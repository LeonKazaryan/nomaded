import Foundation

/// One line of the app's `cities.json`: a city search can find instantly, offline, ranked by
/// size, with its capital status.
struct CityEntry: Encodable {
    /// English name.
    let name: String
    let nameRu: String?
    /// Native and plain-Latin spellings worth matching ("Roma", "Sao Paulo").
    let aliases: [String]
    /// First-level region, to tell same-named cities in one country apart.
    let region: String?
    let code: String
    let lat: Double
    let lon: Double
    let population: Int
    let capital: Bool
}

/// Natural Earth's populated places (~7,300) → the app's city list.
enum CityCatalogBuilder {
    /// Places Natural Earth leaves without an ISO code, given the country the globe shows
    /// them in.
    static let codeFallbacks = ["KOS": "XK", "CYN": "CY", "SOL": "SO"]
    /// Not cities: research stations, ruins.
    static let skippedClasses: Set<String> = ["Scientific station", "Meteorological Station", "Historic place"]

    static func entries(_ url: URL, countries: Set<String>) throws -> [CityEntry] {
        guard
            let root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any],
            let features = root["features"] as? [[String: Any]]
        else { throw PipelineError.malformed("populated places") }

        return features.compactMap { feature -> CityEntry? in
            guard let p = feature["properties"] as? [String: Any],
                  let name = (p["NAME_EN"] as? String) ?? (p["NAME"] as? String),
                  let lat = (p["LATITUDE"] as? NSNumber)?.doubleValue,
                  let lon = (p["LONGITUDE"] as? NSNumber)?.doubleValue,
                  !skippedClasses.contains(p["FEATURECLA"] as? String ?? "")
            else { return nil }
            var code = p["ISO_A2"] as? String ?? "-99"
            if code == "-99" { code = codeFallbacks[p["ADM0_A3"] as? String ?? ""] ?? code }
            guard countries.contains(code) else { return nil }

            // NAMEALT is left out: many of its entries are cut off mid-word ("Ciudad de M").
            var aliases: [String] = []
            for key in ["NAME", "NAMEASCII"] {
                if let value = p[key] as? String { aliases.append(value) }
            }
            let nameRu = p["NAME_RU"] as? String
            aliases = Array(Set(aliases.filter { !$0.isEmpty && $0 != name && $0 != nameRu })).sorted()

            return CityEntry(
                name: name,
                nameRu: nameRu,
                aliases: aliases,
                region: p["ADM1NAME"] as? String,
                code: code,
                lat: (lat * 10_000).rounded() / 10_000,
                lon: (lon * 10_000).rounded() / 10_000,
                population: (p["POP_MAX"] as? NSNumber)?.intValue ?? 0,
                // "Admin-0 capital alt" (The Hague) is the seat of government, not the capital.
                capital: (p["ADM0CAP"] as? NSNumber)?.intValue == 1
            )
        }
        .sorted { ($0.population, $1.name) > ($1.population, $0.name) }
    }

    static func encode(_ entries: [CityEntry]) throws -> Data {
        let encoder = JSONEncoder()
        // One line: it's large, and nobody reads it by hand.
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(entries)
    }
}
