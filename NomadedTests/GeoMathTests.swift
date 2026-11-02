import CoreGraphics
import Testing
@testable import Nomaded

struct GeoMathTests {
    @Test(arguments: [
        GeoCoordinate(latitude: 41.9, longitude: 12.5),
        GeoCoordinate(latitude: -33.9, longitude: 151.2),
        GeoCoordinate(latitude: 64.1, longitude: -21.9),
        GeoCoordinate(latitude: 0, longitude: 179.9),
    ])
    func unitVectorRoundTrips(_ coordinate: GeoCoordinate) {
        let back = GeoMath.coordinate(of: GeoMath.unitVector(coordinate))
        #expect(abs(back.latitude - coordinate.latitude) < 1e-9)
        #expect(abs(back.longitude - coordinate.longitude) < 1e-9)
    }

    @Test func screenCenterHitsTheFocusedCoordinate() throws {
        let camera = GlobeCamera(viewportSize: CGSize(width: 402, height: 874), distance: 6)
        let paris = GeoCoordinate(latitude: 48.85, longitude: 2.35)
        let ray = camera.ray(through: CGPoint(x: 201, y: 437))

        let hit = try #require(GeoMath.intersectUnitSphere(origin: ray.origin, direction: ray.direction))
        let coordinate = GlobeOrientation(facing: paris).coordinate(atWorldPoint: hit)

        #expect(abs(coordinate.latitude - paris.latitude) < 1e-6)
        #expect(abs(coordinate.longitude - paris.longitude) < 1e-6)
    }

    @Test func silhouetteMatchesRayHits() {
        let camera = GlobeCamera(viewportSize: CGSize(width: 402, height: 874), distance: 6)
        let center = CGPoint(x: 201, y: 437)
        let radius = camera.silhouetteRadius
        let inside = camera.ray(through: CGPoint(x: center.x + radius - 1, y: center.y))
        let outside = camera.ray(through: CGPoint(x: center.x + radius + 1, y: center.y))

        #expect(GeoMath.intersectUnitSphere(origin: inside.origin, direction: inside.direction) != nil)
        #expect(GeoMath.intersectUnitSphere(origin: outside.origin, direction: outside.direction) == nil)
    }

    @Test func distanceForSilhouetteRoundTrips() {
        var camera = GlobeCamera(viewportSize: CGSize(width: 402, height: 874), distance: 1)
        camera.distance = GlobeCamera.distance(silhouetteRadius: 177, focalLength: camera.focalLength)
        #expect(abs(camera.silhouetteRadius - 177) < 1e-9)
    }

    @Test func evenOddRingsHandleHoles() {
        let outer: [SIMD2<Float>] = [[0, 0], [10, 0], [10, 10], [0, 10]]
        let hole: [SIMD2<Float>] = [[4, 4], [6, 4], [6, 6], [4, 6]]

        #expect(GeoMath.ringsContain([outer, hole], longitude: 2, latitude: 2))
        #expect(!GeoMath.ringsContain([outer, hole], longitude: 5, latitude: 5))
        #expect(!GeoMath.ringsContain([outer, hole], longitude: 11, latitude: 5))
    }

    @Test func wrapAngleStaysInRange() {
        #expect(abs(GeoMath.wrapAngle(2 * .pi + 0.5) - 0.5) < 1e-12)
        #expect(abs(GeoMath.wrapAngle(-2 * .pi - 0.5) + 0.5) < 1e-12)
        #expect(abs(GeoMath.wrapAngle(0.25)) - 0.25 < 1e-12)
    }

    @Test func springSettlesOnTarget() {
        var spring = SpringValue(0)
        spring.target = 1
        for _ in 0..<240 { spring.step(1.0 / 120, SpringParameters(response: 0.5, dampingRatio: 0.6)) }
        #expect(spring.value == 1)
        #expect(spring.isSettled)
    }
}
