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
}
