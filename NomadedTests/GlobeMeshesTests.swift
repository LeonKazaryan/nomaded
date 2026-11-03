import CoreGraphics
import Testing
import simd
@testable import Nomaded

struct GlobeMeshesTests {
    @Test func sphereIsClosedAndInRange() {
        let mesh = GlobeMeshes.sphere(radius: 1, segments: 8, rings: 4)
        #expect(mesh.positions.count == 9 * 5)
        #expect(mesh.indices.count == 8 * 4 * 6)
        #expect(mesh.indices.allSatisfy { Int($0) < mesh.positions.count })
        #expect(mesh.positions.allSatisfy { abs(simd_length($0) - 1) < 1e-5 })
    }

    @Test func packRebasesIndices() {
        let a = MeshData(positions: [.zero, .one, .one], indices: [0, 1, 2])
        let b = MeshData(positions: [.one, .zero, .zero, .one], indices: [0, 2, 3, 3, 1, 0])
        let packed = GlobeMeshes.pack([a, b])

        #expect(packed.mesh.positions.count == 7)
        #expect(packed.mesh.indices == [0, 1, 2, 3, 5, 6, 6, 4, 3])
        #expect(packed.ranges == [MeshRange(indexStart: 0, indexCount: 3), MeshRange(indexStart: 3, indexCount: 6)])
    }

    @Test func wallsRunFromTopToBottom() {
        let square: [SIMD2<Float>] = [[0, 0], [1, 0], [1, 1], [0, 1]]
        let shape = CountryShape(
            code: "XX", colorSlot: 0, label: GeoCoordinate(latitude: 0.5, longitude: 0.5),
            bounds: GeoBounds(minLongitude: 0, minLatitude: 0, maxLongitude: 1, maxLatitude: 1),
            rings: [square], vertices: [], indices: []
        )
        let walls = GlobeMeshes.walls(shape, top: 1.003, bottom: 0.9)

        #expect(walls.positions.count == 8)
        // Two triangles per side, drawn both ways round.
        #expect(walls.indices.count == 4 * 12)
        #expect(abs(simd_length(walls.positions[0]) - 1.003) < 1e-5)
        #expect(abs(simd_length(walls.positions[1]) - 0.9) < 1e-5)
    }

    /// The renderer's matrix and the hit-test ray must agree, or taps would land beside the
    /// countries they're aimed at.
    @Test(arguments: [CGPoint(x: 201, y: 437), CGPoint(x: 120, y: 300), CGPoint(x: 330, y: 610)])
    func projectionMatchesTheTapRay(_ point: CGPoint) throws {
        for distance in [1.2, 3.0, 9.0] {
            let camera = GlobeCamera(viewportSize: CGSize(width: 402, height: 874), distance: distance)
            let ray = camera.ray(through: point)
            guard let hit = GeoMath.intersectUnitSphere(origin: ray.origin, direction: ray.direction) else { continue }

            let clip = camera.viewProjection * SIMD4<Float>(SIMD3<Float>(hit), 1)
            let ndc = SIMD3(clip.x, clip.y, clip.z) / clip.w
            let x = Double(ndc.x + 1) / 2 * 402
            let y = Double(1 - ndc.y) / 2 * 874

            #expect(abs(x - point.x) < 0.01 && abs(y - point.y) < 0.01, "distance \(distance): (\(x), \(y))")
            #expect(ndc.z > 0 && ndc.z < 1, "depth \(ndc.z) is clipped at distance \(distance)")
        }
    }
}
