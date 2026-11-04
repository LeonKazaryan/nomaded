import Foundation
import StoreKit

/// Which worldview the globe draws: the one for the App Store storefront the app was
/// downloaded from (ADR-015). StoreKit knows it without asking the user for anything. It's
/// remembered, so a launch without an answer from StoreKit still draws the right borders.
/// In Debug the developer zone can force one.
enum WorldviewSource {
    private static let storefrontKey = "storefrontCountry"
    #if DEBUG
    /// "standard", "rus", "chn" or "ind"; unset follows the storefront. Also a launch argument:
    /// `-NomadedDebugWorldview rus`.
    static let overrideKey = "NomadedDebugWorldview"
    #endif

    /// The worldview to load. Waits for StoreKit at most `timeout`, then goes with the
    /// storefront seen last, then with the default.
    static func resolve(timeout: Duration = .seconds(1.5)) async -> Worldview {
        #if DEBUG
        if let forced = UserDefaults.standard.string(forKey: overrideKey).flatMap(Worldview.init(rawValue:)) { return forced }
        #endif
        let code = await storefront(timeout: timeout) ?? lastStorefront
        return code.map(Worldview.init(storefront:)) ?? .standard
    }

    /// The storefront's country (ISO 3166-1 alpha-3) as last seen.
    static var lastStorefront: String? { UserDefaults.standard.string(forKey: storefrontKey) }

    /// Asks StoreKit, and remembers the answer. `nil` without one in time.
    @discardableResult
    static func storefront(timeout: Duration) async -> String? {
        let code = await withTaskGroup(of: String?.self) { group in
            group.addTask { await Storefront.current?.countryCode }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        if let code { UserDefaults.standard.set(code, forKey: storefrontKey) }
        return code
    }
}
