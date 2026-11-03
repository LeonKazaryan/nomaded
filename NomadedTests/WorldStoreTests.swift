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
