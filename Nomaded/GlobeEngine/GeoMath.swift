import Foundation
import simd

/// A point on Earth, in degrees.
struct GeoCoordinate: Equatable, Sendable {
    var latitude: Double
    var longitude: Double
}

/// Spherical math shared by rendering, hit testing and tests.
///
/// Convention (must match Tools/GeoPipeline): +Y is north, latitude/longitude (0, 0)
/// faces +Z, and +X points to 90°E.
enum GeoMath {
    static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }

    static func unitVector(_ coordinate: GeoCoordinate) -> SIMD3<Double> {
        let phi = radians(coordinate.latitude)
        let lambda = radians(coordinate.longitude)
        return SIMD3(cos(phi) * sin(lambda), sin(phi), cos(phi) * cos(lambda))
    }

    static func unitVector(longitude: Float, latitude: Float) -> SIMD3<Float> {
        let phi = latitude * .pi / 180
        let lambda = longitude * .pi / 180
        return SIMD3(cos(phi) * sin(lambda), sin(phi), cos(phi) * cos(lambda))
    }

    static func coordinate(of vector: SIMD3<Double>) -> GeoCoordinate {
        let n = simd_normalize(vector)
        return GeoCoordinate(
            latitude: asin(max(-1, min(1, n.y))) * 180 / .pi,
            longitude: atan2(n.x, n.z) * 180 / .pi
        )
    }

    /// Nearest point where a ray enters the unit sphere at the origin, or `nil` on a miss.
    static func intersectUnitSphere(origin: SIMD3<Double>, direction: SIMD3<Double>) -> SIMD3<Double>? {
        let d = simd_normalize(direction)
        let b = simd_dot(origin, d)
        let discriminant = b * b - (simd_length_squared(origin) - 1)
        guard discriminant >= 0 else { return nil }
        let t = -b - discriminant.squareRoot()
        guard t >= 0 else { return nil }
        return origin + d * t
    }

    /// Even-odd point-in-polygon test over all rings, so holes (Lesotho inside South Africa)
    /// and multi-part countries both work. Coordinates are (longitude, latitude).
    static func ringsContain(_ rings: [[SIMD2<Float>]], longitude x: Float, latitude y: Float) -> Bool {
        var inside = false
        for ring in rings {
            var j = ring.count - 1
            for i in ring.indices {
                let a = ring[i], b = ring[j]
                if (a.y > y) != (b.y > y), x < (b.x - a.x) * (y - a.y) / (b.y - a.y) + a.x {
                    inside.toggle()
                }
                j = i
            }
        }
        return inside
    }

    /// Maps any angle to [-π, π).
    static func wrapAngle(_ angle: Double) -> Double {
        var a = fmod(angle + .pi, 2 * .pi)
        if a < 0 { a += 2 * .pi }
        return a - .pi
    }

    /// Great-circle distance in radians.
    static func angularDistance(_ a: GeoCoordinate, _ b: GeoCoordinate) -> Double {
        acos(max(-1, min(1, simd_dot(unitVector(a), unitVector(b)))))
    }

    /// Angular radius (radians) of the circle around `center` that holds every outline
    /// point closer than `limit`. Far-flung parts are left out, so France is framed
    /// without French Guiana and the US without Hawaii.
    static func capRadius(around center: GeoCoordinate, rings: [[SIMD2<Float>]], limit: Double) -> Double {
        let axis = unitVector(center)
        let limitCosine = cos(limit)
        var smallestCosine = 1.0
        for ring in rings {
            for point in ring {
                let cosine = simd_dot(axis, unitVector(GeoCoordinate(latitude: Double(point.y), longitude: Double(point.x))))
                if cosine >= limitCosine { smallestCosine = min(smallestCosine, cosine) }
            }
        }
        return acos(smallestCosine)
    }
}
