import SwiftUI

@main
struct NomadedApp: App {
    var body: some Scene {
        WindowGroup {
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
    }
}
