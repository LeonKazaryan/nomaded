import Foundation
import Observation
import QuartzCore
import RealityKit
import os

/// Owns the 3D globe: the scene, rotation physics, per-country animations and hit testing.
///
/// RealityKit calls `tick` every frame. Gestures and app state only set targets; all
/// motion happens in `tick`, driven by springs, so anything can be interrupted mid-flight.
@Observable @MainActor
final class GlobeController {
    /// Drives the SwiftUI overlays. Changes only while zooming.
    private(set) var camera = GlobeCamera(viewportSize: .zero, distance: 9)
    private(set) var isReady = false
    /// Measured render rate, for the debug HUD.
    private(set) var framesPerSecond = 0

    /// Called with the tapped country's code, or `nil` for the ocean / empty space.
    @ObservationIgnored var onCountryTap: (@MainActor (String?) -> Void)?
    @ObservationIgnored var reduceMotion = false

    private let style: GlobeStyle
    private let root = Entity()
    private let globe = Entity()
    private let cameraEntity = PerspectiveCamera()

    @ObservationIgnored private var nodes: [String: CountryNode] = [:]
    @ObservationIgnored private var animating: Set<String> = []
    @ObservationIgnored private var visited: Set<String> = []
    @ObservationIgnored private var selected: String?
    @ObservationIgnored private var hitTester: GlobeHitTester?
    @ObservationIgnored private var updateSubscription: EventSubscription?
    @ObservationIgnored private var sceneStarted = false

    @ObservationIgnored private var isDragging = false
    @ObservationIgnored private var isFocusing = false
    @ObservationIgnored private var rotationSpring = GlobeTuning.focusSpring
    @ObservationIgnored private var yaw = SpringValue(0)
    @ObservationIgnored private var pitch = SpringValue(0.35)
    @ObservationIgnored private var lastDragTranslation = CGSize.zero
    @ObservationIgnored private var lastInteraction = CACurrentMediaTime()

    @ObservationIgnored private var zoom = SpringValue(1)
    @ObservationIgnored private var zoomSpring = GlobeTuning.zoomSpring
    @ObservationIgnored private var isPinching = false
    @ObservationIgnored private var pinchStartZoom = 1.0

    @ObservationIgnored private var frameSample = (frames: 0, elapsed: 0.0)

    private static let log = Logger(subsystem: "com.leonkazaryan.nomaded", category: "Globe")

    init(style: GlobeStyle) {
        self.style = style
    }

    // MARK: - Scene

    /// Builds the scene once and returns its root. Call from `RealityView`'s make closure.
    func makeScene() async -> Entity {
        guard !sceneStarted else { return root }
        sceneStarted = true

        cameraEntity.camera.fieldOfViewInDegrees = GlobeCamera.verticalFieldOfView
        cameraEntity.camera.near = 0.05
        cameraEntity.camera.far = 100
        root.addChild(cameraEntity)
        root.addChild(globe)
        applyCamera()

        do {
            let started = CACurrentMediaTime()
            let world = try await WorldGeometry.loadBundled()
            try buildGlobe(world)
            let elapsed = Int((CACurrentMediaTime() - started) * 1000)
            Self.log.info("Globe ready in \(elapsed) ms")
        } catch {
            Self.log.error("Globe failed to load: \(error)")
        }
        return root
    }

    /// Keeps the per-frame update subscription alive for as long as the controller lives.
    func retain(_ subscription: EventSubscription) {
        updateSubscription?.cancel()
        updateSubscription = subscription
    }

    func setViewportSize(_ size: CGSize) {
        guard size != camera.viewportSize, size.width > 0, size.height > 0 else { return }
        camera.viewportSize = size
        applyCamera()
    }

