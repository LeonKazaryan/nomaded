import Foundation
import SwiftData

/// One trip to a country. A country counts as visited while it has at least one visit.
///
/// Kept CloudKit-compatible so iCloud sync can be switched on later without a migration:
/// every property has a default, nothing is `@Attribute(.unique)`.
@Model
final class Visit {
    var id: UUID = UUID()
    /// ISO 3166-1 alpha-2, the same code the globe and search use.
    var countryCode: String = ""
    /// `nil` = "I was there, but I don't remember when".
    var startDate: Date?
    var endDate: Date?
    /// Unused: cities live in `VisitedCity`, with coordinates. Kept so stores on existing
    /// installs open without a migration.
    var cities: [String] = []
    var note: String = ""
    var createdAt: Date = Date.now

    init(countryCode: String, createdAt: Date = .now) {
        self.countryCode = countryCode
        self.createdAt = createdAt
    }
}
