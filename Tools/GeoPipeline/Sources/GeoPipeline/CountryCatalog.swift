import Foundation

/// One line of the app's `countries.json`: what the statistics need about each place.
struct CatalogEntry: Encodable {
    let code: String
    /// One of the app's `Continent` raw values.
    let continent: String
    /// UN M49 subregion, e.g. "Western Europe".
    let subregion: String
    /// One of the 195 countries "% of the world" counts. Everything else is a territory.
    let sovereign: Bool
    let areaKm2: Double
}

enum CountryCatalog {
    /// The 193 UN members plus the Vatican and Palestine (docs/01-product.md, "Definitions").
    /// Taiwan, Kosovo and Western Sahara are on the globe but count as territories.
    static let sovereign: Set<String> = [
        // Africa
        "DZ", "AO", "BJ", "BW", "BF", "BI", "CV", "CM", "CF", "TD", "KM", "CG", "CD", "CI", "DJ", "EG", "GQ", "ER",
        "SZ", "ET", "GA", "GM", "GH", "GN", "GW", "KE", "LS", "LR", "LY", "MG", "MW", "ML", "MR", "MU", "MA", "MZ",
        "NA", "NE", "NG", "RW", "ST", "SN", "SC", "SL", "SO", "ZA", "SS", "SD", "TZ", "TG", "TN", "UG", "ZM", "ZW",
        // Asia
        "AF", "AM", "AZ", "BH", "BD", "BT", "BN", "KH", "CN", "CY", "GE", "IN", "ID", "IR", "IQ", "IL", "JP", "JO",
        "KZ", "KW", "KG", "LA", "LB", "MY", "MV", "MN", "MM", "NP", "KP", "OM", "PK", "PS", "PH", "QA", "SA", "SG",
        "KR", "LK", "SY", "TJ", "TH", "TL", "TR", "TM", "AE", "UZ", "VN", "YE",
        // Europe
        "AL", "AD", "AT", "BY", "BE", "BA", "BG", "HR", "CZ", "DK", "EE", "FI", "FR", "DE", "GR", "HU", "IS", "IE",
        "IT", "LV", "LI", "LT", "LU", "MT", "MD", "MC", "ME", "NL", "MK", "NO", "PL", "PT", "RO", "RU", "SM", "RS",
        "SK", "SI", "ES", "SE", "CH", "UA", "GB", "VA",
        // North America
        "AG", "BS", "BB", "BZ", "CA", "CR", "CU", "DM", "DO", "SV", "GD", "GT", "HT", "HN", "JM", "MX", "NI", "PA",
        "KN", "LC", "VC", "TT", "US",
        // South America
        "AR", "BO", "BR", "CL", "CO", "EC", "GY", "PY", "PE", "SR", "UY", "VE",
        // Oceania
        "AU", "FJ", "KI", "MH", "FM", "NR", "NZ", "PW", "PG", "WS", "SB", "TO", "TV", "VU",
    ]

    /// Natural Earth puts a few island places in "Seven seas (open ocean)". These follow
    /// the UN M49 geoscheme instead.
    static let overrides: [String: (continent: String, subregion: String)] = [
        "SC": ("africa", "Eastern Africa"),
        "MU": ("africa", "Eastern Africa"),
        "IO": ("africa", "Eastern Africa"),
        "TF": ("africa", "Eastern Africa"),
        "SH": ("africa", "Western Africa"),
        "MV": ("asia", "Southern Asia"),
        "HM": ("oceania", "Australia and New Zealand"),
        "UM": ("oceania", "Micronesia"),
        "GS": ("southAmerica", "South America"),
    ]

    static let continents: [String: String] = [
        "Africa": "africa",
        "Antarctica": "antarctica",
        "Asia": "asia",
        "Europe": "europe",
        "North America": "northAmerica",
        "Oceania": "oceania",
        "South America": "southAmerica",
    ]

    static func entries(_ countries: [CountryInput]) throws -> [CatalogEntry] {
        let entries = try countries.filter { !$0.code.isEmpty }.map { country in
            let override = overrides[country.code]
            guard let continent = override?.continent ?? continents[country.main.continent] else {
                throw PipelineError.malformed("no continent for \(country.code) (\(country.main.continent))")
            }
            let subregion = override?.subregion ?? country.main.subregion
            guard !subregion.hasPrefix("Seven seas") else {
                throw PipelineError.malformed("no subregion for \(country.code)")
            }
            let area = country.polygons.reduce(0) { $0 + Sphere.areaKm2($1) }
            return CatalogEntry(
                code: country.code,
                continent: continent,
                subregion: subregion,
                sovereign: sovereign.contains(country.code),
                // Two decimals keep the Vatican (0.44 km²) without noise on Russia.
                areaKm2: (area * 100).rounded() / 100
            )
        }
        let missing = sovereign.subtracting(entries.map(\.code))
        guard missing.isEmpty else { throw PipelineError.malformed("countries missing from the data: \(missing.sorted())") }
        return entries.sorted { $0.code < $1.code }
    }

    static func encode(_ entries: [CatalogEntry]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(entries)
    }
}

extension Sphere {
    static let earthRadiusKm = 6371.0088

    /// Area on the sphere: the outer ring minus the holes. Same ring formula as d3 and
    /// Turf, accurate to well under 1% for countries.
    static func areaKm2(_ polygon: GeoPolygon) -> Double {
        guard let outer = polygon.rings.first else { return 0 }
        return max(0, ringArea(outer) - polygon.rings.dropFirst().reduce(0) { $0 + ringArea($1) })
    }

    private static func ringArea(_ ring: [GeoPoint]) -> Double {
        guard ring.count > 2 else { return 0 }
        var total = 0.0
        for i in ring.indices {
            let previous = ring[(i + ring.count - 1) % ring.count]
            let next = ring[(i + 1) % ring.count]
            total += (next.x - previous.x) * .pi / 180 * sin(ring[i].y * .pi / 180)
        }
        return abs(total) * earthRadiusKm * earthRadiusKm / 2
    }
}
