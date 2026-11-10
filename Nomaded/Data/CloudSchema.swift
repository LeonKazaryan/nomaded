#if DEBUG
import CoreData
import SwiftData
import os

/// The record types iCloud keeps for the store. A development build creates each one the
/// first time it saves such a record, so one never saved (a medal, say) would be missing
/// from the schema deployed to production, and those records would never sync there.
/// `-NomadedDebugCloudSchema YES` sends every type at once, from a device signed in to
/// iCloud; then CloudKit Console → Deploy Schema Changes takes them to production.
enum CloudSchema {
    private static let log = Logger(subsystem: "com.leonkazaryan.nomaded", category: "CloudSchema")

    static func initialize() {
        do {
            // Apple's recipe: a Core Data stack over the same models, in a store of its own
            // that's thrown away after. It goes before SwiftData opens the real one.
            guard let model = NSManagedObjectModel.makeManagedObjectModel(for: [Visit.self, VisitedCity.self, EarnedMilestone.self]) else {
                log.error("No Core Data model for the store")
                return
            }
            let url = URL.temporaryDirectory.appending(path: "CloudSchema.store")
            let description = NSPersistentStoreDescription(url: url)
            description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: WorldStore.cloudContainer)
            description.shouldAddStoreAsynchronously = false
            let container = NSPersistentCloudKitContainer(name: "CloudSchema", managedObjectModel: model)
            container.persistentStoreDescriptions = [description]
            container.loadPersistentStores { _, error in
                if let error { log.error("Schema store failed to load: \(error)") }
            }
            try container.initializeCloudKitSchema()
            for store in container.persistentStoreCoordinator.persistentStores {
                try container.persistentStoreCoordinator.remove(store)
            }
            log.notice("CloudKit schema sent to the development environment")
        } catch {
            log.error("CloudKit schema failed: \(error)")
        }
    }
}
#endif
