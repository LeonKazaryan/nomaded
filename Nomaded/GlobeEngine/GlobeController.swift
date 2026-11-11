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
        /// A tap: turn the globe to the country and zoom until it fits, out or in.
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
    /// How often the globe is drawing now: at rest it isn't, which saves the battery.
    private(set) var frameDemand = FrameDemand.full

    /// The loaded outlines, for screens that draw maps of their own. `nil` until `isReady`.
    @ObservationIgnored private(set) var world: WorldGeometry?
    /// Whose borders the globe draws (see `Worldview`).
    @ObservationIgnored private(set) var worldview = Worldview.standard
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
    @ObservationIgnored var reduceMotion = false {
        // The idle spin may start or stop.
        didSet { wake() }
    }
    /// Asks the view for frames again after the globe came to rest. Set by the view.
    @ObservationIgnored var onWake: (@MainActor () -> Void)?
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
    /// Countries marked on another device, each with the seconds left before it fills in.
    /// Visited already; `awaitingMark` keeps them plain until their turn. Soonest first.
    @ObservationIgnored private var arrivals: [(code: String, wait: Double)] = []
    /// Where the user last touched a country, so marking it fills from under their finger.
    @ObservationIgnored private var lastTouch: (code: String, coordinate: GeoCoordinate)?
    @ObservationIgnored private var ring: Ring?
    /// Points the globe sits above the view's middle, springing as panels come and go.
    @ObservationIgnored private var centerOffset = SpringValue(0)
    @ObservationIgnored private var centerShift = SpringValue(0)
    /// Where the globe stands: the whole view (`nil`), or a part of it, like one page of an
    /// open iPhone Duo's spread. Flights, fits and the resting size all happen inside it.
    @ObservationIgnored private var stage: CGRect?
    /// The stage's middle right of and above the view's middle, and its size as a share of
    /// the whole view's, springing from one stage to the next.
    @ObservationIgnored private var stageShift = SpringValue(0)
    @ObservationIgnored private var stageLift = SpringValue(0)
    @ObservationIgnored private var stageScale = SpringValue(1)
    /// The zoom the globe comes to rest at when framed for a panel (1 = whole globe).
    @ObservationIgnored private var restingZoom = 1.0
    /// Each name on screen, including names on their way out.
    @ObservationIgnored private var labelMotion: [UUID: CityLabelMotion] = [:]
    /// The side the layout gave each name last frame. Names it left out aren't here.
    @ObservationIgnored private var labelSides: [UUID: CityLabel.Placement] = [:]

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
    /// Countries too small to see or tap from afar, with their dot's spot and how big the
    /// country itself is (angular radius), so the dot can fade as it grows.
    @ObservationIgnored private var microStates: [(code: String, coordinate: GeoCoordinate, radius: Double)] = []
    /// The slow spin on the whole globe after a few idle seconds is on.
    @ObservationIgnored private var isAutoRotating = false
    /// Wakes a globe at rest for the idle spin, which starts on a timer, not a touch.
    @ObservationIgnored private var spinWake: Task<Void, Never>?

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
        renderer?.riverColor = style.river
    }

    /// The GPU the view's Metal layer must draw with.
    var device: MTLDevice? { renderer?.device }

    // MARK: - Scene

    /// Loads the countries and builds the scene once. Call from the view's `.task`.
    func load(_ worldview: Worldview) async {
        guard !loadStarted, renderer != nil else { return }
        loadStarted = true
        do {
            let started = CACurrentMediaTime()
            let world = try await WorldGeometry.loadBundled(worldview)
            try await build(world, worldview: worldview, started: started)
        } catch {
            Self.log.error("Globe failed to load: \(error)")
        }
    }

    /// Builds the scene from outlines another globe loaded already: a film's globe borrows
    /// the screen's. Returns with walls and rivers in place.
    func load(_ world: WorldGeometry, worldview: Worldview) async {
        guard !loadStarted, renderer != nil else { return }
        loadStarted = true
        do {
            try await build(world, worldview: worldview, started: CACurrentMediaTime())
        } catch {
            Self.log.error("Globe failed to build: \(error)")
        }
    }

    private func build(_ world: WorldGeometry, worldview: Worldview, started: CFTimeInterval) async throws {
        guard let renderer else { return }
        self.worldview = worldview
        let scene = await Self.buildScene(world)
        try renderer.setScene(ocean: scene.ocean, land: scene.land)
        setUpCountries(world, ranges: scene.ranges)
        hitTester = GlobeHitTester(world: world)
        self.world = world
        isReady = true
        playIntro()
        wake()
        let elapsed = Int((CACurrentMediaTime() - started) * 1000)
        Self.log.info("Globe ready in \(elapsed) ms")

        // Walls follow a moment later, while the intro is still flying in.
        let walls = await Self.buildWalls(world)
        try renderer.setWalls(walls.mesh, ranges: walls.ranges)
        try renderer.setRivers(await Self.buildRivers(world))
        wake()
    }

    /// Redraws the borders for another worldview. The globe turns to where they change, the
    /// new outlines land once it's there, and the countries they changed jump and light up.
    /// Reduce Motion just swaps them. Returns once the new borders are on the globe.
    func switchWorldview(_ worldview: Worldview) async {
        guard isReady, worldview != self.worldview, let renderer, let old = world else { return }
        let previous = self.worldview
        self.worldview = worldview
        if !reduceMotion, let focus = worldview.focus ?? previous.focus {
            fly(to: focus, arrivalZoom: GlobeTuning.worldviewZoom)
            wake()
        }
        do {
            let world = try await WorldGeometry.loadBundled(worldview)
            async let scene = Self.buildScene(world)
            async let walls = Self.buildWalls(world)
            async let rivers = Self.buildRivers(world)
            let built = await (scene: scene, walls: walls, rivers: rivers)
            // The change happens in view: wait for the globe to arrive (a drag ends the wait).
            let deadline = CACurrentMediaTime() + 3
            while flight != nil || isFocusing, CACurrentMediaTime() < deadline {
                try? await Task.sleep(for: .milliseconds(50))
            }
            try renderer.setScene(ocean: built.scene.ocean, land: built.scene.land)
            setUpCountries(world, ranges: built.scene.ranges)
            try renderer.setWalls(built.walls.mesh, ranges: built.walls.ranges)
            try renderer.setRivers(built.rivers)
            hitTester = GlobeHitTester(world: world)
            self.world = world

            let before = Dictionary(old.countries.map { ($0.code, $0.vertices.count) }, uniquingKeysWith: { first, _ in first })
            if !reduceMotion {
                for country in world.countries where !country.code.isEmpty && before[country.code] != country.vertices.count {
                    guard var node = nodes[country.code] else { continue }
                    node.lift.velocity += GlobeTuning.celebrationKick * GlobeTuning.quietKickScale
                    // A flash that fades back to whatever the country's glow should be.
                    node.highlight.value = 1
                    nodes[country.code] = node
                    animating.insert(country.code)
                }
            }
            wake()
        } catch {
            Self.log.error("Worldview \(worldview.rawValue) failed to load: \(error)")
        }
    }

    /// The first launch's arrival out of deep space, again: for a fresh start.
    func replayArrival() {
        introStyle = .arrival
        flight = nil
        isFocusing = false
        playIntro()
        wake()
    }

    /// One frame: advance the physics, then draw. The view's display link calls this and
    /// asks again as often as the answer says.
    func renderFrame(deltaTime: TimeInterval, in layer: CAMetalLayer) -> FrameDemand {
        tick(deltaTime: deltaTime)
        renderer?.riverStyle = riverStyle
        renderer?.draw(in: layer, rotation: GlobeOrientation(yaw: yaw.value, pitch: pitch.value).renderQuaternion, camera: camera)
        let demand = nextDemand()
        if demand != frameDemand { frameDemand = demand }
        return demand
    }

    // MARK: - Power

    /// Something changed: draw again, at full rate. Cheap, so everything that can move or
    /// change the globe calls it.
    private func wake() {
        spinWake?.cancel()
        spinWake = nil
        guard frameDemand != .full else { return }
        frameDemand = .full
        onWake?()
    }

    /// What the globe needs after this frame: full rate while anything moves, a low rate
    /// for the idle spin alone, nothing at rest.
    private func nextDemand() -> FrameDemand {
        guard isReady else { return .none }
        if isMoving { return .full }
        if isAutoRotating { return .slow }
        // What's left of a flick is too slow to see; dropped, it can't jump on the next wake.
        yaw.velocity = 0
        pitch.velocity = 0
        scheduleSpinWake()
        #if DEBUG
        framesPerSecond = 0
        frameSample = (0, 0)
        #endif
        return .none
    }

    private var isMoving: Bool {
        if isDragging || isPinching || isFocusing || flight != nil || ring != nil || !animating.isEmpty
            || !arrivals.isEmpty || !zoom.isSettled || !centerOffset.isSettled || !centerShift.isSettled
            || !stageShift.isSettled || !stageLift.isSettled || !stageScale.isSettled {
            return true
        }
        // Coasting after a flick, or springing back inside the tilt limit, faster than the eye
        // can tell from standing still.
        let still = GlobeTuning.restSpeed / max(camera.pointsPerRadian, 1)
        let spin = isAutoRotating ? GlobeTuning.autoRotateSpeed * 1.5 : still
        if abs(yaw.velocity) > spin || abs(pitch.velocity) > still
            || abs(pitch.value) - pitchLimit(atZoom: zoom.value) > still / 10 {
            return true
        }
        if cityMotion.values.contains(where: { !$0.scale.isSettled || $0.landedAt != nil })
            || labelMotion.values.contains(where: { !$0.isSettled }) {
            return true
        }
        // A landing waits for the camera to settle, then goes on the next frame.
        return !pendingLandings.isEmpty && cities.contains { pendingLandings.contains($0.id) && nodes[$0.countryCode] != nil }
    }

    /// On the whole globe with nothing selected the idle spin starts `autoRotateDelay` after
    /// the last touch; a globe at rest by then has to wake up for it.
    private func scheduleSpinWake() {
        guard spinWake == nil, !reduceMotion, selected == nil, zoom.value <= GlobeTuning.autoRotateMaxZoom else { return }
        let delay = max(0, lastInteraction + GlobeTuning.autoRotateDelay - CACurrentMediaTime())
        spinWake = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.wake()
        }
    }

    /// Which rivers show and how wide, from the zoom: on a log scale between the normal size
    /// and fully zoomed in, below it fewer still.
    private var riverStyle: SIMD4<Float> {
        let zoom = max(self.zoom.value, 0.01)
        let progress = Float(Foundation.log(zoom) / Foundation.log(GlobeTuning.zoomRange.upperBound))
        let ranks = GlobeTuning.riverRanks
        return SIMD4(
            ranks.lowerBound + (ranks.upperBound - ranks.lowerBound) * progress,
            Float(pow(max(zoom, 1), GlobeTuning.riverWidthZoomExponent)),
            GlobeTuning.landRadius * GlobeTuning.riverLift,
            GlobeTuning.riverGlint
        )
    }

    func setViewportSize(_ size: CGSize) {
        let old = camera.viewportSize
        guard size != old, size.width > 0, size.height > 0 else { return }
        camera.viewportSize = size
        // A screen twice the size (iPhone Duo opening): for a moment the globe stays the size
        // it was, then springs to fill the new room, instead of popping to it.
        let areas = (size.width * size.height) / max(old.width * old.height, 1)
        if isReady, !reduceMotion, old.width > 0, max(areas, 1 / areas) >= GlobeTuning.resizeCarryOver {
            stageScale.value *= GlobeTuning.baseDiameter(in: old) / GlobeTuning.baseDiameter(in: size)
        }
        retargetStage()
        if reduceMotion { snapStage() }
        applyCenter()
        applyCamera()
        wake()
    }

    /// Moves the globe into `rect` (view points) and sizes it there the way it's sized in the
    /// whole view; `nil` gives it the whole view back. On an open iPhone Duo that's its page
    /// of the spread, while a panel holds the other one or the screen is bent at the fold.
    func setStage(_ rect: CGRect?) {
        guard rect != stage else { return }
        wake()
        stage = rect
        retargetStage()
        if reduceMotion {
            snapStage()
            applyCenter()
            applyCamera()
        }
    }

    private func retargetStage() {
        let size = camera.viewportSize
        guard let stage, size.width > 0, size.height > 0 else {
            stageShift.target = 0
            stageLift.target = 0
            stageScale.target = 1
            return
        }
        stageShift.target = stage.midX - size.width / 2
        stageLift.target = size.height / 2 - stage.midY
        stageScale.target = GlobeTuning.baseDiameter(in: stage.size) / GlobeTuning.baseDiameter(in: size)
    }

    private func snapStage() {
        stageShift.snap()
        stageLift.snap()
        stageScale.snap()
    }

    /// The camera's centre: the panel framing on top of the stage.
    private func applyCenter() {
        camera.centerOffset = centerOffset.value + stageLift.value
        camera.centerShift = centerShift.value + stageShift.value
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

    nonisolated private static func buildRivers(_ world: WorldGeometry) async -> RiverMesh {
        GlobeMeshes.rivers(world)
    }

    /// Land without a selectable country (`code` is empty) keeps one neutral color.
    private func setUpCountries(_ world: WorldGeometry, ranges: [MeshRange]) {
        guard let renderer else { return }
        // A new worldview starts over: Taiwan has no node in China's.
        nodes = [:]
        animating = []
        renderer.pieces = zip(world.countries, ranges).map { shape, range in
            GlobeRenderer.Piece(
                surface: range,
                color: shape.code.isEmpty ? style.unclaimedLand : style.idleColor(slot: shape.colorSlot)
            )
        }
        microStates = world.countries.compactMap { shape in
            guard !shape.code.isEmpty else { return nil }
            let area = shape.areaKm2
            guard area < GlobeTuning.microStateAreaKm2 else { return nil }
            return (shape.code, shape.label, (area / .pi).squareRoot() / GeoMath.earthRadiusKm)
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
        wake()
        let changed = visited.symmetricDifference(codes)
        visited = codes
        changed.forEach(retarget)
    }

    /// Countries marked on another device: they fill in one after another, west to east
    /// across the side in view and on round the back, each with a quiet wave from its
    /// middle, so a world coming back from iCloud sweeps in instead of popping on. Works
    /// before or after `setVisited` has them. Reduce Motion: they fade in as `setVisited`
    /// has them, all at once.
    func fillIn(_ codes: Set<String>, after delay: Double = 0) {
        guard !reduceMotion, isReady else { return }
        wake()
        let center = GlobeOrientation(yaw: yaw.value, pitch: pitch.value).centerCoordinate.longitude
        let order = codes
            .filter { !awaitingMark.contains($0) }
            .compactMap { code in
                nodes[code].map { node in
                    // 0 at the left edge of the side in view, 180 at the right, on to 360 behind.
                    let angle = (node.shape.label.longitude - center + 90).truncatingRemainder(dividingBy: 360)
                    return (code: code, angle: angle < 0 ? angle + 360 : angle)
                }
            }
            .sorted { $0.angle < $1.angle }
        let gap = min(GlobeTuning.arrivalGap, GlobeTuning.arrivalSweep / Double(max(order.count, 1)))
        for (index, country) in order.enumerated() {
            awaitingMark.insert(country.code)
            arrivals.append((country.code, delay + Double(index) * gap))
            retarget(country.code)
        }
        arrivals.sort { $0.wait < $1.wait }
    }

    /// "Mark as visited": the color spreads across the country from `origin` (by default
    /// where it was last touched, else its middle) with a bright front, the country jumps
    /// out of the globe and settles back, and a ring runs off across the planet. Returns
    /// where it starts on screen, for confetti; `nil` if that's out of sight.
    /// `quietly`: a smaller jump and no ring, for marking many countries one after another.
    @discardableResult
    func celebrate(_ code: String, from origin: GeoCoordinate? = nil, quietly: Bool = false) -> CGPoint? {
        wake()
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

    /// Slides the globe up by `offset` points (and right by `shift`) and settles it at `zoom`,
    /// leaving room for a panel underneath (or beside it). `frame(offset: 0, zoom: 1)` puts it back.
    func frame(offset: Double, zoom: Double, shift: Double = 0) {
        wake()
        centerOffset.target = offset
        centerShift.target = shift
        restingZoom = zoom
        flight = nil
        // May go below the pinch range: a panel can leave little room.
        self.zoom.target = min(GlobeTuning.zoomRange.upperBound, max(0.3, zoom))
        zoomSpring = GlobeTuning.framingSpring
        if reduceMotion {
            centerOffset.snap()
            centerShift.snap()
            applyCenter()
            self.zoom.snap()
            applyCamera()
        }
    }

    /// Turns the country to the middle without selecting it.
    func lookAt(_ code: String) {
        wake()
        guard let label = nodes[code]?.shape.label else { return }
        focus(on: label, spring: GlobeTuning.focusSpring)
        lastInteraction = CACurrentMediaTime()
    }

    /// Unmarking, the calm way back: the color drains to the country's middle.
    func drain(_ code: String) {
        wake()
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
        wake()
        let previous = selected
        selected = code
        flight = nil
        [previous, code].compactMap { $0 }.forEach(retarget)
        if let code, let shape = nodes[code]?.shape {
            switch framing {
            case .turn: turn(to: shape)
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
        wake()
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
        wake()
        pendingLandings.insert(id)
        if let countryCode {
            landingsThatMark[id] = countryCode
            awaitingMark.insert(countryCode)
            retarget(countryCode)
        }
    }

    /// The city whose name always shows and whose dot glows a little brighter.
    func highlightCity(_ id: UUID?) {
        wake()
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

        // Tiny countries first: city dots go on top of them.
        for micro in microStates {
            guard let node = nodes[micro.code], let visibility = microStateAlpha(micro.radius), visibility > 0.01 else { continue }
            // Quiet until visited or selected; it brightens with the fill and the glow.
            let emphasis = min(1, max(node.tint.value, node.highlight.value, 0))
            let idle = GlobeTuning.microStateIdleOpacity
            let alpha = visibility * Float(idle + (1 - idle) * emphasis)
            let lift = renderer.pieces[node.index].scale * GlobeTuning.landRadius * 1.0004
            markers.append(GlobeRenderer.Marker(
                position: SIMD4(SIMD3<Float>(GeoMath.unitVector(micro.coordinate)) * lift, GlobeTuning.microStateDotRadius),
                color: SIMD4(node.currentColor, alpha),
                params: SIMD4(1, -1, Float(max(0, node.highlight.value)), 2)
            ))
        }

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
    /// selected country's, then the newest. Shown from `cityLabelZoom` on; dots together on
    /// the globe share a name, crowded ones move aside, names already showing keep their
    /// spots (`CityLabelLayout`). Each pops up out of its dot on a spring and sinks back into
    /// it when it goes, or before it changes (`CityLabelMotion`).
    private func updateCityLabels(_ dt: Double) {
        let showsAll = zoom.value >= GlobeTuning.cityLabelZoom
        var candidates: [(candidate: CityLabelLayout.Candidate, rank: Int)] = []
        var points: [UUID: CGPoint] = [:]
        for (order, city) in cities.enumerated().reversed() {
            guard !pendingLandings.contains(city.id), let spot = screenSpot(of: city) else { continue }
            points[city.id] = spot.point
            let isHighlighted = city.id == highlightedCity
            guard showsAll || isHighlighted else { continue }
            let rank = isHighlighted ? 0 : city.countryCode == selected ? 1 : 2
            let label = CityLabel(id: city.id, name: city.name, point: spot.point, isHighlighted: isHighlighted, isCapital: city.isCapital)
            let candidate = CityLabelLayout.Candidate(
                label: label, location: GeoMath.unitVector(city.coordinate), facing: spot.facing, isFeatured: rank < 2
            )
            candidates.append((candidate, rank * 100_000 - order))
        }
        let ordered = candidates.sorted { $0.rank < $1.rank }.map(\.candidate)
        let placed = CityLabelLayout.place(
            ordered, in: CGRect(origin: .zero, size: camera.viewportSize),
            pointsPerRadian: camera.pointsPerRadian, previous: labelSides
        )
        let placedByID = Dictionary(uniqueKeysWithValues: placed.map { ($0.id, $0) })
        labelSides = placedByID.mapValues(\.placement)

        for label in placed where labelMotion[label.id] == nil {
            labelMotion[label.id] = CityLabelMotion(label)
        }
        let candidatesByID = Dictionary(uniqueKeysWithValues: ordered.map { ($0.label.id, $0.label) })
        let citiesByID = Dictionary(uniqueKeysWithValues: cities.map { ($0.id, $0) })
        var labels: [CityLabel] = []
        for (id, var motion) in labelMotion {
            motion.step(dt, toward: placedByID[id], reduceMotion: reduceMotion)
            // Gone once it has sunk back in, or once its dot went over the horizon.
            guard !motion.isGone, let point = points[id], let city = citiesByID[id] else {
                labelMotion[id] = nil
                continue
            }
            labelMotion[id] = motion
            let label = placedByID[id] ?? candidatesByID[id]
                ?? CityLabel(id: id, name: city.name, point: point, isHighlighted: false, isCapital: city.isCapital)
            labels.append(motion.applied(to: label))
        }
        // Stable order, so names don't swap places in the view every frame.
        labels.sort { $0.id.uuidString < $1.id.uuidString }
        if labels != cityLabels { cityLabels = labels }
    }

    /// The city's dot on screen, or `nil` past the horizon.
    private func screenPoint(of city: CityMarker) -> CGPoint? {
        screenSpot(of: city)?.point
    }

    /// The city's dot on screen and how squarely it faces the camera (1 head-on, 0 at the
    /// horizon), or `nil` past the horizon.
    private func screenSpot(of city: CityMarker) -> (point: CGPoint, facing: Double)? {
        guard let node = nodes[city.countryCode], let renderer else { return nil }
        let lift = Double(renderer.pieces[node.index].scale * GlobeTuning.landRadius)
        let orientation = GlobeOrientation(yaw: yaw.value, pitch: pitch.value)
        let world = orientation.quaternion.act(GeoMath.unitVector(city.coordinate) * lift)
        guard camera.faces(worldPoint: world), let point = camera.screenPoint(ofWorld: world) else { return nil }
        return (point, camera.facing(worldPoint: world))
    }

    /// How strongly a tiny country's dot shows: fully while the country is a speck on
    /// screen, gone once it's big enough to see and tap itself.
    private func microStateAlpha(_ radius: Double) -> Float? {
        func smoothstep(_ range: ClosedRange<Double>, _ x: Double) -> Double {
            let t = min(1, max(0, (x - range.lowerBound) / (range.upperBound - range.lowerBound)))
            return t * t * (3 - 2 * t)
        }
        let shown = smoothstep(GlobeTuning.microStateZoom, zoom.value)
        let tooBig = smoothstep(GlobeTuning.microStateFade, radius * camera.pointsPerRadian)
        return Float(shown * (1 - tooBig))
    }

    /// The tiny country whose dot is under the finger, if its dot shows, and how far off.
    private func microState(at point: CGPoint) -> (micro: (code: String, coordinate: GeoCoordinate), distance: Double)? {
        let orientation = GlobeOrientation(yaw: yaw.value, pitch: pitch.value)
        return microStates
            .filter { (microStateAlpha($0.radius) ?? 0) > 0.3 }
            .compactMap { micro -> (micro: (code: String, coordinate: GeoCoordinate), distance: Double)? in
                let world = orientation.quaternion.act(GeoMath.unitVector(micro.coordinate) * Double(GlobeTuning.landRadius))
                guard camera.faces(worldPoint: world), let screen = camera.screenPoint(ofWorld: world) else { return nil }
                return ((micro.code, micro.coordinate), hypot(screen.x - point.x, screen.y - point.y))
            }
            .filter { $0.distance < GlobeTuning.microStateDotTapRadius * 2 }
            .min { $0.distance < $1.distance }
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
        wake()
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
        wake()
        if isDragging {
            isDragging = false
            lastInteraction = CACurrentMediaTime()
        }
        if isPinching { pinchEnded() }
    }

    func dragEnded(velocity: CGSize) {
        wake()
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
        wake()
        isDragging = false
        yaw.velocity = 0
        pitch.velocity = 0
        lastInteraction = CACurrentMediaTime()
        guard !touchIncludedPinch else { return }
        if let city = city(at: point), let onCityTap {
            onCityTap(city)
        } else if let hit = microState(at: point), hit.distance < GlobeTuning.microStateDotTapRadius
                    || [nil, hit.micro.code].contains(country(at: point)) {
            // Its fill starts from the dot, not from the sea next to it.
            lastTouch = hit.micro
            onCountryTap?(hit.micro.code)
        } else {
            let code = country(at: point)
            lastTouch = code.flatMap { code in coordinate(at: point).map { (code, $0) } }
            onCountryTap?(code)
        }
    }

    /// Zooms toward `anchor`, the point between the fingers when the pinch began: the
    /// place under it stays under it, like on a map.
    func pinchChanged(magnification: CGFloat, anchor: CGPoint) {
        wake()
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
        wake()
        isPinching = false
        pinchAnchor = nil
        let range = GlobeTuning.zoomRange
        zoom.target = min(range.upperBound, max(range.lowerBound, zoom.value))
    }

    /// The zoom the globe is at, or springing to (1 = the whole globe). Past the range while a
    /// pinch stretches it.
    var currentZoom: Double { zoom.target }

    /// Springs in (`factor` above 1) or out a step, around the globe's middle: VoiceOver
    /// adjusting the zoom rail.
    func zoom(by factor: Double) {
        wake()
        isFocusing = false
        flight = nil
        zoomSpring = GlobeTuning.zoomSpring
        let range = GlobeTuning.zoomRange
        zoom.target = min(range.upperBound, max(range.lowerBound, zoom.target * factor))
        lastInteraction = CACurrentMediaTime()
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
        let dt = Self.physicsStep(deltaTime)
        stepRotation(dt)
        stepFlight()
        stepZoom(dt)
        stepArrivals(dt)
        stepCountries(dt)
        stepCities(dt)
        stepRing(dt)
        recoverIfNonFinite()
    }

    /// Starts the fill of each country from another device whose turn has come. One
    /// unmarked meanwhile just stays plain.
    private func stepArrivals(_ dt: Double) {
        guard !arrivals.isEmpty else { return }
        for index in arrivals.indices { arrivals[index].wait -= dt }
        while let next = arrivals.first, next.wait <= 0 {
            arrivals.removeFirst()
            guard awaitingMark.remove(next.code) != nil else { continue }
            if visited.contains(next.code), let middle = nodes[next.code]?.shape.label {
                celebrate(next.code, from: middle, quietly: true)
            }
            retarget(next.code)
        }
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
        isAutoRotating = false
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
        isAutoRotating = !reduceMotion && selected == nil && isOverview && idle > GlobeTuning.autoRotateDelay
        if isAutoRotating {
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
        let scale = Self.focusStepScale(moved: simd_length(step) * camera.pointsPerRadian, dt: dt)
        guard scale < 1 else { return }
        yaw.value = start.yaw + step.x * scale
        pitch.value = start.pitch + step.y * scale
        yaw.velocity *= scale
        pitch.velocity *= scale
    }

    /// The share of this frame's turn the speed limit lets through, 0…1. A frame of no
    /// time lets nothing through; a turn of nothing needs no limit. Never NaN: a NaN here
    /// once spread to the whole rotation and the globe vanished until a relaunch.
    nonisolated static func focusStepScale(moved: Double, dt: Double) -> Double {
        let allowed = GlobeTuning.maxFocusScreenSpeed * max(0, dt)
        guard moved > allowed else { return 1 }
        return allowed / moved
    }

    /// The physics step for a frame: never negative (the display's clock can step back a
    /// frame when its rate changes), never NaN, and clamped so a hitch doesn't fling the globe.
    nonisolated static func physicsStep(_ deltaTime: TimeInterval) -> Double {
        guard deltaTime.isFinite else { return 0 }
        return min(max(deltaTime, 0), 1.0 / 15)
    }

    /// Nothing should ever make the rotation or zoom non-finite, but if something does, the
    /// globe can't be drawn at all and stays blank until a relaunch. Start over instead,
    /// facing the selected country (or the default view).
    private func recoverIfNonFinite() {
        let values = [yaw.value, pitch.value, yaw.velocity, pitch.velocity, zoom.value, zoom.velocity]
        guard values.contains(where: { !$0.isFinite }) else { return }
        Self.log.error("Globe state went non-finite; resetting the view")
        let facing = GlobeOrientation(facing: selected.flatMap { nodes[$0]?.shape.label } ?? GeoCoordinate(latitude: 30, longitude: 15))
        let limit = pitchLimit(atZoom: 1)
        yaw = SpringValue(facing.yaw)
        pitch = SpringValue(max(-limit, min(limit, facing.pitch)))
        if !zoom.value.isFinite || !zoom.velocity.isFinite || !zoom.target.isFinite {
            zoom = SpringValue(restingZoom.isFinite ? max(0.3, restingZoom) : 1)
        }
        isFocusing = false
        flight = nil
        applyCamera()
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
        let target = framing(of: shape, fraction: GlobeTuning.flightFitFraction)
        fly(to: target.center, arrivalZoom: target.zoom)
    }

    /// A tapped country is already in view, so there's no pulling back on the way: the globe
    /// turns to it and the zoom changes until it fills `tapFitFraction` of the screen.
    /// Zooming out starts at once, so up close Russia comes into view as the globe turns
    /// instead of the turn crawling under the speed limit. Zooming in waits for the end of
    /// the turn, like a flight's, or the country would slide off screen first. Both springs
    /// are critically damped, so Reduce Motion gets the same calm move.
    private func turn(to shape: CountryShape) {
        let start = GlobeOrientation(yaw: yaw.value, pitch: pitch.value).centerCoordinate
        let target = framing(of: shape, fraction: GlobeTuning.tapFitFraction)
        let arrivalZoom = target.zoom
        focus(on: target.center, spring: GlobeTuning.focusSpring, atZoom: arrivalZoom)
        zoomSpring = GlobeTuning.tapZoomSpring
        guard arrivalZoom > zoom.value else {
            zoom.target = arrivalZoom
            return
        }
        // Holds the zoom where it is (a previous tap may still be pulling back) until the handoff.
        zoom.target = zoom.value
        let destination = GlobeOrientation(yaw: yaw.target, pitch: pitch.target).centerCoordinate
        flight = Flight(destination: destination, length: GeoMath.angularDistance(start, destination), arrivalZoom: arrivalZoom)
    }

    /// Where to aim at the country, and the zoom at which it (without far-off parts) spans
    /// `fraction` of the screen's shorter side; never below the whole globe.
    private func framing(of shape: CountryShape, fraction: Double) -> (center: GeoCoordinate, zoom: Double) {
        let limit = GlobeTuning.framingExtentLimit
        let framing = GeoMath.framing(of: shape.rings, limit: limit)
            ?? (shape.label, GeoMath.capRadius(around: shape.label, rings: shape.rings, limit: limit))
        return (framing.center, max(1, zoom(fitting: framing.radius, fraction: fraction)))
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

    /// The zoom at which an angular radius around the screen center spans `fraction` of the
    /// stage's shorter side, clamped to the zoom range.
    private func zoom(fitting angle: Double, fraction: Double) -> Double {
        let range = GlobeTuning.zoomRange
        return min(range.upperBound, max(range.lowerBound, unclampedZoom(fitting: angle, fraction: fraction)))
    }

    private func unclampedZoom(fitting angle: Double, fraction: Double) -> Double {
        let size = stage?.size ?? camera.viewportSize
        let side = Double(min(size.width, size.height))
        guard side > 0, angle > 0 else { return .infinity }
        let distance = camera.distance(fitting: angle, screenRadius: side * fraction / 2)
        guard distance > 1 else { return .infinity }
        let silhouette = camera.focalLength / (distance * distance - 1).squareRoot()
        return silhouette / (GlobeTuning.baseDiameter(in: size) / 2)
    }

    private func stepZoom(_ dt: Double) {
        if !isPinching { zoom.step(dt, zoomSpring) }
        if !centerOffset.isSettled { centerOffset.step(dt, GlobeTuning.framingSpring) }
        if !centerShift.isSettled { centerShift.step(dt, GlobeTuning.framingSpring) }
        if !stageShift.isSettled { stageShift.step(dt, GlobeTuning.stageSpring) }
        if !stageLift.isSettled { stageLift.step(dt, GlobeTuning.stageSpring) }
        if !stageScale.isSettled { stageScale.step(dt, GlobeTuning.stageSpring) }
        applyCenter()
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
        guard camera.viewportSize.width > 0, camera.viewportSize.height > 0 else { return }
        let radius = GlobeTuning.baseDiameter(in: camera.viewportSize) / 2 * zoom.value * stageScale.value
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

    // MARK: - Film

    /// The longitude the globe faces, unwrapped: it keeps going past ±180 as the globe turns.
    /// A film checks it to fill each place as it comes round.
    var facingLongitude: Double { -yaw.value * 180 / .pi }

    /// Sets up a film, drawn frame by frame with `renderFilmFrame`: the globe flies in from
    /// deep space, unwinding `filmArrivalSpin` the way it idly spins, to face `coordinate`
    /// at `zoom`, `offset` points below the middle.
    func startFilm(facing coordinate: GeoCoordinate, zoom: Double, offset: Double) {
        let target = GlobeOrientation(facing: coordinate)
        flight = nil
        yaw = SpringValue(target.yaw - GlobeTuning.filmArrivalSpin)
        pitch = SpringValue(0)
        restingZoom = zoom
        self.zoom = SpringValue(GlobeTuning.arrivalStartZoom)
        self.zoom.target = zoom
        zoomSpring = GlobeTuning.filmArrivalSpring
        centerOffset = SpringValue(-offset)
        applyCenter()
        aim(at: coordinate)
        applyCamera()
    }

    /// Follows a point that moves every frame, a step behind on a spring.
    func aim(at coordinate: GeoCoordinate) {
        focus(on: coordinate, spring: GlobeTuning.filmAimSpring)
        // No idle spin: the film turns the globe itself.
        lastInteraction = CACurrentMediaTime()
    }

    /// Follows a point and a zoom that move every frame, a step behind on a spring.
    func aim(at coordinate: GeoCoordinate, zoom: Double) {
        self.zoom.target = zoom
        zoomSpring = GlobeTuning.filmAimSpring
        focus(on: coordinate, spring: GlobeTuning.filmAimSpring, atZoom: zoom)
        lastInteraction = CACurrentMediaTime()
    }

    /// The zoom at which a cap `degrees` across its middle fills `filmFitFraction` of a film
    /// frame's narrower side, between the whole planet (`filmZoom`) and `filmMaxZoom`.
    func filmZoom(fitting degrees: Double) -> Double {
        let zoom = unclampedZoom(fitting: degrees * .pi / 180, fraction: GlobeTuning.filmFitFraction)
        return min(GlobeTuning.filmMaxZoom, max(GlobeTuning.filmZoom, zoom))
    }

    /// Where a place on the globe shows in the frame, standing on its country (lifted as
    /// visited), and how squarely it faces the camera (1 head-on, 0 at the horizon). `nil`
    /// past the horizon. A film's flags stand here.
    func screenPoint(of coordinate: GeoCoordinate) -> (point: CGPoint, facing: Double)? {
        let orientation = GlobeOrientation(yaw: yaw.value, pitch: pitch.value)
        let world = orientation.quaternion.act(GeoMath.unitVector(coordinate) * Double(GlobeTuning.landRadius) * (1 + GlobeTuning.visitedLift))
        guard camera.faces(worldPoint: world), let point = camera.screenPoint(ofWorld: world) else { return nil }
        return (point, camera.facing(worldPoint: world))
    }

    /// Draws the globe at rest into `texture`: every country already at its color and
    /// height, facing `coordinate` at `zoom`, `offset` points below the middle. A story's
    /// picture: one frame, no film to wait through.
    func renderStill(facing coordinate: GeoCoordinate, zoom: Double, offset: Double, into texture: MTLTexture) {
        let target = GlobeOrientation(facing: coordinate)
        let limit = pitchLimit(atZoom: zoom)
        flight = nil
        isFocusing = false
        yaw = SpringValue(target.yaw)
        pitch = SpringValue(max(-limit, min(limit, target.pitch)))
        restingZoom = zoom
        self.zoom = SpringValue(zoom)
        centerOffset = SpringValue(-offset)
        applyCenter()
        // Without motion every spring lands where it's going in a single step.
        let moves = reduceMotion
        reduceMotion = true
        renderFilmFrame(deltaTime: 0, into: texture)
        reduceMotion = moves
    }

    /// Advances the film one frame and draws it into `texture` (see `GlobeRenderer.render`).
    func renderFilmFrame(deltaTime: TimeInterval, into texture: MTLTexture) {
        tick(deltaTime: deltaTime)
        renderer?.riverStyle = riverStyle
        renderer?.render(into: texture, rotation: GlobeOrientation(yaw: yaw.value, pitch: pitch.value).renderQuaternion, camera: camera)
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
