import Foundation

/// GeoNames (geonames.org, CC BY 4.0) → the app's city list, `cities.nmcity` (`CityTable`).
///
/// Which places: every town of 5,000 people or more, smaller ones the world knows by name,
/// and every capital. Fame is how many languages name a place: Tsaghkadzor, a ski resort of
/// 1,100 people, has 34 names, a village of the same size two or three. Names: English, and
/// Russian where GeoNames has a real one; the rest keep their own in Latin letters.
enum CityCatalogBuilder {
    /// The GeoNames dump files, as downloaded (see the README).
    struct Source {
        let cities: URL
        let alternateNames: URL
        let regions: URL
        let countries: URL

        init(folder: URL) {
            cities = folder.appending(path: "cities1000.txt")
            alternateNames = folder.appending(path: "alternateNamesV2.txt")
            regions = folder.appending(path: "admin1CodesASCII.txt")
            countries = folder.appending(path: "countryInfo.txt")
        }
    }

    /// Towns and cities; not "sections of populated places" (city districts), abandoned,
    /// destroyed or historical ones.
    static let featureCodes: Set<String> = ["PPL", "PPLA", "PPLA2", "PPLA3", "PPLA4", "PPLA5", "PPLC", "PPLG", "PPLL", "PPLS", "PPLF", "PPLR", "STLMT"]
    static let minimumPopulation = 5_000
    /// Smaller places come in with at least this many names in other languages.
    static let famousNames = 8
    /// One name, one region, closer than this: one city listed twice.
    static let duplicateKm = 15.0
    /// Capitals GeoNames doesn't mark as such, by country: geonameid.
    static let unmarkedCapitals = ["IL": 281_184]

    private struct Place {
        let id: Int
        let name: String
        let asciiName: String
        let latitude: Double
        let longitude: Double
        let countryCode: String
        let region: String
        let population: Int
        let isCapital: Bool
        let fame: Int
    }

    private struct Name {
        let text: String
        let isPreferred: Bool
        let isColloquial: Bool
        let isHistoric: Bool
        var isCurrent: Bool { !isColloquial && !isHistoric }
    }

    /// - Parameters:
    ///   - countries: The codes the globe has; a city goes on one of them or nowhere.
    ///   - owner: Who disputed land belongs to in the default worldview, over GeoNames' say.
    ///   - countryAt: The globe's country at a point, for places GeoNames files under a code
    ///     the globe draws as part of another (Réunion: France).
    static func rows(_ source: Source, countries: Set<String>, owner: (GeoPoint) -> String?, countryAt: (GeoPoint) -> String?) throws -> [CityTable.Row] {
        let languages = try countryLanguages(source.countries)
        let regions = try regionNames(source.regions)

        var places: [Place] = []
        try forEachLine(source.cities) { fields in
            guard fields.count >= 15, featureCodes.contains(fields[7]) else { return }
            let id = Int(fields[0]) ?? 0
            let population = Int(fields[14]) ?? 0
            let isCapital = fields[7] == "PPLC" || unmarkedCapitals[fields[8]] == id
            let fame = Set(fields[3].split(separator: ",")).count
            guard isCapital || population >= minimumPopulation || fame >= famousNames else { return }
            places.append(Place(
                id: id, name: fields[1], asciiName: fields[2],
                latitude: Double(fields[4]) ?? 0, longitude: Double(fields[5]) ?? 0,
                countryCode: fields[8], region: fields[8] + "." + fields[10],
                population: population, isCapital: isCapital, fame: fame
            ))
        }

        // Every name of those places and their regions in English, Russian and the
        // country's own languages: the one file with all of them is 800 MB, so it's
        // streamed and only these are kept.
        var wanted: [Int: Set<String>] = [:]
        for place in places { wanted[place.id] = languages[place.countryCode, default: []].union(["en", "ru"]) }
        for region in regions.values { wanted[region.id, default: []].formUnion(["en", "ru"]) }
        var names: [Int: [String: [Name]]] = [:]
        try forEachLine(source.alternateNames, keepingID: { wanted[$0] != nil }) { fields in
            guard fields.count >= 8, let id = Int(fields[1]), let languages = wanted[id], languages.contains(fields[2]) else { return }
            names[id, default: [:]][fields[2], default: []].append(Name(
                text: fields[3], isPreferred: fields[4] == "1", isColloquial: fields[6] == "1", isHistoric: fields[7] == "1"
            ))
        }

        func english(_ id: Int, fallback: String) -> String {
            names[id]?["en"]?.first { $0.isPreferred && $0.isCurrent }?.text ?? fallback
        }
        func russian(_ id: Int) -> String? {
            let current = names[id]?["ru"]?.filter(\.isCurrent) ?? []
            return (current.first(where: \.isPreferred) ?? current.first)?.text
        }

        var rows: [(row: CityTable.Row, key: String, region: String)] = []
        var kept: [String: [Int]] = [:]
        for place in places.sorted(by: { ($0.population, $1.id) > ($1.population, $0.id) }) {
            let point = GeoPoint(place.longitude, place.latitude)
            guard let code = owner(point) ?? (countries.contains(place.countryCode) ? place.countryCode : countryAt(point)),
                  countries.contains(code)
            else { continue }
            let name = english(place.id, fallback: place.name)
            let key = CityKey.key(name)
            // GeoNames lists a few towns twice: an older entry next to the current one.
            if let twin = kept[code, default: []].first(where: { index in
                rows[index].key == key && rows[index].region == place.region
                    && distanceKm(rows[index].row.latitude, rows[index].row.longitude, place.latitude, place.longitude) < duplicateKm
            }) {
                rows[twin].row.isCapital = rows[twin].row.isCapital || place.isCapital
                continue
            }
            let nameRu = russian(place.id)
            var aliases = Set([place.name, place.asciiName])
            for (_, list) in names[place.id] ?? [:] { aliases.formUnion(list.map(\.text)) }
            aliases.subtract([name, nameRu ?? ""])
            let region = regions[place.region].map {
                CityTable.Region(name: english($0.id, fallback: $0.name), nameRu: russian($0.id))
            }
            kept[code, default: []].append(rows.count)
            rows.append((CityTable.Row(
                name: name, nameRu: nameRu,
                // Not abbreviations ("Bur", "A"): typing a few letters shouldn't bring up a
                // town by a nickname. Real short names (Ufa) are the name itself.
                aliases: aliases.filter { $0.count <= 60 && CityKey.key($0).count >= 4 }.sorted(),
                region: region, countryCode: code,
                latitude: (place.latitude * 10_000).rounded() / 10_000,
                longitude: (place.longitude * 10_000).rounded() / 10_000,
                population: place.population, isCapital: place.isCapital, fame: place.fame
            ), key, place.region))
        }
        return rows.map(\.row)
    }

