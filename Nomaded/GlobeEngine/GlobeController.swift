import Foundation
import Metal
import Observation
import QuartzCore
import os
import simd

/// Owns the 3D globe: the scene, rotation physics, per-country animations and hit testing.
///
/// The view's display link calls `renderFrame` every frame. Gestures and app state only set
/// targets; all motion happens in `tick`, driven by springs, so anything can be interrupted
/// mid-flight. `GlobeRenderer` then draws the result.
@Observable @MainActor
final class GlobeController {
    /// How the camera frames a newly selected country.
    enum Framing {
        /// A tap: turn the globe to the country and keep the zoom.
        case turn
        /// A search result: fly there and zoom in until the whole country fits.
        case flight
        /// A city: fly close to this spot.
        case point(GeoCoordinate)
    }

    /// A city's dot on the globe.
    struct CityMarker: Equatable, Sendable {
        let id: UUID
        let name: String
        let countryCode: String
        let coordinate: GeoCoordinate
    }

    /// Drives the SwiftUI overlays. Changes only while zooming.
    private(set) var camera = GlobeCamera(viewportSize: .zero, distance: 9)
    private(set) var isReady = false
    /// Measured render rate, for the debug HUD.
    private(set) var framesPerSecond = 0

    /// The loaded outlines, for screens that draw maps of their own. `nil` until `isReady`.
    @ObservationIgnored private(set) var world: WorldGeometry?
    /// While paused nothing moves or redraws, e.g. under a full-screen panel.
    var isPaused = false

    /// City names to show this frame, already placed so none overlap.
    private(set) var cityLabels: [CityLabel] = []

    /// Every country that can be selected. Empty until `isReady`.
    var countryCodes: [String] { Array(nodes.keys) }

    /// Called with the tapped country's code, or `nil` for the ocean / empty space.
    @ObservationIgnored var onCountryTap: (@MainActor (String?) -> Void)?
    /// Called with a tapped city dot's id. Takes priority over the country under it.
    @ObservationIgnored var onCityTap: (@MainActor (UUID) -> Void)?
    /// A new city just touched down: the moment for a haptic.
    @ObservationIgnored var onCityLanded: (@MainActor () -> Void)?
    @ObservationIgnored var reduceMotion = false

    @ObservationIgnored private var cities: [CityMarker] = []
    @ObservationIgnored private var cityMotion: [UUID: CityMotion] = [:]
    /// New cities wait, hidden, until the flight to them is over, then land.
    @ObservationIgnored private var pendingLandings: Set<UUID> = []
    @ObservationIgnored private var highlightedCity: UUID?

    private let style: GlobeStyle
    /// `nil` only without Metal, which every iPhone on iOS 18 has.
    private let renderer: GlobeRenderer?

    @ObservationIgnored private var nodes: [String: CountryNode] = [:]
    @ObservationIgnored private var animating: Set<String> = []
    @ObservationIgnored private var visited: Set<String> = []
    @ObservationIgnored private var selected: String?
    @ObservationIgnored private var hitTester: GlobeHitTester?
    @ObservationIgnored private var loadStarted = false

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
    /// The spot that stays under the fingers while pinching. `nil` if the pinch started off the globe.
    @ObservationIgnored private var pinchAnchor: (point: CGPoint, coordinate: GeoCoordinate)?
    /// The current touch turned into a pinch, so lifting the last finger is neither a tap nor a flick.
    @ObservationIgnored private var touchIncludedPinch = false
    @ObservationIgnored private var flight: Flight?
    @ObservationIgnored private var liftScale = 1.0

    @ObservationIgnored private var frameSample = (frames: 0, elapsed: 0.0)

    private static let log = Logger(subsystem: "com.leonkazaryan.nomaded", category: "Globe")

    init(style: GlobeStyle) {
        self.style = style
        do {
            renderer = try GlobeRenderer()
        } catch {
            renderer = nil
            Self.log.error("Globe renderer unavailable: \(error)")
        }
        renderer?.oceanColor = style.ocean
    }

