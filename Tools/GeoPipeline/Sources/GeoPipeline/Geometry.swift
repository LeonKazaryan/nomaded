import Foundation
import simd

/// x = longitude, y = latitude, both in degrees.
typealias GeoPoint = SIMD2<Double>

/// Rings are open (the closing point is not repeated). The first ring is the outer
/// boundary, the rest are holes.
struct GeoPolygon {
    var rings: [[GeoPoint]]
}

struct SourceFeature {
    let code: String
    let adm0: String
    let name: String
    let label: GeoPoint
    /// Natural Earth's CONTINENT, REGION_UN and SUBREGION (UN M49 names).
    let continent: String
    let regionUN: String
    let subregion: String
    let polygons: [GeoPolygon]

    var vertexCount: Int { polygons.reduce(0) { $0 + $1.rings.reduce(0) { $0 + $1.count } } }
}

struct SourceLake {
    let name: String
    /// Natural Earth's importance: 0 for the great lakes of the world, up to 9.
    let scaleRank: Int
    let polygons: [GeoPolygon]
}

struct CountryInput {
    /// ISO 3166-1 alpha-2. Empty for land that belongs to no selectable country.
    let code: String
    let label: GeoPoint
    /// The largest part's: France is in Europe, not where Clipperton Island is.
    let main: SourceFeature
    var polygons: [GeoPolygon]
}

enum Sphere {
    /// Must match `GeoMath.unitVector` in the app.
    static func unitVector(_ p: GeoPoint) -> SIMD3<Double> {
        let phi = p.y * .pi / 180
        let lambda = p.x * .pi / 180
        return SIMD3(cos(phi) * sin(lambda), sin(phi), cos(phi) * cos(lambda))
    }
}

enum Planar {
    /// Shoelace area; the sign depends on winding.
    static func signedArea(_ ring: [GeoPoint]) -> Double {
        var sum = 0.0
        var j = ring.count - 1
        for i in ring.indices {
            sum += (ring[j].x - ring[i].x) * (ring[i].y + ring[j].y)
            j = i
        }
        return sum / 2
    }

    static func triangleArea(_ a: GeoPoint, _ b: GeoPoint, _ c: GeoPoint) -> Double {
        abs((b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y)) / 2
    }

    /// Distance from `p` to the segment `a`–`b`.
    static func distance(_ p: GeoPoint, toSegment a: GeoPoint, _ b: GeoPoint) -> Double {
        let ab = b - a
        let lengthSquared = simd_length_squared(ab)
        guard lengthSquared > 0 else { return simd_distance(p, a) }
        let t = max(0, min(1, simd_dot(p - a, ab) / lengthSquared))
        return simd_distance(p, a + ab * t)
    }
}
