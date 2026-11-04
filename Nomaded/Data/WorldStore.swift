import Foundation
import Observation
import SwiftData
import os

/// The user's visited countries and cities, saved on the device. Every screen marks and
/// unmarks through this one store, so the globe, search and stats never disagree.
@Observable @MainActor
final class WorldStore {
    private(set) var visitedCodes: Set<String> = []
    /// When each visited country was first marked: the date on its passport stamp.
    private(set) var firstVisits: [String: Date] = [:]
    /// Oldest first.
    private(set) var cities: [CityPin] = []
    /// Milestones reached, and when. Unmarking takes back the ones no longer reached.
    private(set) var milestones: [Milestone: Date] = [:]

    /// Held so it outlives `context`: SwiftData crashes if a container goes away while its
    /// context is still in use.
    @ObservationIgnored private let container: ModelContainer
    @ObservationIgnored private var context: ModelContext { container.mainContext }
    @ObservationIgnored private let catalog: CountryCatalog

    private static let log = Logger(subsystem: "com.leonkazaryan.nomaded", category: "WorldStore")

    init(container: ModelContainer, catalog: CountryCatalog = .bundled) {
        self.container = container
        self.catalog = catalog
        reload()
        // Medals left over from before unmarking took them back go…
        revokeMilestones(visited: visitedCodes)
        if context.hasChanges { save() }
        // …and whatever was reached before milestones existed counts quietly: no flood of
        // celebrations for 90 countries marked last month.
        earnMilestones()
    }

    /// A container for every model the store saves. The default configuration is the app's
    /// store on disk.
    static func makeContainer(_ configuration: ModelConfiguration = ModelConfiguration()) throws -> ModelContainer {
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

    /// Deletes the earned milestones `visited` no longer reaches. Doesn't save.
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

    private func reload() {
        do {
            let visits = try context.fetch(FetchDescriptor<Visit>())
            visitedCodes = Set(visits.map(\.countryCode))
            firstVisits = Dictionary(visits.map { ($0.countryCode, $0.createdAt) }, uniquingKeysWith: min)
            let cities = try context.fetch(FetchDescriptor<VisitedCity>(sortBy: [SortDescriptor(\.createdAt)]))
            self.cities = cities.map(\.pin)
            let earned = try context.fetch(FetchDescriptor<EarnedMilestone>())
            milestones = Dictionary(
                earned.compactMap { record in Milestone(id: record.id).map { ($0, record.earnedAt) } },
                uniquingKeysWith: min
            )
        } catch {
            Self.log.error("Fetch failed: \(error)")
        }
    }

    #if DEBUG
    /// An empty store in memory, for previews.
    static func scratch() -> WorldStore {
        // A failure here is a programming error in the schema, not something to recover from.
        WorldStore(container: try! makeContainer(ModelConfiguration(isStoredInMemoryOnly: true)))
    }
    #endif
}
