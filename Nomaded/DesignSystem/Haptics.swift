import SwiftUI

/// Haptic vocabulary: each event has exactly one feel, used everywhere.
/// Use with `.sensoryFeedback(Haptics.select, trigger: …)`. The system respects the
/// user's haptics setting on its own.
enum Haptics {
    /// Picking something: a country, a tab.
    static let select = SensoryFeedback.selection
    /// A light confirmation on a button.
    static let tap = SensoryFeedback.impact(weight: .light)
    /// A country was marked as visited.
    static let markVisited = SensoryFeedback.success
    /// The passport stamp lands.
    static let stamp = SensoryFeedback.impact(weight: .heavy)
}
