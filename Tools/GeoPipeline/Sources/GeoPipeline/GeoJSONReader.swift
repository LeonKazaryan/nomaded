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
            polygons: polygons.filter { !$0.rings.isEmpty }
        )
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
