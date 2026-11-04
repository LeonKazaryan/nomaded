import Foundation
import SwiftData
import Testing
@testable import Nomaded

@MainActor
struct WorldStoreTests {
    private let container: ModelContainer

    init() throws {
        container = try WorldStore.makeContainer(ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private var visitCount: Int {
        (try? container.mainContext.fetchCount(FetchDescriptor<Visit>())) ?? -1
    }

    @Test func startsEmpty() {
        #expect(WorldStore(container: container).visitedCodes.isEmpty)
    }

    @Test func markAndUnmark() {
        let store = WorldStore(container: container)
        store.markVisited("IT")
        store.markVisited("FR")
        #expect(store.visitedCodes == ["IT", "FR"])

        store.unmarkVisited("IT")
        #expect(store.visitedCodes == ["FR"])
        #expect(!store.isVisited("IT"))
    }

    @Test func markingTwiceKeepsOneVisit() {
        let store = WorldStore(container: container)
        store.markVisited("KZ")
        store.markVisited("KZ")
        #expect(visitCount == 1)
    }

    @Test func unmarkRemovesEveryTrip() throws {
        let context = container.mainContext
        context.insert(Visit(countryCode: "JP"))
        context.insert(Visit(countryCode: "JP"))
        context.insert(Visit(countryCode: "KR"))
        try context.save()

        let store = WorldStore(container: container)
        #expect(store.visitedCodes == ["JP", "KR"])

        store.unmarkVisited("JP")
        #expect(store.visitedCodes == ["KR"])
        #expect(visitCount == 1)
    }

    private static let rome = CityDraft(name: "Rome", region: "Lazio", countryCode: "IT", latitude: 41.9, longitude: 12.5)

    @Test func addingACityMarksItsCountry() {
        let store = WorldStore(container: container)
        let city = store.addCity(Self.rome)

        #expect(store.isVisited("IT"))
        #expect(store.cities == [city])
        #expect(store.cities(in: "IT").map(\.name) == ["Rome"])
    }

    @Test func theSameCityIsNotAddedTwice() {
        let store = WorldStore(container: container)
        let first = store.addCity(Self.rome)
        // A few kilometres off, as Rome from another source might be.
        let again = store.addCity(CityDraft(name: "Rome", region: "", countryCode: "IT", latitude: 41.93, longitude: 12.48))

        #expect(again == first)
        #expect(store.cities.count == 1)
    }

    @Test func removingACityKeepsTheCountry() throws {
        let store = WorldStore(container: container)
        let city = store.addCity(Self.rome)
        store.removeCity(city.id)

        #expect(store.cities.isEmpty)
        #expect(store.isVisited("IT"))
    }

    @Test func unmarkingACountryRemovesItsCities() {
        let store = WorldStore(container: container)
        store.addCity(Self.rome)
        store.addCity(CityDraft(name: "Paris", region: "", countryCode: "FR", latitude: 48.86, longitude: 2.35))
        store.unmarkVisited("IT")

        #expect(store.cities.map(\.countryCode) == ["FR"])
        #expect(store.visitedCodes == ["FR"])
    }

    /// Installs from before cities had a store with visits only. It must open with the new
    /// model and keep every mark.
    @Test func aStoreWithoutCitiesStillOpens() throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: "visits.store")

        do {
            let old = try ModelContainer(for: Visit.self, configurations: ModelConfiguration(url: file))
            old.mainContext.insert(Visit(countryCode: "JP"))
            try old.mainContext.save()
        }
        let store = WorldStore(container: try WorldStore.makeContainer(ModelConfiguration(url: file)))
        #expect(store.visitedCodes == ["JP"])
        #expect(store.cities.isEmpty)

        store.addCity(CityDraft(name: "Kyoto", region: "", countryCode: "JP", latitude: 35.01, longitude: 135.77))
        #expect(store.cities.count == 1)
    }

