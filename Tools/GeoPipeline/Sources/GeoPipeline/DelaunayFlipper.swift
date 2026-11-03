import Foundation

/// Turns a polygon triangulation into the constrained Delaunay one by flipping edges
/// (Lawson's algorithm). Earcut, bridging holes to the outline, leaves long slivers right
/// across a country; every sliver then gets cut into dozens of pieces to follow the
/// curvature. After flipping, the triangles are as round as the outline allows. The
/// outline's own edges never flip, so borders stay exactly where neighbours expect them.
enum DelaunayFlipper {
    /// - Parameters:
    ///   - coords: Flat `[x0, y0, x1, y1, …]` in lon/lat, as given to earcut.
    ///   - triangles: Earcut's output, three indices per triangle.
    ///   - rings: How many points each ring has, in order: their edges are fixed.
    static func flip(_ triangles: [Int], coords: [Double], ringSizes: [Int]) -> [Int] {
        guard triangles.count >= 6 else { return triangles }
        // East–west distances shrink toward the poles; judging shapes on a plane squeezed
        // the same way keeps triangles round on the ground. One factor for the whole
        // polygon keeps the map affine, so no triangle turns over.
        let latitudes = stride(from: 1, to: coords.count, by: 2).map { coords[$0] }
        let squeeze = cos((latitudes.min()! + latitudes.max()!) / 2 * .pi / 180)
        func point(_ i: Int) -> SIMD2<Double> { SIMD2(coords[2 * i] * squeeze, coords[2 * i + 1]) }

        var fixed = Set<UInt64>()
        var start = 0
        for size in ringSizes {
            for k in 0..<size { fixed.insert(key(start + k, start + (k + 1) % size)) }
            start += size
        }

        // Counter-clockwise triangles and, for each edge, the triangles on either side.
        var tris: [(Int, Int, Int)] = stride(from: 0, to: triangles.count, by: 3).map { t in
            let a = triangles[t], b = triangles[t + 1], c = triangles[t + 2]
            return orientation(point(a), point(b), point(c)) >= 0 ? (a, b, c) : (a, c, b)
        }
        var sides: [UInt64: [Int]] = [:]
        for (t, tri) in tris.enumerated() {
            for (p, q) in [(tri.0, tri.1), (tri.1, tri.2), (tri.2, tri.0)] { sides[key(p, q), default: []].append(t) }
        }

        var pending = Array(sides.keys.filter { !fixed.contains($0) && sides[$0]!.count == 2 })
        var flips = 0
        let limit = tris.count * 50
        while let edge = pending.popLast(), flips < limit {
            guard let pair = sides[edge], pair.count == 2 else { continue }
            let (t1, t2) = (pair[0], pair[1])
            let a = Int(edge >> 32), b = Int(edge & 0xFFFF_FFFF)
            guard let c = opposite(tris[t1], a, b), let d = opposite(tris[t2], a, b) else { continue }
            // Order so t1 is (a, b, c) counter-clockwise; then d lies to the right of a→b.
            let (p, q) = orientation(point(a), point(b), point(c)) > 0 ? (a, b) : (b, a)
            guard inCircle(point(p), point(q), point(c), point(d)),
                  orientation(point(p), point(d), point(c)) > 0,
                  orientation(point(d), point(q), point(c)) > 0
            else { continue }

            tris[t1] = (p, d, c)
            tris[t2] = (d, q, c)
            sides[edge] = nil
            sides[key(c, d)] = [t1, t2]
            // c–p stays with t1 and d–q with t2; p–d changes over to t1, q–c to t2.
            replace(&sides, key(p, d), old: t2, new: t1)
            replace(&sides, key(q, c), old: t1, new: t2)
            for side in [key(p, d), key(d, q), key(q, c), key(c, p)] where !fixed.contains(side) {
                pending.append(side)
            }
            flips += 1
        }
        return tris.flatMap { [$0.0, $0.1, $0.2] }
    }

    private static func key(_ a: Int, _ b: Int) -> UInt64 {
        UInt64(min(a, b)) << 32 | UInt64(max(a, b))
    }

    private static func opposite(_ tri: (Int, Int, Int), _ a: Int, _ b: Int) -> Int? {
        [tri.0, tri.1, tri.2].first { $0 != a && $0 != b }
    }

    private static func replace(_ sides: inout [UInt64: [Int]], _ edge: UInt64, old: Int, new: Int) {
        guard var pair = sides[edge], let k = pair.firstIndex(of: old) else { return }
        pair[k] = new
        sides[edge] = pair
    }

    /// Positive when a, b, c turn counter-clockwise.
    private static func orientation(_ a: SIMD2<Double>, _ b: SIMD2<Double>, _ c: SIMD2<Double>) -> Double {
        (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
    }

    /// Whether d lies inside the circle through a, b, c (counter-clockwise).
    private static func inCircle(_ a: SIMD2<Double>, _ b: SIMD2<Double>, _ c: SIMD2<Double>, _ d: SIMD2<Double>) -> Bool {
        let ad = a - d, bd = b - d, cd = c - d
        let det = (ad.x * ad.x + ad.y * ad.y) * (bd.x * cd.y - cd.x * bd.y)
            - (bd.x * bd.x + bd.y * bd.y) * (ad.x * cd.y - cd.x * ad.y)
            + (cd.x * cd.x + cd.y * cd.y) * (ad.x * bd.y - bd.x * ad.y)
        // A hair of slack, so four points on one circle don't flip back and forth.
        return det > 1e-12
    }
}