    private func buildGlobe(_ world: WorldGeometry) throws {
        let ocean = ModelEntity(
            mesh: try GlobeMeshFactory.sphere(radius: 1),
            materials: [GlobeMeshFactory.material(style.ocean)]
        )
        globe.addChild(ocean)

        for shape in world.countries {
            let isSelectable = !shape.code.isEmpty
            let color = isSelectable ? style.idleColor(slot: shape.colorSlot) : style.unclaimedLand
            let entity = ModelEntity(
                mesh: try GlobeMeshFactory.country(shape, radius: GlobeTuning.landRadius),
                materials: [GlobeMeshFactory.material(color)]
            )
            globe.addChild(entity)
            guard isSelectable else { continue }
            var node = CountryNode(
                shape: shape,
                entity: entity,
                idleColor: color,
                visitedColor: style.visitedColor(slot: shape.colorSlot)
            )
            retarget(&node, code: shape.code)
            node.snap()
            nodes[shape.code] = node
            animating.insert(shape.code)
        }

        hitTester = GlobeHitTester(world: world)
        isReady = true
        playIntro()
    }

    // MARK: - Countries

    func setVisited(_ codes: Set<String>) {
        let changed = visited.symmetricDifference(codes)
        visited = codes
        changed.forEach(retarget)
    }

    /// The "Mark as visited" pop: the country jumps out of the globe and settles back.
    func celebrate(_ code: String) {
        guard !reduceMotion, nodes[code] != nil else { return }
        nodes[code]?.lift.velocity += GlobeTuning.celebrationKick
        animating.insert(code)
    }

    /// Highlights a country and turns the globe to it. `nil` clears the selection.
    func select(_ code: String?) {
        let previous = selected
        selected = code
        [previous, code].compactMap { $0 }.forEach(retarget)
        if let code, let label = nodes[code]?.shape.label {
            focus(on: label, spring: GlobeTuning.focusSpring)
        }
        lastInteraction = CACurrentMediaTime()
    }

    private func retarget(_ code: String) {
        guard var node = nodes[code] else { return }
        retarget(&node, code: code)
        nodes[code] = node
        animating.insert(code)
    }

    private func retarget(_ node: inout CountryNode, code: String) {
        let isVisited = visited.contains(code)
        let isSelected = selected == code
        node.lift.target = (isVisited ? GlobeTuning.visitedLift : 0) + (isSelected ? GlobeTuning.selectedLift : 0)
        node.tint.target = isVisited ? 1 : 0
        node.highlight.target = isSelected ? 1 : 0
    }

    // MARK: - Gestures

    func dragChanged(translation: CGSize) {
        if !isDragging {
            isDragging = true
            isFocusing = false
            lastDragTranslation = .zero
            yaw.velocity = 0
            pitch.velocity = 0
        }
        let dx = translation.width - lastDragTranslation.width
        let dy = translation.height - lastDragTranslation.height
        lastDragTranslation = translation

        let pointsPerRadian = camera.pointsPerRadian
        guard pointsPerRadian > 0 else { return }
        yaw.value += dx / pointsPerRadian
        var pitchDelta = dy / pointsPerRadian
        // Rubber band past the tilt limit.
        let limit = GlobeTuning.pitchLimit
        if (pitch.value > limit && pitchDelta > 0) || (pitch.value < -limit && pitchDelta < 0) {
            pitchDelta *= 0.25
        }
        pitch.value += pitchDelta
        lastInteraction = CACurrentMediaTime()
    }

    func dragEnded(velocity: CGSize) {
        isDragging = false
        let pointsPerRadian = camera.pointsPerRadian
        guard pointsPerRadian > 0 else { return }
        let limit = GlobeTuning.maxSpinVelocity
        yaw.velocity = max(-limit, min(limit, velocity.width / pointsPerRadian))
        pitch.velocity = max(-limit, min(limit, velocity.height / pointsPerRadian))
        lastInteraction = CACurrentMediaTime()
    }

    /// A touch that barely moved: it stops the spin and picks whatever is under the finger.
    func tap(at point: CGPoint) {
        isDragging = false
        yaw.velocity = 0
        pitch.velocity = 0
        lastInteraction = CACurrentMediaTime()
        onCountryTap?(country(at: point))
    }

