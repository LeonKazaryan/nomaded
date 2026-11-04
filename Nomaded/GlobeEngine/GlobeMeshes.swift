import simd

/// Vertices and triangles ready for a GPU buffer. Triangles are counter-clockwise seen from
/// outside the globe.
struct MeshData: Sendable {
    var positions: [SIMD3<Float>] = []
    var indices: [UInt32] = []
}

/// Where one piece sits inside a packed mesh.
struct MeshRange: Equatable, Sendable {
    var indexStart: Int
    var indexCount: Int
}

/// One point along a river, as the river shader reads it. Mirrors `RiverPoint` in
/// GlobeShaders.metal.
struct RiverPoint: Sendable {
    /// xyz: on the unit globe. w: width in points at the normal size.
    var position: SIMD4<Float>
    /// x: Natural Earth's rank. y: 1 at a line's first point, 2 at its last.
    var params: SIMD4<Float>
}

/// Every river as ribbons: two vertices per point, made in the vertex shader, which reads
/// the point as `vertex_id / 2` and the bank as `vertex_id % 2`.
struct RiverMesh: Sendable {
    var points: [RiverPoint] = []
    var indices: [UInt32] = []
    /// Each country's rivers, by its index in the world; `nil` where it has none.
    var ranges: [MeshRange?] = []
}

/// Builds the globe's meshes as plain arrays. Pure and nonisolated, so it runs off the main
/// thread and is covered by tests.
enum GlobeMeshes {
    /// UV sphere, fine enough that its outline stays round when zoomed in.
    static func sphere(radius: Float, segments: Int = 160, rings: Int = 80) -> MeshData {
        var mesh = MeshData()
        mesh.positions.reserveCapacity((segments + 1) * (rings + 1))
        for ring in 0...rings {
            let latitude = -90 + 180 * Float(ring) / Float(rings)
            for segment in 0...segments {
                let longitude = -180 + 360 * Float(segment) / Float(segments)
                mesh.positions.append(GeoMath.unitVector(longitude: longitude, latitude: latitude) * radius)
            }
        }

        mesh.indices.reserveCapacity(segments * rings * 6)
        let stride = UInt32(segments + 1)
        for ring in 0..<UInt32(rings) {
            for segment in 0..<UInt32(segments) {
                let southWest = ring * stride + segment
                let southEast = southWest + 1
                let northWest = southWest + stride
                let northEast = northWest + 1
                mesh.indices += [southWest, southEast, northWest, southEast, northEast, northWest]
            }
        }
        return mesh
    }

    static func country(_ shape: CountryShape, radius: Float) -> MeshData {
        MeshData(positions: shape.vertices.map { $0 * radius }, indices: shape.indices)
    }

    /// Side walls along the country's outline, visible only while it's lifted. Both windings,
    /// so they show from either side whatever the ring direction.
    static func walls(_ shape: CountryShape, top: Float, bottom: Float) -> MeshData {
        var mesh = MeshData()
        for ring in shape.rings where ring.count > 1 {
            let base = UInt32(mesh.positions.count)
            for point in ring {
                let direction = GeoMath.unitVector(longitude: point.x, latitude: point.y)
                mesh.positions.append(direction * top)
                mesh.positions.append(direction * bottom)
            }
            let count = UInt32(ring.count)
            for i in 0..<count {
                let topA = base + 2 * i, bottomA = topA + 1
                let topB = base + 2 * ((i + 1) % count), bottomB = topB + 1
                mesh.indices += [topA, bottomA, bottomB, topA, bottomB, topB]
                mesh.indices += [topA, bottomB, bottomA, topA, topB, bottomB]
            }
        }
        return mesh
    }

    /// All rivers, grouped by country so each country draws its own with its own lift.
    static func rivers(_ world: WorldGeometry) -> RiverMesh {
        var mesh = RiverMesh()
        mesh.ranges = Array(repeating: nil, count: world.countries.count)
        let byCountry = Dictionary(grouping: world.rivers, by: \.country)
        for (country, rivers) in byCountry.sorted(by: { $0.key < $1.key }) {
            let start = mesh.indices.count
            for river in rivers where river.points.count >= 2 {
                let base = UInt32(mesh.points.count)
                let last = river.points.count - 1
                for (k, point) in river.points.enumerated() {
                    let width = GlobeTuning.riverWidth(weight: Float(river.weights[k]) / 100)
                    let ends: Float = (k == 0 ? 1 : 0) + (k == last ? 2 : 0)
                    mesh.points.append(RiverPoint(
                        position: SIMD4(GeoMath.unitVector(longitude: point.x, latitude: point.y), width),
                        params: SIMD4(Float(river.ranks[k]), ends, 0, 0)
                    ))
                }
                for k in 0..<UInt32(last) {
                    let a = 2 * (base + k), b = a + 2
                    mesh.indices += [a, a + 1, b, a + 1, b + 1, b]
                }
            }
            mesh.ranges[country] = MeshRange(indexStart: start, indexCount: mesh.indices.count - start)
        }
        return mesh
    }

    /// Joins meshes into one, so the renderer keeps a single buffer pair and draws each
    /// piece by its index range. Indices are rebased onto the joined vertices.
    static func pack(_ meshes: [MeshData]) -> (mesh: MeshData, ranges: [MeshRange]) {
        var packed = MeshData()
        packed.positions.reserveCapacity(meshes.reduce(0) { $0 + $1.positions.count })
        packed.indices.reserveCapacity(meshes.reduce(0) { $0 + $1.indices.count })
        var ranges: [MeshRange] = []
        ranges.reserveCapacity(meshes.count)
        for mesh in meshes {
            let base = UInt32(packed.positions.count)
            ranges.append(MeshRange(indexStart: packed.indices.count, indexCount: mesh.indices.count))
            packed.positions += mesh.positions
            packed.indices += mesh.indices.map { $0 + base }
        }
        return (packed, ranges)
    }
}
