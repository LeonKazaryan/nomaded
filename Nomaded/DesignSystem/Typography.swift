import SwiftUI

/// Type scale. Everything is SF Pro Rounded and follows Dynamic Type.
/// For the one big number on a screen use `HeroNumber`, which sizes itself.
enum Typography {
    static let title = Font.system(.title2, design: .rounded, weight: .bold)
    static let headline = Font.system(.headline, design: .rounded, weight: .bold)
    static let body = Font.system(.body, design: .rounded)
    static let label = Font.system(.subheadline, design: .rounded, weight: .semibold)
    static let caption = Font.system(.footnote, design: .rounded, weight: .medium)
    /// Values in stat tiles.
    static let statValue = Font.system(.title, design: .rounded, weight: .semibold)
}
