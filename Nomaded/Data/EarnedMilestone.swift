import Foundation
import SwiftData

/// A milestone the user has reached. Unmarking countries below it deletes it, so a country
/// marked by mistake doesn't leave its medal behind.
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
