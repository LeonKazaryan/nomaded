import CoreGraphics
import simd

/// A fixed camera on the +Z axis looking at the globe (radius 1) at the origin.
///
/// All screen ↔ globe math lives here, so SwiftUI overlays, gestures and hit testing
/// agree with what RealityKit draws.
struct GlobeCamera: Equatable, Sendable {
    /// RealityKit's `fieldOfViewInDegrees` is the vertical field of view.
    static let verticalFieldOfView: Float = 30

    var viewportSize: CGSize
    /// Distance from the camera to the globe's center, in globe radii.
    var distance: Double

    var focalLength: Double {
        Double(viewportSize.height) / 2 / tan(Double(Self.verticalFieldOfView) * .pi / 360)
    }

    /// Radius of the globe's outline on screen, in points.
    var silhouetteRadius: Double {
        focalLength / (distance * distance - 1).squareRoot()
    }

    /// How far the point at the center of the globe moves on screen per radian of rotation.
    /// Dividing a drag by this keeps the globe glued to the finger.
    var pointsPerRadian: Double {
        focalLength / (distance - 1)
    }

    static func distance(silhouetteRadius: Double, focalLength: Double) -> Double {
        let ratio = focalLength / silhouetteRadius
        return (ratio * ratio + 1).squareRoot()
    }

    /// World-space ray through a point in the view (points, origin top-left).
    func ray(through point: CGPoint) -> (origin: SIMD3<Double>, direction: SIMD3<Double>) {
        let x = Double(point.x - viewportSize.width / 2)
        let y = Double(viewportSize.height / 2 - point.y)
        return (SIMD3(0, 0, distance), simd_normalize(SIMD3(x, y, -focalLength)))
    }
}

/// The globe's rotation: yaw spins it around the poles, pitch tilts the north toward the
/// viewer. Keeping north up this way stops people from getting lost on an upside-down planet.
struct GlobeOrientation: Equatable, Sendable {
    var yaw: Double
    var pitch: Double

    init(yaw: Double, pitch: Double) {
        self.yaw = yaw
        self.pitch = pitch
    }

    /// The orientation that puts `coordinate` in the center of the screen.
    init(facing coordinate: GeoCoordinate) {
        yaw = -GeoMath.radians(coordinate.longitude)
        pitch = GeoMath.radians(coordinate.latitude)
    }

    var quaternion: simd_quatd {
        simd_quatd(angle: pitch, axis: [1, 0, 0]) * simd_quatd(angle: yaw, axis: [0, 1, 0])
    }

    var renderQuaternion: simd_quatf {
        simd_quatf(angle: Float(pitch), axis: [1, 0, 0]) * simd_quatf(angle: Float(yaw), axis: [0, 1, 0])
    }

    /// Geographic coordinate of a world-space point on the globe's surface.
    func coordinate(atWorldPoint point: SIMD3<Double>) -> GeoCoordinate {
        GeoMath.coordinate(of: quaternion.inverse.act(point))
    }
}
