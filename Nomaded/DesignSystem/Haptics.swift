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
    /// A new city's dot touches down on the globe.
    static let cityLanded = SensoryFeedback.impact(weight: .medium)
    /// One half-turn of a spinning milestone medal; `intensity` fades as it slows.
    static func coinTick(_ intensity: Double) -> SensoryFeedback { .impact(weight: .light, intensity: intensity) }
    /// A milestone medal lands.
    static let medalLanded = SensoryFeedback.impact(weight: .heavy)
    /// A milestone's title appears.
    static let milestone = SensoryFeedback.success
    /// The user's world came back from iCloud.
    static let restored = SensoryFeedback.success
    /// A story film is ready to share.
    static let storyReady = SensoryFeedback.success
    /// The zoom rail hits its closest or farthest end.
    static let zoomLimit = SensoryFeedback.impact(weight: .light, intensity: 0.6)
    /// A letter of the welcome title lands: barely there.
    static let letter = SensoryFeedback.impact(weight: .light, intensity: 0.35)
}