    /// The GPU the view's Metal layer must draw with.
    var device: MTLDevice? { renderer?.device }

    // MARK: - Scene

    /// Loads the countries and builds the scene once. Call from the view's `.task`.
    func load() async {
        guard !loadStarted, let renderer else { return }
        loadStarted = true
        do {
            let started = CACurrentMediaTime()
            let world = try await WorldGeometry.loadBundled()
            let scene = await Self.buildScene(world)
            try renderer.setScene(ocean: scene.ocean, land: scene.land)
            setUpCountries(world, ranges: scene.ranges)
            hitTester = GlobeHitTester(world: world)
            self.world = world
            isReady = true
            playIntro()
            let elapsed = Int((CACurrentMediaTime() - started) * 1000)
            Self.log.info("Globe ready in \(elapsed) ms")

            // Walls follow a moment later, while the intro is still flying in.
            let walls = await Self.buildWalls(world)
            try renderer.setWalls(walls.mesh, ranges: walls.ranges)
        } catch {
            Self.log.error("Globe failed to load: \(error)")
        }
    }

    /// One frame: advance the physics, then draw. The view's display link calls this.
    func renderFrame(deltaTime: TimeInterval, in layer: CAMetalLayer) {
        tick(deltaTime: deltaTime)
        renderer?.draw(in: layer, rotation: GlobeOrientation(yaw: yaw.value, pitch: pitch.value).renderQuaternion, camera: camera)
    }

    func setViewportSize(_ size: CGSize) {
        guard size != camera.viewportSize, size.width > 0, size.height > 0 else { return }
        camera.viewportSize = size
        applyCamera()
    }

    /// Off the main thread: packing ~165k vertices takes a moment.
    nonisolated private static func buildScene(_ world: WorldGeometry) async -> (ocean: MeshData, land: MeshData, ranges: [MeshRange]) {
        let land = GlobeMeshes.pack(world.countries.map { GlobeMeshes.country($0, radius: GlobeTuning.landRadius) })
        return (GlobeMeshes.sphere(radius: 1), land.mesh, land.ranges)
    }

    /// Off the main thread too, and after the globe is already on screen.
    nonisolated private static func buildWalls(_ world: WorldGeometry) async -> (mesh: MeshData, ranges: [MeshRange]) {
        GlobeMeshes.pack(world.countries.map { GlobeMeshes.walls($0, top: GlobeTuning.landRadius, bottom: GlobeTuning.wallBottom) })
    }

