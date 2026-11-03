/// Everything that defines how the globe feels. Tune on a real iPhone, not the simulator.
enum GlobeTuning {
    // MARK: Size and zoom

    /// Globe diameter as a share of the screen width at zoom 1.
    static let baseDiameterRatio = 0.88
    /// At 14 the screen shows about 300 km across: Luxembourg or Andorra fill a good part of it.
    static let zoomRange = 0.85...14.0
    /// Lifted countries rise less when zoomed in, so up close they don't tower over their
    /// neighbours. 0 keeps the full height, 1 shrinks it as fast as the zoom grows.
    static let liftZoomDamping = 0.5

    // MARK: Rotation

    /// How far north/south the globe can tilt, in radians (~69°), seen whole…
    static let pitchLimit = 1.2
    /// …and zoomed in (~83°), so far-north and far-south places (Tromsø, Svalbard) can come
    /// to the center of the screen.
    static let pitchLimitClose = 1.45
    /// The zoom over which the limit opens from one to the other.
    static let pitchLimitOpening = 2.0...4.0
    /// Spin decay per second after a flick. Higher stops sooner.
    static let friction = 1.6
    static let maxSpinVelocity = 9.0
    static let autoRotateDelay = 5.0
    static let autoRotateSpeed = 0.07
    /// No idle spin while someone is looking closely.
    static let autoRotateMaxZoom = 1.5
    /// Fastest the surface may slide past while the globe turns to a country, in points
    /// per second. Keeps a long swing readable when zoomed in.
    static let maxFocusScreenSpeed = 3000.0

    // MARK: Countries

    /// Land sits just above the ocean sphere.
    static let landRadius: Float = 1.003
    /// Side walls reach this far inside the globe, so a lifted country never shows a gap.
    static let wallBottom: Float = 0.9
    static let visitedLift = 0.008
    static let selectedLift = 0.02
    /// Upward velocity given to a country when it's marked as visited.
    static let celebrationKick = 0.35
    static let selectedBrightening: Float = 0.22
    static let wallShade: Float = 0.5

    // MARK: Cities

    /// Dot radius in points: small sparks on the whole globe, full size up close.
    static let cityDotRadius = 2.6...4.4
    /// Zoom at which dots reach full size.
    static let cityDotFullZoom = 5.0
    /// Names show from this zoom on, when a region fills the screen. The highlighted city's
    /// name shows at any zoom.
    static let cityLabelZoom = 2.6
    /// How close a flight to a city lands: a city and its surroundings.
    static let cityZoom = 9.0
    /// A tap this close to a dot picks the city, in points.
    static let cityTapRadius = 22.0
    /// A new city lands: it starts this many times its size and springs down to it.
    static let cityDropScale = 3.2
    static let cityDropSpring = SpringParameters(response: 0.45, dampingRatio: 0.45)
    /// How long the ring around a new city takes to spread and fade, in seconds.
    static let cityRippleDuration = 1.1
    /// A name popping up out of its dot as it comes into view, and sinking back as it goes.
    static let cityLabelSpring = SpringParameters(response: 0.32, dampingRatio: 0.62)

    // MARK: Taps

    static let tapSlop = 10.0
    static let microStateTapRadius = 14.0

    // MARK: Flight to a country (search)

    /// Share of the screen width the country takes when the flight lands.
    static let flightFitFraction = 0.6
    /// Parts of a country farther than this from its center (radians, ~26°) are ignored
    /// when framing it: France is framed without French Guiana.
    static let framingExtentLimit = 0.45
    /// How far a flight pulls back on the way: cruise zoom = this / trip length in radians.
    /// Long trips zoom out to the whole globe, short hops stay close.
    static let flightCruiseScale = 1.5
    /// Start zooming in when this share of the trip is left.
    static let flightHandoff = 0.4

    // MARK: Springs

    static let focusSpring = SpringParameters(response: 0.75, dampingRatio: 1)
    static let introSpring = SpringParameters(response: 1.6, dampingRatio: 1)
    static let zoomSpring = SpringParameters(response: 0.35, dampingRatio: 1)
    static let flightSpring = SpringParameters(response: 1.1, dampingRatio: 1)
    static let flightZoomSpring = SpringParameters(response: 0.9, dampingRatio: 1)
    static let pitchWallSpring = SpringParameters(response: 0.35, dampingRatio: 1)
    static let liftSpring = SpringParameters(response: 0.5, dampingRatio: 0.55)
    static let colorSpring = SpringParameters(response: 0.55, dampingRatio: 0.7)
}
