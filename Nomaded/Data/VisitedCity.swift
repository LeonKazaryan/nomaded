import Foundation
import SwiftData

/// A city the user has been to, with where it is, so the globe can pin it.
///
/// CloudKit-compatible like `Visit`: every property has a default, nothing is unique.
@Model
final class VisitedCity {
    var id: UUID = UUID()
    var name: String = ""
    /// State or region, to tell same-named cities apart. May be empty.
    var region: String = ""
    /// ISO 3166-1 alpha-2. Adding a city marks its country visited.
    var countryCode: String = ""
    var latitude: Double = 0
    var longitude: Double = 0
    var createdAt: Date = Date.now

    init(_ draft: CityDraft, createdAt: Date = .now) {
        name = draft.name
        region = draft.region
        countryCode = draft.countryCode
        latitude = draft.latitude
        longitude = draft.longitude
        self.createdAt = createdAt
    }

    var pin: CityPin {
        CityPin(id: id, name: name, region: region, countryCode: countryCode, latitude: latitude, longitude: longitude, createdAt: createdAt)
    }
}
