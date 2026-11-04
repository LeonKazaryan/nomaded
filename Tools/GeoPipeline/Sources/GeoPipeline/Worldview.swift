import Foundation

/// How the disputed borders are drawn for the App Store regions whose law says otherwise
/// than the default, Natural Earth's "USA" worldview (ADR-008). Each one becomes a small
/// overlay next to world.nmgeo with just the countries it changes; the app picks it by the
/// App Store storefront the app was downloaded from.
///
/// Natural Earth's own worldview files date from May 2022 and miss the regions Russia
/// annexed that autumn, so the changes are spelled out here instead, as admin-1 regions
/// (ISO 3166-2) handed from one country to another.
struct Worldview {
    struct Move {
        /// ISO 3166-2 codes of Natural Earth's admin-1 regions.
        let regions: [String]
        let from: String
        let to: String
    }

    /// The overlay's file suffix and the app's id for it.
    let id: String
    let moves: [Move]
    /// Whole countries drawn as part of another.
    let merges: [(code: String, into: String)]

    static let all = [
        // Russian law: Crimea, Sevastopol and the four regions annexed in 2022 are Russia.
        Worldview(id: "rus", moves: [
            Move(regions: ["UA-43", "UA-40", "UA-14", "UA-09", "UA-23", "UA-65"], from: "UA", to: "RU"),
        ], merges: []),
        // Chinese law: Taiwan and Arunachal Pradesh ("South Tibet") are China.
        Worldview(id: "chn", moves: [
            Move(regions: ["IN-AR"], from: "IN", to: "CN"),
        ], merges: [("TW", "CN")]),
    ]

    /// Every admin-1 region any worldview moves.
    static var regionCodes: Set<String> { Set(all.flatMap { $0.moves.flatMap(\.regions) }) }

    /// The countries as this worldview draws them. Regions come off one country and onto
    /// the other by cancelling shared edges (`PolygonDissolver`), so borders stay exact.
    func apply(to countries: [CountryInput], regions: [String: [GeoPolygon]]) throws -> [CountryInput] {
        var countries = countries
        func index(_ code: String) throws -> Int {
            guard let i = countries.firstIndex(where: { $0.code == code }) else { throw PipelineError.malformed("worldview \(id): no country \(code)") }
            return i
        }
        for move in moves {
            let parts = try move.regions.flatMap { code -> [GeoPolygon] in
                guard let polygons = regions[code] else { throw PipelineError.malformed("worldview \(id): no admin-1 region \(code)") }
                return polygons
            }
            let from = try index(move.from), to = try index(move.to)
            countries[from].polygons = PolygonDissolver.joined(
                countries[from].polygons.map { PolygonDissolver.oriented($0) } + parts.map { PolygonDissolver.oriented($0, reversed: true) },
                minimumArea: 1e-9
            )
            countries[to].polygons = PolygonDissolver.joined(
                countries[to].polygons.map { PolygonDissolver.oriented($0) } + parts.map { PolygonDissolver.oriented($0) },
                minimumArea: 1e-9
            )
        }
        for merge in merges {
            let from = try index(merge.code)
            let parts = countries[from].polygons
            countries[try index(merge.into)].polygons += parts
            countries.remove(at: from)
        }
        return countries
    }

    /// The disputed land of every worldview, and who it belongs to in this one (`nil`: the
    /// default). The app gives points there to that country whatever the simplified outlines
    /// say, so a city on Crimea's coast is never left to the sea or the wrong side.
    static func disputes(in worldview: Worldview?, countries: [CountryInput], regions: [String: [GeoPolygon]]) -> [(code: String, polygons: [GeoPolygon])] {
        var result: [(code: String, polygons: [GeoPolygon])] = []
        for view in all {
            for move in view.moves {
                let moved = worldview?.moves.contains { $0.regions == move.regions } ?? false
                result.append((moved ? move.to : move.from, move.regions.flatMap { regions[$0] ?? [] }))
            }
            for merge in view.merges {
                let merged = worldview?.merges.contains { $0.code == merge.code } ?? false
                let polygons = countries.first { $0.code == merge.code }?.polygons ?? []
                result.append((merged ? merge.into : merge.code, polygons))
            }
        }
        return result
    }
}
