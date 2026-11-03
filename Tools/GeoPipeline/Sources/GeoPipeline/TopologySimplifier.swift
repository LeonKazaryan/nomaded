import simd

/// Douglas–Peucker simplification that keeps shared borders identical on both sides,
/// so neighbouring countries don't open gaps or overlap after simplification.
///
/// A border between two countries is the same run of points in both rings (in opposite
/// directions). Pinning the points where "who shares this point" changes splits every
/// ring into arcs; simplifying each arc between pinned points gives the same result on
/// both sides.
enum TopologySimplifier {
    private struct PointKey: Hashable {
        let x: UInt64
        let y: UInt64
        init(_ p: GeoPoint) {
            x = p.x.bitPattern
            y = p.y.bitPattern
        }
    }

    static func simplify(_ countries: [CountryInput], tolerance: Double) -> [CountryInput] {
        guard tolerance > 0 else { return countries }

        var usage: [PointKey: Int] = [:]
        for country in countries {
            for polygon in country.polygons {
                for ring in polygon.rings {
                    for key in Set(ring.map(PointKey.init)) { usage[key, default: 0] += 1 }
                }
            }
        }

        return countries.map { country in
            var result = country
            result.polygons = country.polygons.compactMap { polygon in
                let rings = polygon.rings.map { simplifyRing($0, usage: usage, tolerance: tolerance) }
                return rings.first.map { _ in GeoPolygon(rings: rings) }
            }
            return result
        }
    }

    private static func simplifyRing(_ ring: [GeoPoint], usage: [PointKey: Int], tolerance: Double) -> [GeoPoint] {
        let n = ring.count
        guard n > 4 else { return ring }

        let counts = ring.map { usage[PointKey($0)] ?? 1 }
        var pinned = [Bool](repeating: false, count: n)
        for i in 0..<n {
            let previous = counts[(i + n - 1) % n]
            let next = counts[(i + 1) % n]
            pinned[i] = counts[i] >= 3 || counts[i] != previous || counts[i] != next
        }

        var start: Int
        if let first = pinned.firstIndex(of: true) {
            start = first
        } else {
            // Islands and fully shared loops (enclaves): pick a canonical start both sides agree on,
            // plus the point farthest from it, so the loop is split into two arcs.
            start = ring.indices.min { ring[$0].x != ring[$1].x ? ring[$0].x < ring[$1].x : ring[$0].y < ring[$1].y }!
            let far = ring.indices.max { simd_distance(ring[$0], ring[start]) < simd_distance(ring[$1], ring[start]) }!
            pinned[start] = true
            pinned[far] = true
        }

        let rotated = Array(ring[start...] + ring[..<start])
        let rotatedPinned = Array(pinned[start...] + pinned[..<start])

        var result: [GeoPoint] = []
        var arcStart = 0
        for i in 1...n where i == n || rotatedPinned[i] {
            let arc = (arcStart...i).map { rotated[$0 % n] }
            result.append(contentsOf: douglasPeucker(arc, tolerance: tolerance).dropLast())
            arcStart = i
        }

        // Islands smaller than the tolerance would vanish; keep them as they are.
        return result.count >= 3 ? result : ring
    }

    /// A closed ring on its own (no neighbours to agree with): split at its first point and
    /// the point farthest from it, each half simplified.
    static func simplifyClosed(_ ring: [GeoPoint], tolerance: Double) -> [GeoPoint] {
        guard ring.count > 4 else { return ring }
        let far = ring.indices.max { simd_distance(ring[$0], ring[0]) < simd_distance(ring[$1], ring[0]) }!
        let first = douglasPeucker(Array(ring[0...far]), tolerance: tolerance)
        let second = douglasPeucker(Array(ring[far...]) + [ring[0]], tolerance: tolerance)
        let result = first.dropLast() + second.dropLast()
        return result.count >= 3 ? Array(result) : ring
    }

    static func douglasPeucker(_ points: [GeoPoint], tolerance: Double) -> [GeoPoint] {
        guard points.count > 2 else { return points }
        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true

        var stack = [(0, points.count - 1)]
        while let (a, b) = stack.popLast() {
            guard b - a > 1 else { continue }
            var maxDistance = 0.0
            var farthest = -1
            for i in (a + 1)..<b {
                let d = Planar.distance(points[i], toSegment: points[a], points[b])
                if d > maxDistance {
                    maxDistance = d
                    farthest = i
                }
            }
            if maxDistance > tolerance, farthest >= 0 {
                keep[farthest] = true
                stack.append((a, farthest))
                stack.append((farthest, b))
            }
        }
        return points.indices.filter { keep[$0] }.map { points[$0] }
    }
}
