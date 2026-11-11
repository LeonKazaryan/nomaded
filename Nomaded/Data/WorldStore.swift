import CoreData
import Foundation
import Observation
import SwiftData
import os

/// The user's visited countries and cities, saved on the device and mirrored to their private
/// iCloud database (ADR-018). Every screen marks and unmarks through this one store, so the
/// globe, search and stats never disagree.
@Observable @MainActor
final class WorldStore {
    /// The iCloud container the store syncs through.
    nonisolated static let cloudContainer = "iCloud.com.leonkazaryan.nomaded"

    private(set) var visitedCodes: Set<String> = []
    /// When each visited country was first marked: the date on its passport stamp.
    private(set) var firstVisits: [String: Date] = [:]
    /// Oldest first.
    private(set) var cities: [CityPin] = []
    /// Milestones reached, and when. Unmarking takes back the ones no longer reached.
    private(set) var milestones: [Milestone: Date] = [:]
    /// The last change synced in from the user's other devices that marked or unmarked
    /// something. `nil` until one comes.
    private(set) var lastSync: SyncedChange?

    /// Held so it outlives `context`: SwiftData crashes if a container goes away while its
    /// context is still in use.
    @ObservationIgnored private let container: ModelContainer
    @ObservationIgnored private var context: ModelContext { container.mainContext }
    @ObservationIgnored private let catalog: CountryCatalog
    @ObservationIgnored private var remoteChanges: (any NSObjectProtocol)?
    @ObservationIgnored private var pendingMerge: Task<Void, Never>?

    nonisolated private static let log = Logger(subsystem: "com.leonkazaryan.nomaded", category: "WorldStore")

