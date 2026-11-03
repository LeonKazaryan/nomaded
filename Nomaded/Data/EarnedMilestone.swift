import Foundation
import SwiftData

/// A milestone the user has reached, kept for good: unmarking a country doesn't take it
/// back, so it's never celebrated twice.
///
/// CloudKit-compatible like `Visit`: every property has a default, nothing is unique.
@Model
final class EarnedMilestone {
    /// `Milestone.id`.
    var id: String = ""
    var earnedAt: Date = Date.now

    init(_ milestone: Milestone, earnedAt: Date = .now) {
        id = milestone.id
        self.earnedAt = earnedAt
    }
}
