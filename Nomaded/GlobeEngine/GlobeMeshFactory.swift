import RealityKit
import UIKit

@MainActor
enum GlobeMeshFactory {
    /// UV sphere, fine enough that its outline stays round when zoomed in.
    static func sphere(radius: Float, segments: Int = 160, rings: Int = 80) throws -> MeshResource {
        var positions: [SIMD3<Float>] = []
        positions.reserveCapacity((segments + 1) * (rings + 1))
        for ring in 0...rings {
            let latitude = -90 + 180 * Float(ring) / Float(rings)
            for segment in 0...segments {
                let longitude = -180 + 360 * Float(segment) / Float(segments)
                positions.append(GeoMath.unitVector(longitude: longitude, latitude: latitude) * radius)
            }
        }

        var indices: [UInt32] = []
        indices.reserveCapacity(segments * rings * 6)
        let stride = UInt32(segments + 1)
        for ring in 0..<UInt32(rings) {
            for segment in 0..<UInt32(segments) {
                let southWest = ring * stride + segment
                let southEast = southWest + 1
                let northWest = southWest + stride
                let northEast = northWest + 1
                indices += [southWest, southEast, northWest, southEast, northEast, northWest]
            }
        }

        var descriptor = MeshDescriptor(name: "ocean")
        descriptor.positions = MeshBuffer(positions)
        descriptor.primitives = .triangles(indices)
        return try MeshResource.generate(from: [descriptor])
    }

    static func country(_ shape: CountryShape, radius: Float) throws -> MeshResource {
        var descriptor = MeshDescriptor(name: shape.code)
        descriptor.positions = MeshBuffer(shape.vertices.map { $0 * radius })
        descriptor.primitives = .triangles(shape.indices)
        return try MeshResource.generate(from: [descriptor])
    }

    /// Side walls along the country's outline, visible only while it's lifted. Double-sided,
    /// so ring winding doesn't matter.
    static func walls(_ shape: CountryShape, top: Float, bottom: Float) throws -> MeshResource {
        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        for ring in shape.rings where ring.count > 1 {
            let base = UInt32(positions.count)
            for point in ring {
                let direction = GeoMath.unitVector(longitude: point.x, latitude: point.y)
                positions.append(direction * top)
                positions.append(direction * bottom)
            }
            let count = UInt32(ring.count)
            for i in 0..<count {
                let topA = base + 2 * i, bottomA = topA + 1
                let topB = base + 2 * ((i + 1) % count), bottomB = topB + 1
                indices += [topA, bottomA, bottomB, topA, bottomB, topB]
                indices += [topA, bottomB, bottomA, topA, topB, bottomB]
            }
        }
        var descriptor = MeshDescriptor(name: "\(shape.code)-walls")
        descriptor.positions = MeshBuffer(positions)
        descriptor.primitives = .triangles(indices)
        return try MeshResource.generate(from: [descriptor])
    }

    /// Flat, unlit color: the globe gets its volume from the SwiftUI shading overlay instead
    /// of 3D lights, so palette colors render exactly as designed.
    static func material(_ color: SIMD3<Float>) -> UnlitMaterial {
        var material = UnlitMaterial(applyPostProcessToneMap: false)
        material.color = .init(tint: UIColor(
            red: CGFloat(color.x), green: CGFloat(color.y), blue: CGFloat(color.z), alpha: 1
        ))
        return material
    }
}