    init(container: ModelContainer, catalog: CountryCatalog = .bundled) {
        self.container = container
        self.catalog = catalog
        // Copies of one mark may have come in from another device while the app was closed.
        if removeCopies() { save() } else { reload() }
        // Whatever was reached before milestones existed, or on another device, counts
        // quietly: no flood of celebrations for 90 countries marked last month.
        earnMilestones()
        // iCloud writes what the other devices changed straight into the store, then says so.
        remoteChanges = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleMerge() }
        }
    }

    /// A container for every model the store saves: `.synced` for the app, `.scratch` or
    /// `.unsynced(at:)` for everything else.
    static func makeContainer(_ configuration: ModelConfiguration) throws -> ModelContainer {
        try ModelContainer(for: Visit.self, VisitedCity.self, EarnedMilestone.self, configurations: configuration)
    }

    func isVisited(_ code: String) -> Bool {
        visitedCodes.contains(code)
    }

    /// Adds a visit without dates. Does nothing if the country is already visited.
    func markVisited(_ code: String) {
        guard !isVisited(code) else { return }
        context.insert(Visit(countryCode: code))
        save()
    }

    /// Removes every visit to the country, and its cities with them, and quietly takes back
    /// the milestones that no longer hold: 100 countries down to 90 loses the 100 medal,
    /// the last place on a continent loses the continent.
    func unmarkVisited(_ code: String) {
        let visits = FetchDescriptor<Visit>(predicate: #Predicate { $0.countryCode == code })
        let cities = FetchDescriptor<VisitedCity>(predicate: #Predicate { $0.countryCode == code })
        do {
            try context.fetch(visits).forEach { context.delete($0) }
            try context.fetch(cities).forEach { context.delete($0) }
        } catch {
            Self.log.error("Unmark \(code) failed: \(error)")
        }
        revokeMilestones(visited: visitedCodes.subtracting([code]))
        save()
    }

    func cities(in code: String) -> [CityPin] {
        cities.filter { $0.countryCode == code }
    }

    /// Saves the city and marks its country visited. A city already saved (see
    /// `CityMath.isSamePlace`) isn't added twice; the saved one comes back.
    @discardableResult
    func addCity(_ draft: CityDraft) -> CityPin {
        if let existing = cities.first(where: { CityMath.isSamePlace($0, draft) }) {
            return existing
        }
        let city = VisitedCity(draft)
        context.insert(city)
        if !isVisited(draft.countryCode) {
            context.insert(Visit(countryCode: draft.countryCode))
        }
        save()
        return city.pin
    }

    /// The country stays visited: you were there even without the city.
    func removeCity(_ id: UUID) {
        let match = FetchDescriptor<VisitedCity>(predicate: #Predicate { $0.id == id })
        do {
            try context.fetch(match).forEach { context.delete($0) }
        } catch {
            Self.log.error("Remove city failed: \(error)")
        }
        save()
    }

    /// Saved cities on disputed land go to its owner in the globe's worldview, and mark it
    /// like any city does. Their old country stays marked: there's no telling whether that
    /// was the city's doing. Returns whether anything moved.
    @discardableResult
    func reassignCities(owner: (GeoCoordinate) -> String?) -> Bool {
        do {
            var moved = false
            var marked = visitedCodes
            for city in try context.fetch(FetchDescriptor<VisitedCity>()) {
                guard let code = owner(GeoCoordinate(latitude: city.latitude, longitude: city.longitude)), code != city.countryCode else { continue }
                city.countryCode = code
                if marked.insert(code).inserted { context.insert(Visit(countryCode: code)) }
                moved = true
            }
            if moved { save() }
            return moved
        } catch {
            Self.log.error("Reassigning cities failed: \(error)")
            return false
        }
    }

    /// Everything marked, every city and medal, gone: a fresh start, on every device.
    func resetAll() {
        do {
            // Object by object, like every other delete here, so each one syncs.
            try context.fetch(FetchDescriptor<Visit>()).forEach { context.delete($0) }
            try context.fetch(FetchDescriptor<VisitedCity>()).forEach { context.delete($0) }
            try context.fetch(FetchDescriptor<EarnedMilestone>()).forEach { context.delete($0) }
        } catch {
            Self.log.error("Reset failed: \(error)")
        }
        save()
    }

    /// Records every milestone the visited places now reach that wasn't reached before, and
    /// returns them in celebration order. Call it as a mark is celebrated.
    @discardableResult
    func earnMilestones() -> [Milestone] {
        let new = MilestoneRules.reached(visited: visitedCodes, catalog: catalog).subtracting(milestones.keys)
        guard !new.isEmpty else { return [] }
        new.forEach { context.insert(EarnedMilestone($0)) }
        save()
        return MilestoneRules.celebrationOrder(new)
    }

    /// Deletes the earned milestones `visited` no longer reaches. Doesn't save. Only an unmark
    /// made here takes medals back: a sync caught halfway (the medal in, the countries that
    /// earn it not yet) mustn't take back, on every device, a medal the user still holds.
    private func revokeMilestones(visited: Set<String>) {
        let reached = MilestoneRules.reached(visited: visited, catalog: catalog)
        do {
            for record in try context.fetch(FetchDescriptor<EarnedMilestone>()) {
                guard let milestone = Milestone(id: record.id), !reached.contains(milestone) else { continue }
                context.delete(record)
            }
        } catch {
            Self.log.error("Revoke milestones failed: \(error)")
        }
    }

    /// Saves right away rather than waiting for autosave, so a mark survives the app being
    /// killed a second later (stopping it from Xcode does exactly that).
    private func save() {
        do {
            try context.save()
        } catch {
            Self.log.error("Save failed: \(error)")
        }
        reload()
    }

    /// Reads everything again. Sets only what changed: syncing reloads often, and every set
    /// redraws the screens that read it.
    private func reload() {
        do {
            let visits = try context.fetch(FetchDescriptor<Visit>())
            let visitedCodes = Set(visits.map(\.countryCode))
            let firstVisits = Dictionary(visits.map { ($0.countryCode, $0.createdAt) }, uniquingKeysWith: min)
            let cities = try context.fetch(FetchDescriptor<VisitedCity>(sortBy: [SortDescriptor(\.createdAt)])).map(\.pin)
            let earned = try context.fetch(FetchDescriptor<EarnedMilestone>())
            let milestones = Dictionary(
                earned.compactMap { record in Milestone(id: record.id).map { ($0, record.earnedAt) } },
                uniquingKeysWith: min
            )
            if visitedCodes != self.visitedCodes { self.visitedCodes = visitedCodes }
            if firstVisits != self.firstVisits { self.firstVisits = firstVisits }
            if cities != self.cities { self.cities = cities }
            if milestones != self.milestones { self.milestones = milestones }
        } catch {
            Self.log.error("Fetch failed: \(error)")
        }
    }

    // MARK: - iCloud

    /// An import comes in batches, each with its own notice: a moment's wait takes them
    /// together. Every save made here sends one too; merging after it finds nothing new.
    private func scheduleMerge() {
        guard pendingMerge == nil else { return }
        pendingMerge = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.3))
            self?.pendingMerge = nil
            self?.mergeSyncedChanges()
        }
    }

    /// Takes in what iCloud brought from the user's other devices: copies of one mark made on
    /// two devices become one, and places marked elsewhere count toward milestones quietly,
    /// like anything marked before this device could celebrate it.
    func mergeSyncedChanges() {
        let before = visitedCodes
        if removeCopies() { save() } else { reload() }
        let marked = visitedCodes.subtracting(before)
        let unmarked = before.subtracting(visitedCodes)
        guard !marked.isEmpty || !unmarked.isEmpty else { return }
        if !marked.isEmpty { earnMilestones() }
        lastSync = SyncedChange(marked: marked, unmarked: unmarked, isRestore: before.isEmpty, serial: (lastSync?.serial ?? 0) + 1)
    }

    /// Deletes the records that repeat older ones (`SyncMerge`). Doesn't save; returns
    /// whether it deleted anything.
    private func removeCopies() -> Bool {
        do {
            let visits = SyncMerge.copies(
                in: try context.fetch(FetchDescriptor<Visit>()),
                age: { SyncMerge.Age(made: $0.createdAt, id: $0.id.uuidString) },
                isSame: { $0.countryCode == $1.countryCode && $0.startDate == $1.startDate && $0.endDate == $1.endDate && $0.note == $1.note }
            )
            let cities = SyncMerge.copies(
                in: try context.fetch(FetchDescriptor<VisitedCity>()),
                age: { SyncMerge.Age(made: $0.createdAt, id: $0.id.uuidString) },
                isSame: { CityMath.isSamePlace($0.pin, $1.pin) }
            )
            let medals = SyncMerge.copies(
                in: try context.fetch(FetchDescriptor<EarnedMilestone>()),
                age: { SyncMerge.Age(made: $0.earnedAt, id: $0.id) },
                isSame: { $0.id == $1.id }
            )
            visits.forEach { context.delete($0) }
            cities.forEach { context.delete($0) }
            medals.forEach { context.delete($0) }
            return !visits.isEmpty || !cities.isEmpty || !medals.isEmpty
        } catch {
            Self.log.error("Merging copies failed: \(error)")
            return false
        }
    }

    #if DEBUG
    /// Countries marked on "another device": saved by a context of their own, the way iCloud
    /// writes, then merged as a sync is. `-NomadedDebugSyncMark`.
    func simulateSync(marking codes: [String]) {
        let otherDevice = ModelContext(container)
        codes.forEach { otherDevice.insert(Visit(countryCode: $0)) }
        do {
            try otherDevice.save()
        } catch {
            Self.log.error("Simulated sync failed: \(error)")
        }
        mergeSyncedChanges()
    }

    /// An empty store in memory, for previews.
    static func scratch() -> WorldStore {
        // A failure here is a programming error in the schema, not something to recover from.
        WorldStore(container: try! makeContainer(.scratch))
    }
    #endif
}

