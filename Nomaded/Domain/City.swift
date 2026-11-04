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

    /// The same city under another name, for display.
    func renamed(_ name: String) -> CityPin {
        CityPin(id: id, name: name, region: region, countryCode: countryCode, latitude: latitude, longitude: longitude, createdAt: createdAt)
    }
}

/// A city picked in search, before it's saved.
struct CityDraft: Equatable, Sendable {
    let name: String
    let region: String
    let countryCode: String
    let latitude: Double
    let longitude: Double
}

enum PlaceNames {
    /// The language the app's own strings came out in ("en" or "ru").
    static var appLanguage: String { Bundle.main.preferredLocalizations.first ?? "en" }

    /// A name in letters the app's language reads. Cities the bundled list knows already come
    /// in that language; this is for the rest, as Maps or the user's own search typed them.
    /// An English app gets Cyrillic the way English spells Russian names ("Шымкент" →
    /// "Shymkent"); a Russian app keeps Cyrillic and Latin as they are; other scripts
    /// become Latin in both.
    static func readable(_ name: String, language: String = appLanguage) -> String {
        let readsCyrillic = language.hasPrefix("ru")
        let isForeign = name.unicodeScalars.contains { scalar in
            guard scalar.properties.isAlphabetic, !isLatin(scalar) else { return false }
            return !(readsCyrillic && (0x400...0x52F).contains(scalar.value))
        }
        guard isForeign,
              let latin = name.applyingTransform(StringTransform("Russian-Latin/BGN; Any-Latin; Latin-ASCII"), reverse: false)
        else { return name }
        // Soft signs and Kazakh marks come out as apostrophes nobody writes: "Ust'-Kamenogorsk".
        let plain = latin.filter { !"'ʹˌ".contains($0) }
        // Scripts without capitals come out all lowercase: "bei jing".
        return plain == plain.lowercased() ? plain.capitalized : plain
    }

    private static func isLatin(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value < 0x250 || (0x1E00...0x1EFF).contains(scalar.value)
    }
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
