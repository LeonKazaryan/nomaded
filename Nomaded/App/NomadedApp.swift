import SwiftData
import SwiftUI
import os

@main
struct NomadedApp: App {
    @State private var world: WorldStore
    @State private var cloud: CloudSync

    init() {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "NomadedDebugCloudSchema") { CloudSchema.initialize() }
        #endif
        let store = Self.openStore()
        _world = State(initialValue: WorldStore(container: store.container))
        _cloud = State(initialValue: CloudSync(isSyncing: store.isSyncing))
    }

    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                if UserDefaults.standard.bool(forKey: "NomadedGallery") {
                    DesignSystemGallery()
                } else if UserDefaults.standard.bool(forKey: "NomadedDebugCreative") {
                    CreativeStudio()
                } else {
                    GlobeScreen()
                }
                #else
                GlobeScreen()
                #endif
            }
            .environment(world)
            .environment(cloud)
            .prefersHorizontalBars()
            // Past AX2 a screen with the globe on it can't fit its text any more. Bars stop
            // earlier still and show the large content viewer on a long press instead.
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        }
    }

    /// The store on disk, synced through iCloud. If sync can't be set up, the same store
    /// without it: the marks on this device matter more than the other devices.
    private static func openStore() -> (container: ModelContainer, isSyncing: Bool) {
        do {
            if usesScratchStore { return (try WorldStore.makeContainer(.scratch), false) }
            do {
                return (try WorldStore.makeContainer(.synced), true)
            } catch {
                Logger(subsystem: "com.leonkazaryan.nomaded", category: "App").error("iCloud sync unavailable: \(error)")
                return (try WorldStore.makeContainer(.unsynced), false)
            }
        } catch {
            // Without the store the app can't show or save anything, so fail loudly.
            fatalError("Could not open the visits store: \(error)")
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
