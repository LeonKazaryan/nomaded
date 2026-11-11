import CloudKit
import CoreData
import Foundation
import Observation
import UIKit
import os

/// Whether the user's world is getting to iCloud (ADR-018): if this device can sync at all
/// (signed in, iCloud Drive on), and how the last exchange went. iCloud never asks anyone to
/// sign in, so without this nobody would know their marks stay on one device.
@Observable @MainActor
final class CloudSync {
    enum State: Equatable {
        /// Just launched: not known yet.
        case checking
        /// Syncing. When the last exchange with iCloud finished, if one has since launch.
        case synced(Date?)
        /// This device can't sync: no Apple Account, iCloud Drive off, or not allowed (Screen
        /// Time, a managed device).
        case unavailable
        /// iCloud is on, but the last exchange failed: why, in iCloud's words.
        case failed(String)
        /// The store isn't syncing: it opened without iCloud, or a scripted debug run.
        case off
    }

    private(set) var state: State

    @ObservationIgnored private var observers: [any NSObjectProtocol] = []

    nonisolated private static let log = Logger(subsystem: "com.leonkazaryan.nomaded", category: "iCloud")

    /// `isSyncing`: the store opened with iCloud.
    init(isSyncing: Bool) {
        state = isSyncing ? .checking : .off
        #if DEBUG
        // `-NomadedDebugCloud unavailable` (or `failed`, `synced`, `turnsOn`): what iCloud
        // would say, for a scripted run, which never syncs. `turnsOn` is off, then on 12 s
        // later, as if back from Settings.
        if let forced = UserDefaults.standard.string(forKey: "NomadedDebugCloud") {
            state = switch forced {
            case "unavailable", "turnsOn": .unavailable
            case "failed": .failed("Cannot create or modify field 'CD_countryCode' in record 'CD_Visit' in production schema (CKErrorDomain 15)")
            default: .synced(.now.addingTimeInterval(-120))
            }
            if forced == "turnsOn" {
                Task {
                    try? await Task.sleep(for: .seconds(12))
                    state = .synced(.now)
                }
            }
            return
        }
        #endif
        guard isSyncing else { return }
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main) { [weak self] note in
                guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event,
                      let end = event.endDate
                else { return }
                let name = event.type.name
                let failure = event.error.map(Self.describe)
                MainActor.assumeIsolated { self?.finished(name, at: end, failure: failure) }
            },
            center.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkAccount() }
            },
            // Back from Settings, maybe with iCloud Drive just turned on: that posts no
            // account change.
            center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkAccount() }
            },
        ]
        checkAccount()
    }

    /// Every setup, import and export iCloud finishes goes in the log too: the place to look
    /// when a device doesn't get its marks.
    private func finished(_ name: String, at end: Date, failure: String?) {
        if let failure {
            Self.log.error("iCloud \(name) failed: \(failure)")
            // Without an account every exchange fails; that's better said as unavailable.
            if state != .unavailable { state = .failed(failure) }
        } else {
            Self.log.info("iCloud \(name) done")
            state = .synced(end)
        }
    }

    private func checkAccount() {
        Task {
            let status = try? await CKContainer(identifier: WorldStore.cloudContainer).accountStatus()
            switch status {
            case .available:
                if state == .checking || state == .unavailable { state = .synced(nil) }
            case .noAccount, .restricted, .temporarilyUnavailable:
                state = .unavailable
            default:
                // Offline, say: whatever was known stands.
                break
            }
        }
    }

    /// What went wrong, in iCloud's own words: for a batch, the record that sank it (a schema
    /// missing in production says so there), else the error itself.
    nonisolated static func describe(_ error: any Error) -> String {
        var error = error as NSError
        // Core Data wraps CloudKit's own error.
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError, underlying.domain == CKError.errorDomain {
            error = underlying
        }
        if error.domain == CKError.errorDomain,
           let partials = (error.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: any Error])?.values.map({ $0 as NSError }) {
            // A batch goes in whole or not at all: one record turned down, and every other one
            // comes back as just "Atomic failure", saying nothing. The one that says why is
            // the one that isn't that.
            let sinking = partials.first { $0.code != CKError.batchRequestFailed.rawValue }
            if let partial = sinking ?? partials.first { error = partial }
        }
        return String("\(error.localizedDescription) (\(error.domain) \(error.code))".prefix(300))
    }
}

private extension NSPersistentCloudKitContainer.EventType {
    var name: String {
        switch self {
        case .setup: "setup"
        case .import: "import"
        case .export: "export"
        @unknown default: "event \(rawValue)"
        }
    }
}