    func pinchChanged(magnification: CGFloat) {
        if !isPinching {
            isPinching = true
            pinchStartZoom = zoom.value
            zoomSpring = GlobeTuning.zoomSpring
        }
        let range = GlobeTuning.zoomRange
        var value = pinchStartZoom * magnification
        // Rubber band past the zoom limits.
        if value > range.upperBound {
            value = range.upperBound * pow(value / range.upperBound, 0.3)
        } else if value < range.lowerBound {
            value = range.lowerBound * pow(value / range.lowerBound, 0.3)
        }
        zoom.value = value
        zoom.target = value
        zoom.velocity = 0
        lastInteraction = CACurrentMediaTime()
    }

    func pinchEnded() {
        isPinching = false
        let range = GlobeTuning.zoomRange
        zoom.target = min(range.upperBound, max(range.lowerBound, zoom.value))
    }

    func country(at point: CGPoint) -> String? {
        let ray = camera.ray(through: point)
        guard let hit = GeoMath.intersectUnitSphere(origin: ray.origin, direction: ray.direction) else { return nil }
        let coordinate = GlobeOrientation(yaw: yaw.value, pitch: pitch.value).coordinate(atWorldPoint: hit)
        return hitTester?.country(at: coordinate, tolerance: GlobeTuning.microStateTapRadius / camera.pointsPerRadian)
    }

    // MARK: - Frame update

    func tick(deltaTime: TimeInterval) {
        #if DEBUG
        sampleFrameRate(deltaTime)
        #endif
        // Clamp so a hitch doesn't fling the globe.
        let dt = min(deltaTime, 1.0 / 15)
        stepRotation(dt)
        stepZoom(dt)
        stepCountries(dt)
        globe.orientation = GlobeOrientation(yaw: yaw.value, pitch: pitch.value).renderQuaternion
    }

    private func stepRotation(_ dt: Double) {
        guard !isDragging else { return }

        if isFocusing {
            yaw.step(dt, rotationSpring)
            pitch.step(dt, rotationSpring)
            if yaw.isSettled && pitch.isSettled { isFocusing = false }
            return
        }

        let idle = CACurrentMediaTime() - lastInteraction
        if !reduceMotion && selected == nil && idle > GlobeTuning.autoRotateDelay {
            // Ease into a slow spin instead of starting abruptly.
            yaw.velocity += (GlobeTuning.autoRotateSpeed - yaw.velocity) * min(1, dt * 0.6)
        } else {
            yaw.velocity *= exp(-GlobeTuning.friction * dt)
        }
        pitch.velocity *= exp(-GlobeTuning.friction * dt)

        // A soft wall pulls the tilt back inside its limit.
        let limit = GlobeTuning.pitchLimit
        let overshoot = pitch.value - max(-limit, min(limit, pitch.value))
        if overshoot != 0 {
            let spring = GlobeTuning.pitchWallSpring
            let stiffness = pow(2 * .pi / spring.response, 2)
            let damping = 4 * .pi * spring.dampingRatio / spring.response
            pitch.velocity += (-stiffness * overshoot - damping * pitch.velocity) * dt
        }

        yaw.value = GeoMath.wrapAngle(yaw.value + yaw.velocity * dt)
        pitch.value += pitch.velocity * dt
    }

    private func focus(on coordinate: GeoCoordinate, spring: SpringParameters) {
        let target = GlobeOrientation(facing: coordinate)
        let limit = GlobeTuning.pitchLimit
        yaw.target = yaw.value + GeoMath.wrapAngle(target.yaw - yaw.value)
        pitch.target = max(-limit, min(limit, target.pitch))
        rotationSpring = reduceMotion ? GlobeTuning.focusSpring : spring
        isFocusing = !isDragging
    }

    private func stepZoom(_ dt: Double) {
        if !isPinching { zoom.step(dt, zoomSpring) }
        applyCamera()
    }

