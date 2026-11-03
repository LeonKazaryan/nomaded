import Foundation

/// A city the user has been to, as the screens see it.
struct CityPin: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    /// State or region, to tell same-named cities apart ("Lazio"). May be empty.
    let region: String
    /// ISO 3166-1 alpha-2 of the country it's in.
    let countryCode: String
    let latitude: Double
    let longitude: Double
    let createdAt: Date
}

/// A city picked in search, before it's saved.
struct CityDraft: Equatable, Sendable {
    let name: String
    let region: String
    let countryCode: String
    let latitude: Double
    let longitude: Double
}

enum CityMath {
    /// Two entries of one name this close are one city: search can place "Rome" a few
    /// kilometres apart depending on the source.
    static let sameNameKm = 25.0
    /// Closer than this, two entries are one place whatever they're called ("Rome" and
    /// "Roma"). Small, so a suburb isn't mistaken for the city next to it.
    static let samePlaceKm = 1.5

    static func isSamePlace(_ city: CityPin, _ draft: CityDraft) -> Bool {
        guard city.countryCode == draft.countryCode else { return false }
        let km = distanceKm(city.latitude, city.longitude, draft.latitude, draft.longitude)
        let sameName = CountrySearchIndex.fold(city.name) == CountrySearchIndex.fold(draft.name)
        return km < samePlaceKm || (sameName && km < sameNameKm)
    }

    /// Great-circle distance (haversine), in kilometres.
    static func distanceKm(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let radians = Double.pi / 180
        let dLat = (lat2 - lat1) * radians
        let dLon = (lon2 - lon1) * radians
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * radians) * cos(lat2 * radians) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * 6371.0088 * asin(min(1, a.squareRoot()))
    }
}
