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
    /// Closer than this, two cities in the same country are the same city: search can
    /// return "Rome" a few hundred metres apart depending on the query.
    static let sameCityKm = 10.0

    static func isSamePlace(_ city: CityPin, _ draft: CityDraft) -> Bool {
        city.countryCode == draft.countryCode
            && distanceKm(city.latitude, city.longitude, draft.latitude, draft.longitude) < sameCityKm
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