    /// Land without a selectable country (`code` is empty) keeps one neutral color.
    private func setUpCountries(_ world: WorldGeometry, ranges: [MeshRange]) {
        guard let renderer else { return }
        renderer.pieces = zip(world.countries, ranges).map { shape, range in
            GlobeRenderer.Piece(
                surface: range,
                color: shape.code.isEmpty ? style.unclaimedLand : style.idleColor(slot: shape.colorSlot)
            )
        }
        for (index, shape) in world.countries.enumerated() where !shape.code.isEmpty {
            var node = CountryNode(
                shape: shape,
                index: index,
                idleColor: style.idleColor(slot: shape.colorSlot),
                visitedColor: style.visitedColor(slot: shape.colorSlot)
            )
            retarget(&node, code: shape.code)
            node.snap()
            nodes[shape.code] = node
            animating.insert(shape.code)
        }
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

    /// Highlights a country and brings it to the center. `nil` clears the selection.
    func select(_ code: String?, framing: Framing = .turn) {
        let previous = selected
        selected = code
        flight = nil
        [previous, code].compactMap { $0 }.forEach(retarget)
        if let code, let shape = nodes[code]?.shape {
            switch framing {
            case .turn: focus(on: shape.label, spring: GlobeTuning.focusSpring)
            case .flight: fly(to: shape)
            case .point(let coordinate): fly(to: coordinate, arrivalZoom: GlobeTuning.cityZoom)
            }
        }
        lastInteraction = CACurrentMediaTime()
    }

    // MARK: - Cities

    private struct CityMotion {
        /// Size multiplier: a landing city springs down from big.
        var scale = SpringValue(1)
        var landedAt: CFTimeInterval?
    }

    func setCities(_ markers: [CityMarker]) {
        cities = markers
        let ids = Set(markers.map(\.id))
        cityMotion = cityMotion.filter { ids.contains($0.key) }
        for id in ids where cityMotion[id] == nil {
            cityMotion[id] = CityMotion()
        }
        if let highlightedCity, !ids.contains(highlightedCity) { self.highlightedCity = nil }
    }

    /// Lands a just-added city once the camera arrives: it drops onto the globe and sends
    /// out a ring. Works before `setCities` has it, too.
    func landCity(_ id: UUID) {
        pendingLandings.insert(id)
    }

    /// The city whose name always shows and whose dot glows a little brighter.
    func highlightCity(_ id: UUID?) {
        highlightedCity = id
    }

    private func stepCities(_ dt: Double) {
        guard let renderer else { return }
        let now = CACurrentMediaTime()
        let isSettled = !isFocusing && flight == nil && abs(zoom.value - zoom.target) < 0.05 * zoom.target
        var markers: [GlobeRenderer.Marker] = []
        markers.reserveCapacity(cities.count)
        let full = GlobeTuning.cityDotFullZoom
        let growth = min(1, max(0, (zoom.value - 1) / (full - 1)))
        let radius = GlobeTuning.cityDotRadius.lowerBound + (GlobeTuning.cityDotRadius.upperBound - GlobeTuning.cityDotRadius.lowerBound) * growth

        for city in cities {
            guard var motion = cityMotion[city.id], let node = nodes[city.countryCode] else { continue }
            if pendingLandings.contains(city.id) {
                guard isSettled else { continue }
                pendingLandings.remove(city.id)
                if !reduceMotion {
                    motion.scale = SpringValue(GlobeTuning.cityDropScale)
                    motion.scale.target = 1
                    motion.landedAt = now
                }
                onCityLanded?()
            }
            motion.scale.step(dt, GlobeTuning.cityDropSpring)
            var ripple: Float = -1
            if let landedAt = motion.landedAt {
                let progress = (now - landedAt) / GlobeTuning.cityRippleDuration
                if progress < 1 { ripple = Float(progress) } else { motion.landedAt = nil }
            }
            cityMotion[city.id] = motion

            // Rides on top of its country, lifted or not.
            let lift = renderer.pieces[node.index].scale * GlobeTuning.landRadius * 1.0005
            let position = SIMD3<Float>(GeoMath.unitVector(city.coordinate)) * lift
            markers.append(GlobeRenderer.Marker(
                position: SIMD4(position, Float(radius)),
                color: SIMD4(node.visitedColor, 1),
                params: SIMD4(Float(motion.scale.value), ripple, city.id == highlightedCity ? 1 : 0, 0)
            ))
        }
        renderer.markers = markers
        updateCityLabels()
    }

    /// Names for the cities in view, most important first: the highlighted one, then the
    /// selected country's, then the newest. Shown from `cityLabelZoom` on.
    private func updateCityLabels() {
        let showsAll = zoom.value >= GlobeTuning.cityLabelZoom
        var candidates: [(label: CityLabel, rank: Int)] = []
        if showsAll || highlightedCity != nil {
            for (order, city) in cities.enumerated().reversed() {
                let isHighlighted = city.id == highlightedCity
                guard showsAll || isHighlighted,
                      !pendingLandings.contains(city.id),
                      let point = screenPoint(of: city)
                else { continue }
                let rank = isHighlighted ? 0 : city.countryCode == selected ? 1 : 2
                candidates.append((CityLabel(id: city.id, name: city.name, point: point, isHighlighted: isHighlighted), rank * 100_000 - order))
            }
        }
        let ordered = candidates.sorted { $0.rank < $1.rank }.map(\.label)
        let labels = CityLabelLayout.place(ordered, in: CGRect(origin: .zero, size: camera.viewportSize))
        if labels != cityLabels { cityLabels = labels }
    }

    /// The city's dot on screen, or `nil` past the horizon.
    private func screenPoint(of city: CityMarker) -> CGPoint? {
        guard let node = nodes[city.countryCode], let renderer else { return nil }
        let lift = Double(renderer.pieces[node.index].scale * GlobeTuning.landRadius)
        let orientation = GlobeOrientation(yaw: yaw.value, pitch: pitch.value)
        let world = orientation.quaternion.act(GeoMath.unitVector(city.coordinate) * lift)
        guard camera.faces(worldPoint: world) else { return nil }
        return camera.screenPoint(ofWorld: world)
    }

    private func city(at point: CGPoint) -> UUID? {
        let radius = GlobeTuning.cityTapRadius
        return cities
            .compactMap { city in screenPoint(of: city).map { (city.id, hypot($0.x - point.x, $0.y - point.y)) } }
            .filter { $0.1 < radius }
            .min { $0.1 < $1.1 }?
            .0
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
            flight = nil
            touchIncludedPinch = isPinching
            lastDragTranslation = .zero
            yaw.velocity = 0
            pitch.velocity = 0
        }
        let dx = translation.width - lastDragTranslation.width
        let dy = translation.height - lastDragTranslation.height
        lastDragTranslation = translation
        // While two fingers are down the pinch owns the rotation.
        guard !isPinching else { return }

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
        lastInteraction = CACurrentMediaTime()
        // The finger left over from a pinch shouldn't fling the globe.
        guard !touchIncludedPinch else { return }
        let pointsPerRadian = camera.pointsPerRadian
        guard pointsPerRadian > 0 else { return }
        let limit = GlobeTuning.maxSpinVelocity
        yaw.velocity = max(-limit, min(limit, velocity.width / pointsPerRadian))
        pitch.velocity = max(-limit, min(limit, velocity.height / pointsPerRadian))
    }

