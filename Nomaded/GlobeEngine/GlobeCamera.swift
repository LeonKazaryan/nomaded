import CoreGraphics
import simd

/// A fixed camera on the +Z axis looking at the globe (radius 1) at the origin.
///
/// All screen ↔ globe math lives here, so SwiftUI overlays, gestures and hit testing
/// agree with what the renderer draws.
struct GlobeCamera: Equatable, Sendable {
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

    /// How far from the screen center, in points, a surface point `angle` radians away from
    /// the facing point appears.
    func screenRadius(ofAngle angle: Double) -> Double {
        focalLength * sin(angle) / (distance - cos(angle))
    }

    /// The distance at which `angle` radians around the facing point span `screenRadius`
    /// points. Frames a country so it fills a chosen share of the screen.
    func distance(fitting angle: Double, screenRadius: Double) -> Double {
        cos(angle) + focalLength * sin(angle) / screenRadius
    }

    /// World-space ray through a point in the view (points, origin top-left).
    func ray(through point: CGPoint) -> (origin: SIMD3<Double>, direction: SIMD3<Double>) {
        let x = Double(point.x - viewportSize.width / 2)
        let y = Double(viewportSize.height / 2 - point.y)
        return (SIMD3(0, 0, distance), simd_normalize(SIMD3(x, y, -focalLength)))
    }

    /// Clip planes hugging the visible half of the globe. Lifted land stays well under 0.2
    /// radii above it, and tight planes keep land and ocean apart in the depth buffer even
    /// when the camera is far away.
    var clipPlanes: (near: Double, far: Double) {
        (max(0.02, distance - 1.2), distance + 0.5)
    }

    /// World → clip space for the renderer: the same pinhole as `ray(through:)`, so what's
    /// drawn lines up with hit testing and the SwiftUI shading. Metal depth runs 0…1.
    var viewProjection: simd_float4x4 {
        let (near, far) = clipPlanes
        let f = 1 / tan(Double(Self.verticalFieldOfView) * .pi / 360)
        let aspect = Double(viewportSize.width / viewportSize.height)
        let a = far / (near - far)
        let b = near * far / (near - far)
        // A perspective projection times a view matrix that moves the world by -distance in z.
        return simd_float4x4(columns: (
            SIMD4(Float(f / aspect), 0, 0, 0),
            SIMD4(0, Float(f), 0, 0),
            SIMD4(0, 0, Float(a), -1),
            SIMD4(0, 0, Float(b - distance * a), Float(distance))
        ))
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

    /// The coordinate in the middle of the screen.
    var centerCoordinate: GeoCoordinate {
        coordinate(atWorldPoint: [0, 0, 1])
    }

    /// The orientation nearest to this one that moves `coordinate` to `worldPoint`.
    /// Keeps the spot between the fingers in place while pinching. `nil` when no
    /// yaw and pitch can get it there, e.g. a pole can't reach the globe's side.
    func placing(_ coordinate: GeoCoordinate, at worldPoint: SIMD3<Double>) -> GlobeOrientation? {
        // Pitch first: yaw never changes latitude, so after undoing the pitch the
        // target must sit at the coordinate's latitude. That leaves two candidates.
        let target = simd_normalize(worldPoint)
        let radius = (target.y * target.y + target.z * target.z).squareRoot()
        let sinLatitude = sin(GeoMath.radians(coordinate.latitude))
        guard radius > 1e-9, abs(sinLatitude) <= radius else { return nil }

        let phase = atan2(target.z, target.y)
        let spread = acos(sinLatitude / radius)
        let up: Double = pitch + GeoMath.wrapAngle(phase + spread - pitch)
        let down: Double = pitch + GeoMath.wrapAngle(phase - spread - pitch)
        let newPitch = abs(up - pitch) < abs(down - pitch) ? up : down

        // Then yaw: whatever longitude the target has once the pitch is undone.
        let untilted = SIMD2(target.x, -target.y * sin(newPitch) + target.z * cos(newPitch))
        let longitude = atan2(untilted.x, untilted.y)
        let newYaw = yaw + GeoMath.wrapAngle(longitude - GeoMath.radians(coordinate.longitude) - yaw)
        return GlobeOrientation(yaw: newYaw, pitch: newPitch)
    }
}
