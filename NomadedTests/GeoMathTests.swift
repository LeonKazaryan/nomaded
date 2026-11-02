import CoreGraphics
import Testing
import simd
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

    @Test(arguments: [
        GlobeOrientation(yaw: 0.3, pitch: 0.5),
        GlobeOrientation(yaw: -2.9, pitch: -0.8),
        GlobeOrientation(yaw: 1.4, pitch: 1.1),
    ])
    func placingRecoversTheOrientation(_ orientation: GlobeOrientation) throws {
        let rome = GeoCoordinate(latitude: 41.9, longitude: 12.5)
        let point = orientation.quaternion.act(GeoMath.unitVector(rome))
        // Start a little off, as during a pinch, and land back on the original.
        let nearby = GlobeOrientation(yaw: orientation.yaw + 0.05, pitch: orientation.pitch - 0.04)

        let placed = try #require(nearby.placing(rome, at: point))

        #expect(abs(GeoMath.wrapAngle(placed.yaw - orientation.yaw)) < 1e-9)
        #expect(abs(placed.pitch - orientation.pitch) < 1e-9)
    }

    @Test func placingMovesTheCoordinateUnderTheTarget() throws {
        let tokyo = GeoCoordinate(latitude: 35.7, longitude: 139.7)
        let target = simd_normalize(SIMD3<Double>(0.3, 0.2, 0.93))

        let placed = try #require(GlobeOrientation(yaw: 0, pitch: 0).placing(tokyo, at: target))

        #expect(simd_distance(placed.quaternion.act(GeoMath.unitVector(tokyo)), target) < 1e-9)
    }

    @Test func placingRejectsUnreachablePoints() {
        // Yaw and pitch alone can't move the North Pole onto the globe's right side.
        let pole = GeoCoordinate(latitude: 90, longitude: 0)
        #expect(GlobeOrientation(yaw: 0, pitch: 0).placing(pole, at: [1, 0, 0]) == nil)
    }

    @Test func framingDistanceRoundTrips() {
        var camera = GlobeCamera(viewportSize: CGSize(width: 402, height: 874), distance: 1)
        camera.distance = camera.distance(fitting: 0.15, screenRadius: 120)
        #expect(abs(camera.screenRadius(ofAngle: 0.15) - 120) < 1e-9)
    }

    @Test func capRadiusIgnoresFarParts() {
        let mainland: [SIMD2<Float>] = [[-1, -1], [1, -1], [1, 1], [-1, 1]]
        let farIsland: [SIMD2<Float>] = [[60, 0], [61, 0], [61, 1]]
        let center = GeoCoordinate(latitude: 0, longitude: 0)
        let corner = GeoMath.angularDistance(center, GeoCoordinate(latitude: 1, longitude: 1))

        let radius = GeoMath.capRadius(around: center, rings: [mainland, farIsland], limit: 0.45)

        #expect(abs(radius - corner) < 1e-6)
    }

    @Test func springSettlesOnTarget() {
        var spring = SpringValue(0)
        spring.target = 1
        for _ in 0..<240 { spring.step(1.0 / 120, SpringParameters(response: 0.5, dampingRatio: 0.6)) }
        #expect(spring.value == 1)
        #expect(spring.isSettled)
    }
}
