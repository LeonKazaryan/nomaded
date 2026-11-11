import SwiftUI

/// Animation tokens from docs/02-design.md. Feature code uses these, never raw values.
enum Motion {
    /// Button press-in.
    static let press = Animation.spring(duration: 0.2, bounce: 0.2)
    /// Toggles and small state changes.
    static let snappy = Animation.spring(duration: 0.3, bounce: 0.15)
    /// Cards appearing, things popping in.
    static let bouncy = Animation.spring(duration: 0.5, bounce: 0.35)
    /// Large moves without overshoot.
    static let smooth = Animation.spring(duration: 0.6, bounce: 0)
    /// Celebrations.
    static let celebrate = Animation.spring(duration: 0.7, bounce: 0.5)
    /// Something pressed down hard, like the passport stamp: fast, one small rebound.
    static let slam = Animation.spring(duration: 0.34, bounce: 0.3)
    /// A tossed coin spinning out: fast at first, settling without wobble.
    static let coinSpin = Animation.spring(duration: 1.4, bounce: 0)

    /// Things that pop in one by one and are drawn frame by frame (countries on the
    /// statistics maps). Same feel as `bouncy`, as a `Spring` you can sample at any time.
    static let pop = Spring(duration: 0.55, bounce: 0.45)
    /// A ring spreading off something, slowing as it fades, like the one that crosses the
    /// globe when a country is marked. A `Spring`, for keyframes.
    static let ripple = Spring(duration: 0.9, bounce: 0)
    /// Delay between items of a cascade (docs/02-design.md: 30–50 ms).
    static let stagger = 0.05
}