    /// A touch that barely moved: it stops the spin and picks whatever is under the finger.
    func tap(at point: CGPoint) {
        isDragging = false
        yaw.velocity = 0
        pitch.velocity = 0
        lastInteraction = CACurrentMediaTime()
        guard !touchIncludedPinch else { return }
        if let city = city(at: point), let onCityTap {
            onCityTap(city)
        } else {
            onCountryTap?(country(at: point))
        }
    }

    /// Zooms toward `anchor`, the point between the fingers when the pinch began: the
    /// place under it stays under it, like on a map.
    func pinchChanged(magnification: CGFloat, anchor: CGPoint) {
        if !isPinching {
            isPinching = true
            touchIncludedPinch = true
            isFocusing = false
            flight = nil
            yaw.velocity = 0
            pitch.velocity = 0
            pinchStartZoom = zoom.value
            zoomSpring = GlobeTuning.zoomSpring
            pinchAnchor = coordinate(at: anchor).map { (anchor, $0) }
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
        applyCamera()
        if let pinchAnchor { keep(pinchAnchor.coordinate, under: pinchAnchor.point) }
        lastInteraction = CACurrentMediaTime()
    }

    func pinchEnded() {
        isPinching = false
        pinchAnchor = nil
        let range = GlobeTuning.zoomRange
        zoom.target = min(range.upperBound, max(range.lowerBound, zoom.value))
    }

    func country(at point: CGPoint) -> String? {
        guard let coordinate = coordinate(at: point) else { return nil }
        return hitTester?.country(at: coordinate, tolerance: GlobeTuning.microStateTapRadius / camera.pointsPerRadian)
    }

    /// Where the ray through a screen point meets the land surface, as a unit vector.
    /// Land floats slightly above the ocean, which matters up close.
    private func surfacePoint(at point: CGPoint) -> SIMD3<Double>? {
        let ray = camera.ray(through: point)
        let origin = ray.origin / Double(GlobeTuning.landRadius)
        return GeoMath.intersectUnitSphere(origin: origin, direction: ray.direction)
    }

    private func coordinate(at point: CGPoint) -> GeoCoordinate? {
        surfacePoint(at: point).map { GlobeOrientation(yaw: yaw.value, pitch: pitch.value).coordinate(atWorldPoint: $0) }
    }

    /// Turns the globe so `coordinate` is back under `point` after the camera moved.
    private func keep(_ coordinate: GeoCoordinate, under point: CGPoint) {
        guard let target = surfacePoint(at: point),
              let placed = GlobeOrientation(yaw: yaw.value, pitch: pitch.value).placing(coordinate, at: target)
        else { return }
        // Don't let a pinch tilt past the limit, but don't yank back a tilt that already is.
        let limit = max(GlobeTuning.pitchLimit, abs(pitch.value))
        yaw.value = placed.yaw
        pitch.value = max(-limit, min(limit, placed.pitch))
    }

    // MARK: - Frame update

    func tick(deltaTime: TimeInterval) {
        #if DEBUG
        sampleFrameRate(deltaTime)
        #endif
        // Clamp so a hitch doesn't fling the globe.
        let dt = min(deltaTime, 1.0 / 15)
        stepRotation(dt)
        stepFlight()
        stepZoom(dt)
        stepCountries(dt)
        stepCities(dt)
    }

    private func stepRotation(_ dt: Double) {
        guard !isDragging else { return }

        if isFocusing {
            let start = (yaw: yaw.value, pitch: pitch.value)
            yaw.step(dt, rotationSpring)
            pitch.step(dt, rotationSpring)
            limitFocusSpeed(from: start, dt)
            if yaw.isSettled && pitch.isSettled { isFocusing = false }
            return
        }

        let idle = CACurrentMediaTime() - lastInteraction
        let isOverview = zoom.value <= GlobeTuning.autoRotateMaxZoom
        if !reduceMotion && selected == nil && isOverview && idle > GlobeTuning.autoRotateDelay {
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

    /// The surface never slides past faster than `maxFocusScreenSpeed`, so when zoomed in
    /// the turn waits for the zoom to pull back instead of smearing the map.
    private func limitFocusSpeed(from start: (yaw: Double, pitch: Double), _ dt: Double) {
        let step = SIMD2(yaw.value - start.yaw, pitch.value - start.pitch)
        let moved = simd_length(step) * camera.pointsPerRadian
        let allowed = GlobeTuning.maxFocusScreenSpeed * dt
        guard moved > allowed else { return }
        let scale = allowed / moved
        yaw.value = start.yaw + step.x * scale
        pitch.value = start.pitch + step.y * scale
        yaw.velocity *= scale
        pitch.velocity *= scale
    }

    // MARK: - Flight

    private struct Flight {
        /// Where the screen center ends up (the country's center, or as close as the tilt limit allows).
        let destination: GeoCoordinate
        /// Trip length in radians.
        let length: Double
        let arrivalZoom: Double
    }

    /// Pulls back if the trip is long, swings over, then zooms in until the country fills
    /// `flightFitFraction` of the screen. Reduce Motion jumps straight there.
    private func fly(to shape: CountryShape) {
        let extent = GeoMath.capRadius(around: shape.label, rings: shape.rings, limit: GlobeTuning.framingExtentLimit)
        fly(to: shape.label, arrivalZoom: max(1, zoom(fitting: extent, widthFraction: GlobeTuning.flightFitFraction)))
    }

    private func fly(to coordinate: GeoCoordinate, arrivalZoom: Double) {
        let start = GlobeOrientation(yaw: yaw.value, pitch: pitch.value).centerCoordinate
        focus(on: coordinate, spring: GlobeTuning.flightSpring)

        if reduceMotion {
            yaw.snap()
            pitch.snap()
            isFocusing = false
            zoom.target = arrivalZoom
            zoom.snap()
            applyCamera()
            return
        }

        let destination = GlobeOrientation(yaw: yaw.target, pitch: pitch.target).centerCoordinate
        let length = GeoMath.angularDistance(start, destination)
        let cruiseZoom = GlobeTuning.flightCruiseScale / max(length, 1e-3)
        zoom.target = max(GlobeTuning.zoomRange.lowerBound, min(zoom.value, cruiseZoom))
        zoomSpring = GlobeTuning.flightZoomSpring
        flight = Flight(destination: destination, length: length, arrivalZoom: arrivalZoom)
    }

    private func stepFlight() {
        guard let flight else { return }
        let center = GlobeOrientation(yaw: yaw.value, pitch: pitch.value).centerCoordinate
        let left = GeoMath.angularDistance(center, flight.destination)
        guard !isFocusing || left <= flight.length * GlobeTuning.flightHandoff else { return }
        zoom.target = flight.arrivalZoom
        self.flight = nil
    }

    /// The zoom at which an angular radius around the screen center spans `widthFraction`
    /// of the screen width, clamped to the zoom range.
    private func zoom(fitting angle: Double, widthFraction: Double) -> Double {
        let width = Double(camera.viewportSize.width)
        let range = GlobeTuning.zoomRange
        guard width > 0, angle > 0 else { return range.upperBound }
        let distance = camera.distance(fitting: angle, screenRadius: width * widthFraction / 2)
        guard distance > 1 else { return range.upperBound }
        let silhouette = camera.focalLength / (distance * distance - 1).squareRoot()
        let zoom = silhouette / (width * GlobeTuning.baseDiameterRatio / 2)
        return min(range.upperBound, max(range.lowerBound, zoom))
    }

    private func stepZoom(_ dt: Double) {
        if !isPinching { zoom.step(dt, zoomSpring) }
        applyCamera()
        updateLiftScale()
    }

    /// Lifts shrink as the zoom grows (`liftZoomDamping`), so lifted countries need a
    /// refresh whenever the zoom changes.
    private func updateLiftScale() {
        let scale = pow(max(1, zoom.value), -GlobeTuning.liftZoomDamping)
        guard abs(scale - liftScale) > 1e-3 else { return }
        liftScale = scale
        animating.formUnion(visited)
        if let selected { animating.insert(selected) }
    }

    private func applyCamera() {
        guard camera.viewportSize.width > 0 else { return }
        let radius = Double(camera.viewportSize.width) * GlobeTuning.baseDiameterRatio / 2 * zoom.value
        let distance = GlobeCamera.distance(silhouetteRadius: radius, focalLength: camera.focalLength)
        if abs(distance - camera.distance) > 1e-6 { camera.distance = distance }
    }

    private func stepCountries(_ dt: Double) {
        for code in animating {
            guard var node = nodes[code] else {
                animating.remove(code)
                continue
            }
            if reduceMotion {
                node.snap()
            } else {
                node.lift.step(dt, GlobeTuning.liftSpring)
                node.tint.step(dt, GlobeTuning.colorSpring)
                node.highlight.step(dt, GlobeTuning.colorSpring)
            }
            apply(node)
            nodes[code] = node
            if node.isSettled { animating.remove(code) }
        }
    }

    private func apply(_ node: CountryNode) {
        renderer?.pieces[node.index].scale = 1 + Float(max(0, node.lift.value) * liftScale)
        renderer?.pieces[node.index].color = node.currentColor
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
    /// Slot in `GlobeRenderer.pieces`.
    let index: Int
    let idleColor: SIMD3<Float>
    let visitedColor: SIMD3<Float>
    /// Height above the globe, as a fraction of its radius.
    var lift = SpringValue(0)
    /// 0 = idle color, 1 = visited color. Overshoot makes the color flash brighter.
    var tint = SpringValue(0)
    /// Selection glow, 0…1.
    var highlight = SpringValue(0)

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
