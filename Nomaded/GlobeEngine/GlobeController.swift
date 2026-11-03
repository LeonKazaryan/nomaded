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

    /// How the globe appears once loaded.
    enum IntroStyle {
        /// Every launch: a short swing in to the user's region.
        case standard
        /// The very first: out of deep space, tiny and spinning.
        case arrival
    }

    /// A city's dot on the globe.
    struct CityMarker: Equatable, Sendable {
        let id: UUID
        let name: String
        let countryCode: String
        let coordinate: GeoCoordinate
        /// Drawn as a star.
        var isCapital = false
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
    /// A new city just touched down, at this point on screen: the moment for a haptic, and
    /// for confetti if it marked its country (`true`).
    @ObservationIgnored var onCityLanded: (@MainActor (UUID, CGPoint?, Bool) -> Void)?
    @ObservationIgnored var reduceMotion = false
    /// Set before the globe loads.
    @ObservationIgnored var introStyle = IntroStyle.standard

    @ObservationIgnored private var cities: [CityMarker] = []
    @ObservationIgnored private var cityMotion: [UUID: CityMotion] = [:]
    /// New cities wait, hidden, until the flight to them is over, then land.
    @ObservationIgnored private var pendingLandings: Set<UUID> = []
    @ObservationIgnored private var highlightedCity: UUID?
    /// Cities that mark their country once they land: the fill then starts from the city.
    @ObservationIgnored private var landingsThatMark: [UUID: String] = [:]
    /// Countries a landing city will mark. Already visited in the store, but they stay
    /// plain on the globe until the city touches down, so the fill has something to do.
    @ObservationIgnored private var awaitingMark: Set<String> = []
    /// Where the user last touched a country, so marking it fills from under their finger.
    @ObservationIgnored private var lastTouch: (code: String, coordinate: GeoCoordinate)?
    @ObservationIgnored private var ring: Ring?
    /// Points the globe sits above the view's middle, springing as panels come and go.
    @ObservationIgnored private var centerOffset = SpringValue(0)
    /// The zoom the globe comes to rest at when framed for a panel (1 = whole globe).
    @ObservationIgnored private var restingZoom = 1.0
    /// How far each name has popped up, including names on their way out.
    @ObservationIgnored private var labelAppearance: [UUID: SpringValue] = [:]

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

    /// "Mark as visited": the color spreads across the country from `origin` (by default
    /// where it was last touched, else its middle) with a bright front, the country jumps
    /// out of the globe and settles back, and a ring runs off across the planet. Returns
    /// where it starts on screen, for confetti; `nil` if that's out of sight.
    /// `quietly`: a smaller jump and no ring, for marking many countries one after another.
    @discardableResult
    func celebrate(_ code: String, from origin: GeoCoordinate? = nil, quietly: Bool = false) -> CGPoint? {
        guard var node = nodes[code] else { return nil }
        let start = origin ?? (lastTouch?.code == code ? lastTouch?.coordinate : nil) ?? node.shape.label
        let reach = GeoMath.spreadRadius(from: start, rings: node.shape.rings)
        let axis = SIMD3<Float>(GeoMath.unitVector(start))
        // The wave paints the new color; the crossfade would fight it.
        node.tint = SpringValue(1)
        var progress = SpringValue(0)
        progress.target = 1
        node.wave = FillWave(origin: axis, reach: reach, progress: progress, isDrain: false)
        if !reduceMotion, quietly {
            node.lift.velocity += GlobeTuning.celebrationKick * GlobeTuning.quietKickScale
        } else if !reduceMotion {
            node.lift.velocity += GlobeTuning.celebrationKick
            var travel = SpringValue(0)
            travel.target = 1
            ring = Ring(origin: axis, from: reach, delay: GlobeTuning.ringDelay, travel: travel,
                        color: node.visitedColor + (SIMD3(repeating: 1) - node.visitedColor) * 0.35)
        }
        nodes[code] = node
        animating.insert(code)
        return screenPoint(onGlobe: start, lift: 1 + GlobeTuning.visitedLift)
    }

    /// Slides the globe up by `offset` points and settles it at `zoom`, leaving room for a
    /// panel underneath. `frame(offset: 0, zoom: 1)` puts it back.
    func frame(offset: Double, zoom: Double) {
        centerOffset.target = offset
        restingZoom = zoom
        flight = nil
        // May go below the pinch range: a panel can leave little room.
        self.zoom.target = min(GlobeTuning.zoomRange.upperBound, max(0.3, zoom))
        zoomSpring = GlobeTuning.framingSpring
        if reduceMotion {
            centerOffset.snap()
            self.zoom.snap()
            applyCamera()
        }
    }

    /// Turns the country to the middle without selecting it.
    func lookAt(_ code: String) {
        guard let label = nodes[code]?.shape.label else { return }
        focus(on: label, spring: GlobeTuning.focusSpring)
        lastInteraction = CACurrentMediaTime()
    }

    /// Unmarking, the calm way back: the color drains to the country's middle.
    func drain(_ code: String) {
        guard var node = nodes[code] else { return }
        node.tint = SpringValue(0)
        var progress = SpringValue(1)
        progress.target = 0
        let reach = GeoMath.spreadRadius(from: node.shape.label, rings: node.shape.rings)
        node.wave = FillWave(origin: SIMD3<Float>(GeoMath.unitVector(node.shape.label)), reach: reach, progress: progress, isDrain: true)
        nodes[code] = node
        animating.insert(code)
    }

    /// The country's visited color, for things drawn around it (confetti, its stamp).
    func visitedColor(of code: String) -> SIMD3<Float>? {
        nodes[code]?.visitedColor
    }

    /// Where a point on the globe shows on screen, or `nil` past the horizon.
    private func screenPoint(onGlobe coordinate: GeoCoordinate, lift: Double) -> CGPoint? {
        let orientation = GlobeOrientation(yaw: yaw.value, pitch: pitch.value)
        let world = orientation.quaternion.act(GeoMath.unitVector(coordinate) * Double(GlobeTuning.landRadius) * lift)
        guard camera.faces(worldPoint: world) else { return nil }
        return camera.screenPoint(ofWorld: world)
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
    /// out a ring. `marksCountry`: the city is the country's first mark, so the country is
    /// celebrated too, filling from the city, right as it lands. Works before `setCities`
    /// has it, too.
    func landCity(_ id: UUID, marking countryCode: String? = nil) {
        pendingLandings.insert(id)
        if let countryCode {
            landingsThatMark[id] = countryCode
            awaitingMark.insert(countryCode)
            retarget(countryCode)
        }
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
                let marks = landingsThatMark.removeValue(forKey: city.id) != nil
                if marks {
                    awaitingMark.remove(city.countryCode)
                    celebrate(city.countryCode, from: city.coordinate)
                    retarget(city.countryCode)
                }
                onCityLanded?(city.id, screenPoint(of: city), marks)
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
                params: SIMD4(Float(motion.scale.value), ripple, city.id == highlightedCity ? 1 : 0, city.isCapital ? 1 : 0)
            ))
        }
        renderer.markers = markers
        updateCityLabels(dt)
    }

    /// Names for the cities in view, most important first: the highlighted one, then the
    /// selected country's, then names already showing (so two close names don't flicker
    /// back and forth), then the newest. Shown from `cityLabelZoom` on. Each pops up out of
    /// its dot on a spring and sinks back into it when it goes.
    private func updateCityLabels(_ dt: Double) {
        let showsAll = zoom.value >= GlobeTuning.cityLabelZoom
        var candidates: [(label: CityLabel, rank: Int)] = []
        var points: [UUID: CGPoint] = [:]
        for (order, city) in cities.enumerated().reversed() {
            guard !pendingLandings.contains(city.id), let point = screenPoint(of: city) else { continue }
            points[city.id] = point
            let isHighlighted = city.id == highlightedCity
            guard showsAll || isHighlighted else { continue }
            let isShowing = (labelAppearance[city.id]?.target ?? 0) > 0
            let rank = isHighlighted ? 0 : city.countryCode == selected ? 1 : isShowing ? 2 : 3
            let label = CityLabel(id: city.id, name: city.name, point: point, isHighlighted: isHighlighted, isCapital: city.isCapital)
            candidates.append((label, rank * 100_000 - order))
        }
        let ordered = candidates.sorted { $0.rank < $1.rank }.map(\.label)
        let placed = CityLabelLayout.place(ordered, in: CGRect(origin: .zero, size: camera.viewportSize))
        let placedIDs = Set(placed.map(\.id))

        for label in placed where labelAppearance[label.id] == nil {
            labelAppearance[label.id] = SpringValue(0)
        }
        let candidatesByID = Dictionary(uniqueKeysWithValues: ordered.map { ($0.id, $0) })
        let citiesByID = Dictionary(uniqueKeysWithValues: cities.map { ($0.id, $0) })
        var labels: [CityLabel] = []
        for (id, var appearance) in labelAppearance {
            appearance.target = placedIDs.contains(id) ? 1 : 0
            if reduceMotion { appearance.snap() } else { appearance.step(dt, GlobeTuning.cityLabelSpring) }
            // Gone once it has sunk back in, or once its dot went over the horizon.
            guard appearance.target > 0 || appearance.value > 0.01,
                  let point = points[id], let city = citiesByID[id]
            else {
                labelAppearance[id] = nil
                continue
            }
            labelAppearance[id] = appearance
            var label = candidatesByID[id]
                ?? CityLabel(id: id, name: city.name, point: point, isHighlighted: false, isCapital: city.isCapital)
            label.appearance = appearance.value
            labels.append(label)
        }
        // Stable order, so names don't swap places in the view every frame.
        labels.sort { $0.id.uuidString < $1.id.uuidString }
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
        let isVisited = visited.contains(code) && !awaitingMark.contains(code)
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
        let limit = pitchLimit(atZoom: zoom.value)
        if (pitch.value > limit && pitchDelta > 0) || (pitch.value < -limit && pitchDelta < 0) {
            pitchDelta *= 0.25
        }
        pitch.value += pitchDelta
        lastInteraction = CACurrentMediaTime()
    }

    /// Every finger is off the globe, whether its gestures ended or the system cancelled them
    /// (the app went to the background, a system gesture took the touch). A cancelled gesture
    /// never reports its end, and a drag or pinch left "on" would freeze flights and taps.
    func touchesEnded() {
        if isDragging {
            isDragging = false
            lastInteraction = CACurrentMediaTime()
        }
        if isPinching { pinchEnded() }
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
            let code = country(at: point)
            lastTouch = code.flatMap { code in coordinate(at: point).map { (code, $0) } }
            onCountryTap?(code)
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
        let limit = max(pitchLimit(atZoom: zoom.value), abs(pitch.value))
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
        stepRing(dt)
    }

    // MARK: - Celebration ring

    private struct Ring {
        let origin: SIMD3<Float>
        /// Where it sets off: the edge of the country's fill, in radians.
        let from: Double
        /// Seconds left before it sets off.
        var delay: Double
        /// 0 → 1 along `ringReach`, slowing as it goes; it fades the further it gets.
        var travel: SpringValue
        let color: SIMD3<Float>
    }

    private func stepRing(_ dt: Double) {
        guard let renderer else { return }
        guard var ring else {
            renderer.ring.w = -1
            return
        }
        ring.delay -= dt
        guard ring.delay <= 0 else {
            self.ring = ring
            renderer.ring.w = -1
            return
        }
        ring.travel.step(dt, GlobeTuning.ringSpring)
        let progress = ring.travel.value
        let strength = Float(pow(max(0, 1 - progress), 1.4))
        if ring.travel.isSettled || strength < 0.01 {
            self.ring = nil
            renderer.ring.w = -1
            return
        }
        self.ring = ring
        renderer.ring = SIMD4(ring.origin, Float(ring.from + GlobeTuning.ringReach * progress))
        renderer.ringColor = SIMD4(ring.color, strength)
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
        let limit = pitchLimit(atZoom: zoom.value)
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

    /// The tilt limit at a zoom: tight on the whole globe, open enough up close to center
    /// places near the poles.
    private func pitchLimit(atZoom zoom: Double) -> Double {
        let range = GlobeTuning.pitchLimitOpening
        let t = min(1, max(0, (zoom - range.lowerBound) / (range.upperBound - range.lowerBound)))
        let eased = t * t * (3 - 2 * t)
        return GlobeTuning.pitchLimit + (GlobeTuning.pitchLimitClose - GlobeTuning.pitchLimit) * eased
    }

    /// `zoom` is where the turn will end up: a flight to a far-north city lands zoomed in,
    /// where it may tilt further than the globe allows now.
    private func focus(on coordinate: GeoCoordinate, spring: SpringParameters, atZoom zoom: Double? = nil) {
        let target = GlobeOrientation(facing: coordinate)
        let limit = pitchLimit(atZoom: zoom ?? self.zoom.value)
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
        focus(on: coordinate, spring: GlobeTuning.flightSpring, atZoom: arrivalZoom)

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
        if !centerOffset.isSettled {
            centerOffset.step(dt, GlobeTuning.framingSpring)
            camera.centerOffset = centerOffset.value
        }
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
            if var wave = node.wave {
                let spring = reduceMotion ? GlobeTuning.quickWaveSpring
                    : wave.isDrain ? GlobeTuning.drainWaveSpring : GlobeTuning.fillWaveSpring
                wave.progress.step(dt, spring)
                node.wave = wave.progress.isSettled ? nil : wave
            }
            apply(node)
            nodes[code] = node
            if node.isSettled { animating.remove(code) }
        }
    }

    private func apply(_ node: CountryNode) {
        guard let renderer else { return }
        var piece = renderer.pieces[node.index]
        piece.scale = 1 + Float(max(0, node.lift.value) * liftScale)
        if let wave = node.wave {
            // Inside the wave the visited color, outside the idle one, whichever way it runs.
            piece.color = node.color(tint: 1)
            piece.previous = node.color(tint: 0)
            let progress = wave.progress.value
            piece.wave = SIMD4(wave.origin, Float(max(0, wave.reach * progress)))
            // The bright front dims out as the wave finishes, so ending it doesn't pop.
            let front = wave.isDrain
                ? GlobeTuning.drainWaveFront * Float(min(1, progress / 0.15))
                : GlobeTuning.fillWaveFront * Float(min(1, (1 - progress) / 0.15))
            piece.waveStyle = SIMD4(Float(max(0.002, wave.reach * 0.035)), Float(max(0.003, wave.reach * 0.06)), reduceMotion ? 0 : front, 0)
        } else {
            piece.color = node.currentColor
            piece.wave.w = -1
        }
        renderer.pieces[node.index] = piece
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
            zoom = SpringValue(restingZoom)
            return
        }
        let isArrival = introStyle == .arrival
        let spring = isArrival ? GlobeTuning.arrivalSpring : GlobeTuning.introSpring
        yaw = SpringValue(target.yaw - (isArrival ? GlobeTuning.arrivalSpin : 2.6))
        pitch = SpringValue(0)
        zoom = SpringValue(isArrival ? GlobeTuning.arrivalStartZoom : 0.35)
        zoom.target = restingZoom
        zoomSpring = spring
        focus(on: home, spring: spring)
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
    /// The color spreading across the country (marking) or draining back (unmarking).
    var wave: FillWave?

    var isSettled: Bool { lift.isSettled && tint.isSettled && highlight.isSettled && wave == nil }

    var currentColor: SIMD3<Float> { color(tint: tint.value) }

    /// 0 = idle, 1 = visited, with the selection glow on top.
    func color(tint: Double) -> SIMD3<Float> {
        let base = idleColor + (visitedColor - idleColor) * Float(tint)
        let lit = base + (SIMD3(repeating: 1) - base) * Float(highlight.value) * GlobeTuning.selectedBrightening
        return simd_clamp(lit, SIMD3(repeating: 0), SIMD3(repeating: 1))
    }

    mutating func snap() {
        lift.snap()
        tint.snap()
        highlight.snap()
    }
}

/// The visited color spreading across a country, or draining back out of it.
private struct FillWave {
    /// Where it starts, on the unit globe.
    let origin: SIMD3<Float>
    /// The radius (radians) at which it covers its part of the country.
    let reach: Double
    /// 0 → 1 filling, 1 → 0 draining.
    var progress: SpringValue
    let isDrain: Bool
}