    private static let catalog = CountryCatalog([
        Country(code: "FR", continent: .europe, subregion: .westernEurope, isSovereign: true, areaKm2: 1),
        Country(code: "JP", continent: .asia, subregion: .easternAsia, isSovereign: true, areaKm2: 1),
        Country(code: "GL", continent: .northAmerica, subregion: .northernAmerica, isSovereign: false, areaKm2: 1),
    ] + (0..<12).map { Country(code: "X\($0)", continent: .africa, subregion: .easternAfrica, isSovereign: true, areaKm2: 1) })

    @Test func milestonesAreEarnedOnce() {
        let store = WorldStore(container: container, catalog: Self.catalog)
        store.markVisited("FR")
        #expect(store.earnMilestones() == [.continent(.europe)])
        store.markVisited("JP")
        #expect(store.earnMilestones() == [.continent(.asia)])
        #expect(store.earnMilestones().isEmpty)
    }

    /// Marked by mistake, unmarked: the medal goes. Reached again for real, it's celebrated again.
    @Test func unmarkingTakesBackAContinent() {
        let store = WorldStore(container: container, catalog: Self.catalog)
        store.markVisited("FR")
        store.markVisited("JP")
        store.earnMilestones()

        store.unmarkVisited("JP")
        #expect(store.milestones.keys.sorted { $0.id < $1.id } == [.continent(.europe)])

        store.markVisited("JP")
        #expect(store.earnMilestones() == [.continent(.asia)])
    }

    @Test func droppingBelowACountThresholdTakesItBack() {
        let store = WorldStore(container: container, catalog: Self.catalog)
        (0..<10).forEach { store.markVisited("X\($0)") }
        store.earnMilestones()
        #expect(store.milestones[.countries(10)] != nil)

        store.unmarkVisited("X3")
        #expect(store.milestones[.countries(10)] == nil)
        // Africa still has nine marks.
        #expect(store.milestones[.continent(.africa)] != nil)
    }

    /// Medals earned before unmarking took them back are cleaned up at launch.
    @Test func leftoverMilestonesGoAtLaunch() throws {
        let context = container.mainContext
        context.insert(Visit(countryCode: "FR"))
        context.insert(EarnedMilestone(.continent(.europe)))
        context.insert(EarnedMilestone(.continent(.antarctica)))
        context.insert(EarnedMilestone(.countries(10)))
        try context.save()

        let store = WorldStore(container: container, catalog: Self.catalog)
        #expect(Array(store.milestones.keys) == [.continent(.europe)])
    }

    @Test func tenCountriesAndATerritoryContinent() {
        let store = WorldStore(container: container, catalog: Self.catalog)
        (0..<10).forEach { store.markVisited("X\($0)") }
        store.markVisited("GL")
        // Greenland is a territory: it opens North America but doesn't count to ten.
        #expect(store.earnMilestones() == [.continent(.africa), .continent(.northAmerica), .countries(10)])
    }

    /// Marks from before milestones existed count without a celebration.
    @Test func existingMarksCountQuietly() throws {
        let context = container.mainContext
        (0..<11).forEach { context.insert(Visit(countryCode: "X\($0)")) }
        try context.save()

        let store = WorldStore(container: container, catalog: Self.catalog)
        #expect(store.milestones.keys.contains(.countries(10)))
        #expect(store.earnMilestones().isEmpty)
    }

    @Test func milestoneIDsRoundTrip() {
        for milestone in Milestone.all {
            #expect(Milestone(id: milestone.id) == milestone)
        }
        #expect(Milestone(id: "countries.11") == nil)
    }

    @Test func visitsSurviveARelaunch() throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: "visits.store")

        do {
            let store = WorldStore(container: try WorldStore.makeContainer(ModelConfiguration(url: file)))
            store.markVisited("PT")
            store.markVisited("ES")
            store.unmarkVisited("ES")
        }
        let relaunched = WorldStore(container: try WorldStore.makeContainer(ModelConfiguration(url: file)))
        #expect(relaunched.visitedCodes == ["PT"])
    }
}
