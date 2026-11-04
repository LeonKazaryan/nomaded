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
    var capital: Bool
}

/// Natural Earth's populated places (~7,300) → the app's city list.
enum CityCatalogBuilder {
    /// Places Natural Earth leaves without an ISO code, given the country the globe shows
    /// them in.
    static let codeFallbacks = ["KOS": "XK", "CYN": "CY", "SOL": "SO"]
    /// Cities renamed since Natural Earth's data; the old names still find them.
    static let renames: [String: (name: String, nameRu: String)] = [
        "Nur-Sultan": ("Astana", "Астана"),
        // Natural Earth has the Soviet "Алма-Ата"; Kazakhstan and Apple Maps say "Алматы".
        "Almaty": ("Almaty", "Алматы"),
    ]
    /// Natural Earth lists a few cities twice, a few kilometres apart (two Aktau, two
    /// Denpasar): closer than this, with one name and one region, they're one city.
    static let duplicateKm = 15.0
    /// Not cities: research stations, ruins.
    static let skippedClasses: Set<String> = ["Scientific station", "Meteorological Station", "Historic place"]

    static func entries(_ url: URL, countries: Set<String>) throws -> [CityEntry] {
        guard
            let root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any],
            let features = root["features"] as? [[String: Any]]
        else { throw PipelineError.malformed("populated places") }

        let entries = features.compactMap { feature -> CityEntry? in
            guard let p = feature["properties"] as? [String: Any],
                  var name = (p["NAME_EN"] as? String) ?? (p["NAME"] as? String),
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
            var nameRu = p["NAME_RU"] as? String
            if let rename = renames[name] {
                aliases += [name, nameRu].compactMap { $0 }
                (name, nameRu) = (rename.name, rename.nameRu)
            }
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
        return withoutDuplicates(entries)
    }

    /// Keeps the bigger of two entries for one city. Twin cities across a border keep both:
    /// Kansas City, Missouri and Kansas City, Kansas are two cities.
    static func withoutDuplicates(_ entries: [CityEntry]) -> [CityEntry] {
        var kept: [CityEntry] = []
        var byCountry: [String: [Int]] = [:]
        for entry in entries {
            let twin = byCountry[entry.code, default: []].first { index in
                let other = kept[index]
                return other.name == entry.name
                    && distanceKm(other.lat, other.lon, entry.lat, entry.lon) < duplicateKm
                    && editDistance(fold(other.region ?? ""), fold(entry.region ?? "")) <= 2
            }
            if let twin {
                // Natural Earth's typos aside ("Kasssrine"), a capital stays one.
                kept[twin].capital = kept[twin].capital || entry.capital
                continue
            }
            byCountry[entry.code, default: []].append(kept.count)
            kept.append(entry)
        }
        return kept
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        var row = Array(0...b.count)
        for i in 1...max(a.count, 1) where !a.isEmpty {
            var previous = row[0]
            row[0] = i
            for j in stride(from: 1, through: b.count, by: 1) {
                let current = row[j]
                row[j] = min(row[j] + 1, row[j - 1] + 1, previous + (a[i - 1] == b[j - 1] ? 0 : 1))
                previous = current
            }
        }
        return row[b.count]
    }

    private static func distanceKm(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let radians = Double.pi / 180
        let dLat = (lat2 - lat1) * radians
        let dLon = (lon2 - lon1) * radians
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1 * radians) * cos(lat2 * radians) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * 6371.0088 * asin(min(1, h.squareRoot()))
    }

    static func encode(_ entries: [CityEntry]) throws -> Data {
        let encoder = JSONEncoder()
        // One line: it's large, and nobody reads it by hand.
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(entries)
    }
}