/// What the user's other devices changed, as it arrived: for the globe to show it happening.
struct SyncedChange: Equatable {
    /// Countries marked elsewhere…
    let marked: Set<String>
    /// …and unmarked elsewhere.
    let unmarked: Set<String>
    /// Nothing was marked here before: a new device, or a reinstall, getting its world back.
    let isRestore: Bool
    /// Tells two changes with the same countries apart.
    let serial: Int
}

extension ModelConfiguration {
    /// The app's store on disk, mirrored to the user's private iCloud database: their world
    /// is the same on every device and outlives the app being deleted.
    static var synced: ModelConfiguration {
        ModelConfiguration(cloudKitDatabase: .private(WorldStore.cloudContainer))
    }

    /// In memory, never synced: previews, tests, scripted debug runs. With iCloud in the
    /// entitlements SwiftData syncs any store not told otherwise, and test marks would land
    /// in the user's iCloud.
    static var scratch: ModelConfiguration {
        ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    }

    /// The same store on disk without iCloud, for when sync can't be set up.
    static var unsynced: ModelConfiguration {
        ModelConfiguration(cloudKitDatabase: .none)
    }

    /// A store in a file of its own, never synced: tests that relaunch the app.
    static func unsynced(at url: URL) -> ModelConfiguration {
        ModelConfiguration(url: url, cloudKitDatabase: .none)
    }
}
