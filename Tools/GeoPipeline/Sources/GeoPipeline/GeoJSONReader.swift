import Foundation

enum PipelineError: Error, CustomStringConvertible {
    case malformed(String)

    var description: String {
        switch self {
        case .malformed(let what): "Malformed GeoJSON: \(what)"
        }
    }
}

/// Reads Natural Earth admin-0 GeoJSON. Only the fields the app needs are kept.
enum GeoJSONReader {
    static func read(_ url: URL) throws -> [SourceFeature] {
        let data = try Data(contentsOf: url)
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let features = root["features"] as? [[String: Any]]
        else { throw PipelineError.malformed("missing features") }
        return try features.compactMap(parseFeature)
    }

    private static func parseFeature(_ feature: [String: Any]) throws -> SourceFeature? {
        guard
            let properties = feature["properties"] as? [String: Any],
            let geometry = feature["geometry"] as? [String: Any]
        else { return nil }

        let polygons: [GeoPolygon]
        switch geometry["type"] as? String {
        case "Polygon":
            polygons = [try parsePolygon(geometry["coordinates"])]
        case "MultiPolygon":
            guard let parts = geometry["coordinates"] as? [Any] else { throw PipelineError.malformed("multipolygon") }
            polygons = try parts.map(parsePolygon)
        default:
            return nil
        }

        return SourceFeature(
            code: properties["ISO_A2_EH"] as? String ?? "-99",
            adm0: properties["ADM0_A3"] as? String ?? "",
            name: properties["NAME"] as? String ?? "",
            label: GeoPoint(
                (properties["LABEL_X"] as? NSNumber)?.doubleValue ?? 0,
                (properties["LABEL_Y"] as? NSNumber)?.doubleValue ?? 0
            ),
            continent: properties["CONTINENT"] as? String ?? "",
            regionUN: properties["REGION_UN"] as? String ?? "",
            subregion: properties["SUBREGION"] as? String ?? "",
            polygons: polygons.filter { !$0.rings.isEmpty }
        )
    }

    /// Reads the admin-1 regions (`ne_10m_admin_1_states_provinces`) with these ISO 3166-2
    /// codes, for `Worldview`.
    static func readRegions(_ url: URL, codes: Set<String>) throws -> [String: [GeoPolygon]] {
        let data = try Data(contentsOf: url)
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let features = root["features"] as? [[String: Any]]
        else { throw PipelineError.malformed("admin-1 features") }
        var regions: [String: [GeoPolygon]] = [:]
        for feature in features {
            guard let properties = feature["properties"] as? [String: Any],
                  let code = properties["iso_3166_2"] as? String, codes.contains(code),
                  let geometry = feature["geometry"] as? [String: Any]
            else { continue }
            switch geometry["type"] as? String {
            case "Polygon": regions[code, default: []].append(try parsePolygon(geometry["coordinates"]))
            case "MultiPolygon":
                guard let parts = geometry["coordinates"] as? [Any] else { throw PipelineError.malformed("multipolygon") }
                regions[code, default: []] += try parts.map(parsePolygon)
            default: continue
            }
            regions[code]?.removeAll { $0.rings.isEmpty }
        }
        return regions
    }

    /// Reads Natural Earth's lakes (`ne_10m_lakes`): name, rank and outline.
    static func readLakes(_ url: URL) throws -> [SourceLake] {
        let data = try Data(contentsOf: url)
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let features = root["features"] as? [[String: Any]]
        else { throw PipelineError.malformed("missing features") }
        return try features.compactMap { feature in
            guard
                let properties = feature["properties"] as? [String: Any],
                let geometry = feature["geometry"] as? [String: Any]
            else { return nil }
            let polygons: [GeoPolygon]
            switch geometry["type"] as? String {
            case "Polygon":
                polygons = [try parsePolygon(geometry["coordinates"])]
            case "MultiPolygon":
                guard let parts = geometry["coordinates"] as? [Any] else { throw PipelineError.malformed("multipolygon") }
                polygons = try parts.map(parsePolygon)
            default:
                return nil
            }
            return SourceLake(
                name: properties["name"] as? String ?? "",
                scaleRank: (properties["scalerank"] as? NSNumber)?.intValue ?? 99,
                polygons: polygons.filter { !$0.rings.isEmpty }
            )
        }
    }

    /// Reads Natural Earth's rivers (`ne_10m_rivers_lake_centerlines_scale_rank`): each
    /// stretch with its rank, drawing weight and kind.
    static func readRivers(_ url: URL) throws -> [SourceRiver] {
        let data = try Data(contentsOf: url)
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let features = root["features"] as? [[String: Any]]
        else { throw PipelineError.malformed("missing features") }
        return features.flatMap { feature -> [SourceRiver] in
            guard
                let properties = feature["properties"] as? [String: Any],
                let geometry = feature["geometry"] as? [String: Any]
            else { return [] }
            let lines: [Any]
            switch geometry["type"] as? String {
            case "LineString": lines = [geometry["coordinates"] as Any]
            case "MultiLineString": lines = geometry["coordinates"] as? [Any] ?? []
            default: return []
            }
            return lines.compactMap { line in
                guard let coordinates = line as? [[Double]] else { return nil }
                var points: [GeoPoint] = []
                for coordinate in coordinates where coordinate.count >= 2 {
                    let point = GeoPoint(coordinate[0], coordinate[1])
                    if points.last != point { points.append(point) }
                }
                guard points.count >= 2 else { return nil }
                return SourceRiver(
                    kind: properties["featurecla"] as? String ?? "",
                    scaleRank: (properties["scalerank"] as? NSNumber)?.intValue ?? 99,
                    strokeWeight: (properties["strokeweig"] as? NSNumber)?.doubleValue ?? 0.2,
                    points: points
                )
            }
        }
    }

    private static func parsePolygon(_ value: Any?) throws -> GeoPolygon {
        guard let rings = value as? [[[Double]]] else { throw PipelineError.malformed("polygon") }
        let cleaned = rings.map { ring in
            var points: [GeoPoint] = []
            points.reserveCapacity(ring.count)
            for coordinate in ring where coordinate.count >= 2 {
                let point = GeoPoint(coordinate[0], coordinate[1])
                if points.last != point { points.append(point) }
            }
            if points.count > 1, points.first == points.last { points.removeLast() }
            return points
        }
        // A polygon whose outer ring collapsed is dropped entirely; collapsed holes are ignored.
        guard let outer = cleaned.first, outer.count >= 3 else { return GeoPolygon(rings: []) }
        return GeoPolygon(rings: [outer] + cleaned.dropFirst().filter { $0.count >= 3 })
    }
}
