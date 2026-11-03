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
