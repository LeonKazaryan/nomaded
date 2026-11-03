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