    private func applyCamera() {
        guard camera.viewportSize.width > 0 else { return }
        let radius = Double(camera.viewportSize.width) * GlobeTuning.baseDiameterRatio / 2 * zoom.value
        let distance = GlobeCamera.distance(silhouetteRadius: radius, focalLength: camera.focalLength)
        cameraEntity.position = [0, 0, Float(distance)]
        if abs(distance - camera.distance) > 1e-6 { camera.distance = distance }
    }

    private func stepCountries(_ dt: Double) {
        for code in animating {
            guard var node = nodes[code] else { continue }
            if reduceMotion {
                node.snap()
            } else {
                node.lift.step(dt, GlobeTuning.liftSpring)
                node.tint.step(dt, GlobeTuning.colorSpring)
                node.highlight.step(dt, GlobeTuning.colorSpring)
            }
            try? apply(&node)
            nodes[code] = node
            if node.isSettled { animating.remove(code) }
        }
    }

    private func apply(_ node: inout CountryNode) throws {
        let lift = Float(max(0, node.lift.value))
        node.entity.scale = SIMD3(repeating: 1 + lift)

        if lift > 0.0005, node.walls == nil {
            let walls = ModelEntity(
                mesh: try GlobeMeshFactory.walls(node.shape, top: GlobeTuning.landRadius, bottom: GlobeTuning.wallBottom),
                materials: []
            )
            node.entity.addChild(walls)
            node.walls = walls
            node.appliedColor = nil
        }
        node.walls?.isEnabled = lift > 0.0005

        let color = node.currentColor
        guard color != node.appliedColor else { return }
        node.entity.model?.materials = [GlobeMeshFactory.material(color)]
        node.walls?.model?.materials = [GlobeMeshFactory.material(color * GlobeTuning.wallShade)]
        node.appliedColor = color
    }

    // MARK: - Intro

    /// The globe flies in spinning and settles on the selected country, or the user's region.
    private func playIntro() {
        let home = selected.flatMap { nodes[$0]?.shape.label }
            ?? Locale.current.region.flatMap { nodes[$0.identifier]?.shape.label }
            ?? GeoCoordinate(latitude: 30, longitude: 15)
        let target = GlobeOrientation(facing: home)

        if reduceMotion {
            yaw = SpringValue(target.yaw)
            pitch = SpringValue(target.pitch)
            return
        }
        yaw = SpringValue(target.yaw - 2.6)
        pitch = SpringValue(0)
        zoom = SpringValue(0.35)
        zoom.target = 1
        zoomSpring = GlobeTuning.introSpring
        focus(on: home, spring: GlobeTuning.introSpring)
    }

    #if DEBUG
    private func sampleFrameRate(_ deltaTime: TimeInterval) {
        frameSample.frames += 1
        frameSample.elapsed += deltaTime
        guard frameSample.elapsed >= 0.5 else { return }
        framesPerSecond = Int((Double(frameSample.frames) / frameSample.elapsed).rounded())
        frameSample = (0, 0)
    }
    #endif
}

private struct CountryNode {
    let shape: CountryShape
    let entity: ModelEntity
    var walls: ModelEntity?
    let idleColor: SIMD3<Float>
    let visitedColor: SIMD3<Float>
    /// Height above the globe, as a fraction of its radius.
    var lift = SpringValue(0)
    /// 0 = idle color, 1 = visited color. Overshoot makes the color flash brighter.
    var tint = SpringValue(0)
    /// Selection glow, 0…1.
    var highlight = SpringValue(0)
    var appliedColor: SIMD3<Float>?

    var isSettled: Bool { lift.isSettled && tint.isSettled && highlight.isSettled }

    var currentColor: SIMD3<Float> {
        let base = idleColor + (visitedColor - idleColor) * Float(tint.value)
        let lit = base + (SIMD3(repeating: 1) - base) * Float(highlight.value) * GlobeTuning.selectedBrightening
        return simd_clamp(lit, SIMD3(repeating: 0), SIMD3(repeating: 1))
    }

    mutating func snap() {
        lift.snap()
        tint.snap()
        highlight.snap()
    }
}
