import simd

/// Triangulates a country's polygons and wraps the result onto the unit sphere.
///
/// Earcut works in flat lon/lat space and happily produces triangles thousands of
/// kilometres wide. Flat triangles that big would cut through the globe, so they are cut
/// down in that same flat space (longest edge first, at its lon/lat midpoint) until no
/// edge is longer than `maxEdge`. Pieces of a flat triangulation stay inside the outline
/// once wrapped onto the sphere. Great-circle midpoints don't: far up north a long edge's
/// great circle bulges toward the pole and the triangles fold out over the sea (Russia's
/// Arctic coast became one straight line). Whether an edge gets split depends only on the
/// edge, and it's always split at the same midpoint, so neighbouring triangles stay
/// crack-free.
struct SphereMeshBuilder {
    /// In degrees along the ground (see `length`).
    let maxEdge: Double
    let densifyStep: Double

    private(set) var vertices: [SIMD3<Double>] = []
    private(set) var indices: [UInt32] = []
    /// Lon/lat of each vertex, where midpoints are taken.
    private var coordinates: [GeoPoint] = []
    /// Rings after densification, which are exactly the mesh's boundary edges.
    private(set) var rings: [[GeoPoint]] = []
    /// Polygons whose simplified outline self-intersected and were rebuilt from the original.
    private(set) var fallbackCount = 0

    private var midpoints: [UInt64: UInt32] = [:]

    init(maxEdgeDegrees: Double, densifyStepDegrees: Double) {
        maxEdge = maxEdgeDegrees
        densifyStep = densifyStepDegrees
    }

    /// - Parameter original: The unsimplified polygon, used when simplification produced a
    ///   self-intersecting outline (happens to a few tiny islands and atolls).
    mutating func add(_ polygon: GeoPolygon, original: GeoPolygon) {
        var dense = polygon.rings.map(densify)
        var (coords, holeIndices) = flatten(dense)
        var triangles = Earcut.triangulate(coords, holeIndices: holeIndices)

        if areaError(dense, coords: coords, triangles: triangles) > 0.001 {
            fallbackCount += 1
            dense = original.rings.map(densify)
            (coords, holeIndices) = flatten(dense)
            triangles = Earcut.triangulate(coords, holeIndices: holeIndices)
        }

        rings.append(contentsOf: dense)
        let base = vertices.count
        for ring in dense {
            for point in ring {
                coordinates.append(point)
                vertices.append(Sphere.unitVector(point))
            }
        }

        for t in stride(from: 0, to: triangles.count, by: 3) {
            let a = UInt32(base + triangles[t])
            var b = UInt32(base + triangles[t + 1])
            var c = UInt32(base + triangles[t + 2])
            // Counter-clockwise in lon/lat (east right, north up) is counter-clockwise
            // seen from outside the globe, however big the triangle is.
            let pa = coordinates[Int(a)], pb = coordinates[Int(b)], pc = coordinates[Int(c)]
            let signedArea = (pb.x - pa.x) * (pc.y - pa.y) - (pc.x - pa.x) * (pb.y - pa.y)
            guard signedArea != 0 else { continue }
            if signedArea < 0 { swap(&b, &c) }
            subdivide(a, b, c)
        }
    }

    /// Inserts points so no ring edge is longer than `densifyStep`. Long straight borders
    /// (like the 49th parallel) then follow their latitude line instead of a great circle.
    private func densify(_ ring: [GeoPoint]) -> [GeoPoint] {
        var result: [GeoPoint] = []
        for i in ring.indices {
            let a = ring[i]
            let b = ring[(i + 1) % ring.count]
            result.append(a)
            // Edges running along a pole collapse to a single point on the sphere.
            if abs(a.y) > 89.9 && abs(b.y) > 89.9 { continue }
            let steps = Int((simd_distance(a, b) / densifyStep).rounded(.up))
            if steps > 1 {
                for s in 1..<steps { result.append(a + (b - a) * (Double(s) / Double(steps))) }
            }
        }
        return result
    }

    private mutating func subdivide(_ a: UInt32, _ b: UInt32, _ c: UInt32) {
        var stack = [(a, b, c)]
        while let (a, b, c) = stack.popLast() {
            let ab = length(a, b), bc = length(b, c), ca = length(c, a)
            let longest = max(ab, bc, ca)
            if longest <= maxEdge {
                // Pieces that collapse on the sphere (two corners on a pole) cover nothing.
                let va = vertices[Int(a)], vb = vertices[Int(b)], vc = vertices[Int(c)]
                if simd_length(simd_cross(vb - va, vc - va)) > 1e-12 {
                    indices.append(contentsOf: [a, b, c])
                }
            } else if longest == ab {
                let m = midpoint(a, b)
                stack.append((a, m, c))
                stack.append((m, b, c))
            } else if longest == bc {
                let m = midpoint(b, c)
                stack.append((b, m, a))
                stack.append((m, c, a))
            } else {
                let m = midpoint(c, a)
                stack.append((c, m, b))
                stack.append((m, a, b))
            }
        }
    }

    /// Edge length in degrees along the ground: a degree of longitude shrinks toward the
    /// poles, so high latitudes aren't cut finer than they need to be.
    private func length(_ a: UInt32, _ b: UInt32) -> Double {
        let pa = coordinates[Int(a)], pb = coordinates[Int(b)]
        let east = (pb.x - pa.x) * cos((pa.y + pb.y) / 2 * .pi / 180)
        return (east * east + (pb.y - pa.y) * (pb.y - pa.y)).squareRoot()
    }

    private mutating func midpoint(_ a: UInt32, _ b: UInt32) -> UInt32 {
        let key = UInt64(min(a, b)) << 32 | UInt64(max(a, b))
        if let existing = midpoints[key] { return existing }
        let index = UInt32(vertices.count)
        let middle = (coordinates[Int(a)] + coordinates[Int(b)]) / 2
        coordinates.append(middle)
        vertices.append(Sphere.unitVector(middle))
        midpoints[key] = index
        return index
    }

    private func flatten(_ rings: [[GeoPoint]]) -> (coords: [Double], holeIndices: [Int]) {
        var coords: [Double] = []
        var holeIndices: [Int] = []
        for (k, ring) in rings.enumerated() {
            if k > 0 { holeIndices.append(coords.count / 2) }
            for point in ring {
                coords.append(point.x)
                coords.append(point.y)
            }
        }
        return (coords, holeIndices)
    }

    /// Relative difference between the polygon's area and the triangles' total area.
    /// Earcut output on a self-intersecting outline overlaps itself, which shows up here.
    private func areaError(_ rings: [[GeoPoint]], coords: [Double], triangles: [Int]) -> Double {
        let polygonArea = rings.enumerated().reduce(0.0) { sum, item in
            item.offset == 0 ? sum + abs(Planar.signedArea(item.element)) : sum - abs(Planar.signedArea(item.element))
        }
        guard polygonArea > 1e-12 else { return 0 }
        func point(_ i: Int) -> GeoPoint { GeoPoint(coords[2 * i], coords[2 * i + 1]) }
        var trianglesArea = 0.0
        for t in stride(from: 0, to: triangles.count, by: 3) {
            trianglesArea += Planar.triangleArea(point(triangles[t]), point(triangles[t + 1]), point(triangles[t + 2]))
        }
        return abs(trianglesArea - polygonArea) / polygonArea
    }
}
