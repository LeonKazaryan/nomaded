import Foundation

/// Joins polygons that share edges into one, the way neighbouring provinces make a country.
/// Natural Earth draws shared borders with the very same vertices in every layer, so this
/// needs no clipping: every edge that appears once each way is inside the result and
/// cancels out. A polygon added backwards (clockwise) cuts itself out instead: that is how
/// Crimea leaves Ukraine and joins Russia in the "rus" worldview.
enum PolygonDissolver {
    /// - Parameter polygons: outer rings counter-clockwise, holes clockwise (or the reverse,
    ///   to subtract).
    /// - Parameter minimumArea: rings smaller than this (square degrees) are dropped: slivers
    ///   where a shared line didn't quite match up.
    /// - Returns: The rings left once shared edges cancel out, sorted back into outer rings
    ///   and their holes.
    static func joined(_ polygons: [GeoPolygon], minimumArea: Double) -> [GeoPolygon] {
        struct Edge: Hashable {
            let a: GeoPoint, b: GeoPoint
            func hash(into hasher: inout Hasher) {
                hasher.combine(a.x.bitPattern); hasher.combine(a.y.bitPattern)
                hasher.combine(b.x.bitPattern); hasher.combine(b.y.bitPattern)
            }
        }
        var edges: [Edge: Int] = [:]
        for ring in polygons.flatMap(\.rings) {
            for k in ring.indices {
                let edge = Edge(a: ring[k], b: ring[(k + 1) % ring.count])
                guard edge.a != edge.b else { continue }
                let reverse = Edge(a: edge.b, b: edge.a)
                if let count = edges[reverse], count > 0 {
                    edges[reverse] = count - 1
                } else {
                    edges[edge, default: 0] += 1
                }
            }
        }

        // In a fixed order, so the file comes out the same on every run.
        func before(_ a: GeoPoint, _ b: GeoPoint) -> Bool { (a.x, a.y) < (b.x, b.y) }
        var outgoing: [Key: [GeoPoint]] = [:]
        for (edge, count) in edges.sorted(by: { before($0.key.a, $1.key.a) || ($0.key.a == $1.key.a && before($0.key.b, $1.key.b)) }) where count > 0 {
            for _ in 0..<count { outgoing[Key(edge.a), default: []].append(edge.b) }
        }
        let starts = outgoing.keys.sorted { before($0.point, $1.point) }
        var next = starts.startIndex
        var rings: [[GeoPoint]] = []
        while true {
            // Starts already used up stay used up: no need to look at them again.
            while next < starts.endIndex, outgoing[starts[next]]?.isEmpty ?? true { next += 1 }
            guard next < starts.endIndex, let first = outgoing[starts[next]]?.first else { break }
            let startKey = starts[next]
            var ring = [startKey.point]
            outgoing[startKey]!.removeFirst()
            var current = first
            while Key(current) != startKey, var nexts = outgoing[Key(current)], !nexts.isEmpty {
                ring.append(current)
                let step = nexts.removeFirst()
                outgoing[Key(current)] = nexts
                current = step
            }
            if ring.count >= 3, abs(Planar.signedArea(ring)) > minimumArea { rings.append(ring) }
        }

        func isCounterClockwise(_ ring: [GeoPoint]) -> Bool { Planar.signedArea(ring) > 0 }
        var result = rings.filter(isCounterClockwise).map { GeoPolygon(rings: [$0]) }
        let bounds = result.map { PolygonClipper.bounds($0.rings[0]) }
        for hole in rings where !isCounterClockwise(hole) {
            let around = result.indices
                .filter { i in
                    let p = hole[0]
                    return p.x >= bounds[i].min.x && p.x <= bounds[i].max.x && p.y >= bounds[i].min.y && p.y <= bounds[i].max.y
                        && PolygonClipper.contains(result[i].rings[0], p)
                }
                .min { abs(Planar.signedArea(result[$0].rings[0])) < abs(Planar.signedArea(result[$1].rings[0])) }
            if let around { result[around].rings.append(hole) }
        }
        return result
    }

    /// Outer rings counter-clockwise, holes clockwise: the winding `joined` expects.
    static func oriented(_ polygon: GeoPolygon, reversed: Bool = false) -> GeoPolygon {
        GeoPolygon(rings: polygon.rings.enumerated().map { k, ring in
            let wantsCounterClockwise = (k == 0) != reversed
            return (Planar.signedArea(ring) > 0) == wantsCounterClockwise ? ring : Array(ring.reversed())
        })
    }

    private struct Key: Hashable {
        let point: GeoPoint
        init(_ point: GeoPoint) { self.point = point }
        func hash(into hasher: inout Hasher) {
            hasher.combine(point.x.bitPattern)
            hasher.combine(point.y.bitPattern)
        }
    }
}
