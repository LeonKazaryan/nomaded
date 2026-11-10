import Foundation
import SwiftData
import Testing
@testable import Nomaded

/// What iCloud brings from the user's other devices. Another context saving into the same
/// store stands in for the import: that's how iCloud writes, too.
@MainActor
struct WorldStoreSyncTests {
    private let container: ModelContainer
    /// The other device, as its records arrive here.
    private let otherDevice: ModelContext

    init() throws {
        container = try WorldStore.makeContainer(.scratch)
        otherDevice = ModelContext(container)
    }

    private static let lastWeek = Date.now.addingTimeInterval(-7 * 86_400)
    private static let rome = CityDraft(name: "Rome", region: "Lazio", countryCode: "IT", latitude: 41.9, longitude: 12.5)

    private func count<Model: PersistentModel>(_ model: Model.Type) -> Int {
        (try? container.mainContext.fetchCount(FetchDescriptor<Model>())) ?? -1
    }

    @Test func theSameCountryFromTwoDevicesIsOneVisit() throws {
        let store = WorldStore(container: container)
        store.markVisited("IT")
        otherDevice.insert(Visit(countryCode: "IT", createdAt: Self.lastWeek))
        try otherDevice.save()

        store.mergeSyncedChanges()
        #expect(count(Visit.self) == 1)
        // The older mark is the one kept, and with it its date.
        #expect(store.firstVisits["IT"] == Self.lastWeek)
        // Nothing new here: Italy was already marked.
        #expect(store.lastSync == nil)
    }

    @Test func theSameCityFromTwoDevicesIsOneCity() throws {
        let store = WorldStore(container: container)
        store.addCity(Self.rome)
        // Rome as the other device's search placed it, a little off.
        let theirs = VisitedCity(CityDraft(name: "Rome", region: "", countryCode: "IT", latitude: 41.93, longitude: 12.48), createdAt: Self.lastWeek)
        otherDevice.insert(theirs)
        otherDevice.insert(Visit(countryCode: "IT", createdAt: Self.lastWeek))
        try otherDevice.save()

        store.mergeSyncedChanges()
        #expect(store.cities.map(\.id) == [theirs.id])
        #expect(count(Visit.self) == 1)
    }

    @Test func aMedalEarnedOnBothKeepsTheFirstDate() throws {
        let store = WorldStore(container: container)
        store.markVisited("FR")
        store.earnMilestones()
        otherDevice.insert(Visit(countryCode: "FR", createdAt: Self.lastWeek))
        otherDevice.insert(EarnedMilestone(.continent(.europe), earnedAt: Self.lastWeek))
        try otherDevice.save()

        store.mergeSyncedChanges()
        #expect(count(EarnedMilestone.self) == 1)
        #expect(store.milestones[.continent(.europe)] == Self.lastWeek)
    }

    @Test func aWorldArrivingOnANewDeviceIsARestore() throws {
        let store = WorldStore(container: container)
        ["FR", "IT", "JP"].forEach { otherDevice.insert(Visit(countryCode: $0, createdAt: Self.lastWeek)) }
        try otherDevice.save()

        store.mergeSyncedChanges()
        #expect(store.visitedCodes == ["FR", "IT", "JP"])
        #expect(store.lastSync?.marked == ["FR", "IT", "JP"])
        #expect(store.lastSync?.isRestore == true)
    }

    @Test func unmarkedOnTheOtherDevice() throws {
        let store = WorldStore(container: container)
        store.markVisited("FR")
        store.markVisited("IT")
        try otherDevice.fetch(FetchDescriptor<Visit>(predicate: #Predicate { $0.countryCode == "FR" })).forEach { otherDevice.delete($0) }
        try otherDevice.save()

        store.mergeSyncedChanges()
        #expect(store.visitedCodes == ["IT"])
        #expect(store.lastSync?.unmarked == ["FR"])
        #expect(store.lastSync?.marked.isEmpty == true)
        #expect(store.lastSync?.isRestore == false)
    }

    /// Every save here sends the same notice an import does: it mustn't look like one.
    @Test func ownMarksAreNotSyncedChanges() {
        let store = WorldStore(container: container)
        store.markVisited("JP")
        store.mergeSyncedChanges()
        #expect(store.lastSync == nil)
    }

    /// Ten countries marked on the iPhone don't set off a celebration on the iPad.
    @Test func countriesFromElsewhereCountQuietly() throws {
        let store = WorldStore(container: container)
        ["FR", "IT", "ES", "PT", "DE", "NL", "BE", "CH", "AT", "GR"].forEach {
            otherDevice.insert(Visit(countryCode: $0, createdAt: Self.lastWeek))
        }
        try otherDevice.save()

        store.mergeSyncedChanges()
        #expect(store.milestones[.countries(10)] != nil)
        #expect(store.earnMilestones().isEmpty)
    }

    /// Each change gets its own number, so the same countries arriving twice are two events.
    @Test func changesAreNumbered() throws {
        let store = WorldStore(container: container)
        otherDevice.insert(Visit(countryCode: "FR"))
        try otherDevice.save()
        store.mergeSyncedChanges()
        let first = store.lastSync

        try otherDevice.fetch(FetchDescriptor<Visit>()).forEach { otherDevice.delete($0) }
        try otherDevice.save()
        store.mergeSyncedChanges()
        otherDevice.insert(Visit(countryCode: "FR"))
        try otherDevice.save()
        store.mergeSyncedChanges()

        #expect(store.lastSync?.marked == first?.marked)
        #expect(store.lastSync != first)
    }
}
