import Foundation
import Observation
import SwiftData
import os

/// The user's visited countries, saved on the device. Every screen marks and unmarks
/// countries through this one store, so the globe, search and stats never disagree.
@Observable @MainActor
final class WorldStore {
    private(set) var visitedCodes: Set<String> = []

    /// Held so it outlives `context`: SwiftData crashes if a container goes away while its
    /// context is still in use.
    @ObservationIgnored private let container: ModelContainer
    @ObservationIgnored private var context: ModelContext { container.mainContext }

    private static let log = Logger(subsystem: "com.leonkazaryan.nomaded", category: "WorldStore")

    init(container: ModelContainer) {
        self.container = container
        reload()
    }

    /// A container for every model the store saves. The default configuration is the app's
    /// store on disk.
    static func makeContainer(_ configuration: ModelConfiguration = ModelConfiguration()) throws -> ModelContainer {
        try ModelContainer(for: Visit.self, configurations: configuration)
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

    /// Removes every visit to the country.
    func unmarkVisited(_ code: String) {
        let visits = FetchDescriptor<Visit>(predicate: #Predicate { $0.countryCode == code })
        do {
            try context.fetch(visits).forEach { context.delete($0) }
        } catch {
            Self.log.error("Unmark \(code) failed: \(error)")
        }
        save()
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
