import Foundation

/// How the disputed borders are drawn for the App Store regions whose law says otherwise
/// than the default, Natural Earth's "USA" worldview (ADR-008). Each one becomes a small
/// overlay next to world.nmgeo with just the countries it changes; the app picks it by the
/// App Store storefront the app was downloaded from.
///
/// Natural Earth's own worldview files date from May 2022 and miss the regions Russia
/// annexed that autumn, so those changes are spelled out here instead, as admin-1 regions
/// (ISO 3166-2) handed from one country to another. Where nothing has changed since, a move
/// can take its land from Natural Earth's own file for the worldview (`--pov-<id>`).
struct Worldview {
    struct Move {
        /// ISO 3166-2 codes of Natural Earth's admin-1 regions. Empty: what `from` gives up
        /// in Natural Earth's own file for this worldview; with `from` empty, the land `to`
        /// gets there that the default file leaves to no one.
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
        // Indian law: all of Jammu and Kashmir and Ladakh is India. Pakistan gives up
        // Gilgit-Baltistan and Azad Kashmir, China Aksai Chin, the Shaksgam Valley and its
        // side of Demchok, and the Siachen Glacier, which the default file leaves out, joins
        // too. Natural Earth's "IND" file draws exactly this, and nothing there has moved
        // since 2022.
        Worldview(id: "ind", moves: [
            Move(regions: [], from: "PK", to: "IN"),
            Move(regions: [], from: "CN", to: "IN"),
            Move(regions: [], from: "", to: "IN"),
        ], merges: []),
    ]

    /// Every admin-1 region any worldview moves.
    static var regionCodes: Set<String> { Set(all.flatMap { $0.moves.flatMap(\.regions) }) }

    /// Whether some move takes its land from Natural Earth's own file for this worldview.
    var needsOwnFile: Bool { moves.contains { $0.regions.isEmpty } }

    /// Where a move's land is in the regions passed around: its admin-1 codes, or one key for
    /// the land from the worldview's own file (`ownLand`).
    func landCodes(_ move: Move) -> [String] {
        move.regions.isEmpty ? ["\(id):\(move.from)"] : move.regions
    }

    /// The land the moves without admin-1 regions hand over, keyed like `landCodes`: what each
    /// country has in the default file and not in `own`, Natural Earth's file for this
    /// worldview, and what `own` gives on top of that, which the default leaves out. Exact,
    /// by cancelling shared edges: both files draw every border with the same vertices.
    func ownLand(base: [CountryInput], own: [CountryInput]) throws -> [String: [GeoPolygon]] {
        func polygons(_ countries: [CountryInput], _ code: String) -> [GeoPolygon] {
            countries.filter { $0.code == code }.flatMap(\.polygons)
        }
        func minus(_ a: [GeoPolygon], _ b: [GeoPolygon]) -> [GeoPolygon] {
            PolygonDissolver.joined(a.map { PolygonDissolver.oriented($0) } + b.map { PolygonDissolver.oriented($0, reversed: true) }, minimumArea: 1e-9)
        }
        var land: [String: [GeoPolygon]] = [:]
        let given = moves.filter { $0.regions.isEmpty && !$0.from.isEmpty }
        for move in given {
            land[landCodes(move)[0]] = minus(polygons(base, move.from), polygons(own, move.from))
        }
        for move in moves where move.regions.isEmpty && move.from.isEmpty {
            let gained = minus(polygons(own, move.to), polygons(base, move.to))
            land[landCodes(move)[0]] = minus(gained, given.filter { $0.to == move.to }.flatMap { land[landCodes($0)[0]]! })
        }
        if let empty = land.first(where: { $0.value.isEmpty }) {
            throw PipelineError.malformed("worldview \(id): no land for \(empty.key) in its own file")
        }
        return land
    }

    /// The countries as this worldview draws them. Regions come off one country and onto
    /// the other by cancelling shared edges (`PolygonDissolver`), so borders stay exact.
    func apply(to countries: [CountryInput], regions: [String: [GeoPolygon]]) throws -> [CountryInput] {
        var countries = countries
        func index(_ code: String) throws -> Int {
            guard let i = countries.firstIndex(where: { $0.code == code }) else { throw PipelineError.malformed("worldview \(id): no country \(code)") }
            return i
        }
        for move in moves {
            let parts = try landCodes(move).flatMap { code -> [GeoPolygon] in
                guard let polygons = regions[code] else { throw PipelineError.malformed("worldview \(id): no region \(code)") }
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
    /// say, so a city on Crimea's coast is never left to the sea or the wrong side. Land that
    /// is no one's here is left out: there the outlines decide.
    static func disputes(in worldview: Worldview?, countries: [CountryInput], regions: [String: [GeoPolygon]]) -> [(code: String, polygons: [GeoPolygon])] {
        var result: [(code: String, polygons: [GeoPolygon])] = []
        for view in all {
            for move in view.moves {
                let codes = view.landCodes(move)
                let moved = worldview.map { other in other.moves.contains { other.landCodes($0) == codes } } ?? false
                let owner = moved ? move.to : move.from
                if !owner.isEmpty { result.append((owner, codes.flatMap { regions[$0] ?? [] })) }
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