    /// Each country's own languages, as GeoNames codes them ("it", "de"): their names are
    /// worth finding a city by ("Roma", "München").
    private static func countryLanguages(_ url: URL) throws -> [String: Set<String>] {
        var languages: [String: Set<String>] = [:]
        try forEachLine(url) { fields in
            guard fields.count > 15, !fields[0].hasPrefix("#") else { return }
            let codes = fields[15].split(separator: ",").prefix(2).map { String($0.split(separator: "-")[0]) }
            languages[fields[0]] = Set(codes)
        }
        return languages
    }

    /// First-level regions by "country.code": their name and geonameid.
    private static func regionNames(_ url: URL) throws -> [String: (name: String, id: Int)] {
        var regions: [String: (name: String, id: Int)] = [:]
        try forEachLine(url) { fields in
            guard fields.count >= 4, let id = Int(fields[3]) else { return }
            regions[fields[0]] = (fields[1], id)
        }
        return regions
    }

    /// The tab-separated fields of every line, read line by line: the alternate names are
    /// too big to load whole. `keepingID` looks at the second field, a geonameid, first,
    /// so most of those 800 MB never become strings.
    private static func forEachLine(_ url: URL, keepingID: ((Int) -> Bool)? = nil, _ body: ([String]) throws -> Void) throws {
        guard let file = fopen(url.path, "r") else { throw PipelineError.malformed("can't open \(url.path)") }
        defer { fclose(file) }
        var line: UnsafeMutablePointer<CChar>?
        var capacity = 0
        defer { free(line) }
        while true {
            let length = getline(&line, &capacity, file)
            guard length > 0, let line else { break }
            let bytes = UnsafeRawBufferPointer(start: line, count: line[length - 1] == 10 ? length - 1 : length)
            if let keepingID {
                var id = 0, tabs = 0
                for byte in bytes {
                    if byte == 9 { tabs += 1; if tabs == 2 { break } } else if tabs == 1 { id = id * 10 + Int(byte) - 48 }
                }
                guard keepingID(id) else { continue }
            }
            try body(bytes.split(separator: 9, omittingEmptySubsequences: false).map { String(decoding: $0, as: UTF8.self) })
        }
    }

    private static func distanceKm(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let radians = Double.pi / 180
        let dLat = (lat2 - lat1) * radians
        let dLon = (lon2 - lon1) * radians
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1 * radians) * cos(lat2 * radians) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * 6371.0088 * asin(min(1, h.squareRoot()))
    }
}
