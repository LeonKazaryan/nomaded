import SwiftData
import SwiftUI

@main
struct NomadedApp: App {
    @State private var world: WorldStore

    init() {
        let container: ModelContainer
        do {
            container = try WorldStore.makeContainer(ModelConfiguration(isStoredInMemoryOnly: Self.usesScratchStore))
        } catch {
            // Without the store the app can't show or save anything, so fail loudly.
            fatalError("Could not open the visits store: \(error)")
        }
        _world = State(initialValue: WorldStore(container: container))
    }

    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                if UserDefaults.standard.bool(forKey: "NomadedGallery") {
                    DesignSystemGallery()
                } else {
                    GlobeScreen()
                }
                #else
                GlobeScreen()
                #endif
            }
            .environment(world)
        }
    }

    /// Scripted debug runs (`-NomadedDebug…`) start from an empty store in memory, so
    /// screenshots never touch the countries marked by hand.
    private static var usesScratchStore: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("-NomadedDebug") }
        #else
        false
        #endif
    }
}
