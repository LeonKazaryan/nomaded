import CoreGraphics

/// Everything that defines how the globe feels. Tune on a real iPhone, not the simulator.
enum GlobeTuning {
    // MARK: Size and zoom

    /// Globe diameter as a share of the screen width at zoom 1…
    static let baseDiameterRatio = 0.88
    /// …or of its height, whichever is smaller: an iPad on its side (or a wide window) shows
    /// the whole planet, with room for the bar above and the card below.
    static let baseDiameterHeightRatio = 0.74

    /// The globe's diameter at zoom 1 in a view this size, in points.
    static func baseDiameter(in size: CGSize) -> Double {
        min(Double(size.width) * baseDiameterRatio, Double(size.height) * baseDiameterHeightRatio)
    }
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

    // MARK: Marking a country

    /// The visited color spreading across a country from where it was touched.
    static let fillWaveSpring = SpringParameters(response: 0.95, dampingRatio: 1)
    /// Unmarking: the color draining back to the middle. Calmer than the fill.
    static let drainWaveSpring = SpringParameters(response: 1.1, dampingRatio: 1)
    /// Reduce Motion keeps the fill, short.
    static let quickWaveSpring = SpringParameters(response: 0.35, dampingRatio: 1)
    /// How bright the band riding the wave's edge is, 0…1.
    static let fillWaveFront: Float = 0.6
    static let drainWaveFront: Float = 0.18
    /// The ring a marked country sends across the planet: when it sets off (seconds after
    /// the fill starts), how it decelerates, and how far it travels past the country (radians).
    static let ringDelay = 0.3
    static let ringSpring = SpringParameters(response: 1.6, dampingRatio: 1)
    static let ringReach = 1.25
    /// A quiet mark (picking countries while onboarding) jumps this much of a full one.
    static let quietKickScale = 0.5

    // MARK: Syncing

    /// Countries marked on another device fill in one after another, this far apart (s)…
    static let arrivalGap = 0.08
    /// …and all of them within this long, however many come at once.
    static let arrivalSweep = 1.6
    /// A world restored from iCloud starts filling in once the introduction has faded.
    static let restoreFillDelay = 0.45

    // MARK: Story film

    /// The film's globe flies in from deep space too, unwinding less spin (radians)…
    static let filmArrivalSpin = 2.6
    /// …a little quicker than the first launch: a story is short.
    static let filmArrivalSpring = SpringParameters(response: 1.9, dampingRatio: 1)
    /// The camera following the film's path: close behind, never a jolt.
    static let filmAimSpring = SpringParameters(response: 0.55, dampingRatio: 1)
    /// Smaller than on screen, leaving room for the numbers above and the name below.
    static let filmZoom = 0.78

    // MARK: First launch

    /// The globe flies in from deep space: it starts this small…
    static let arrivalStartZoom = 0.04
    /// …unwinding this much spin (radians) on the way…
    static let arrivalSpin = 7.0
    /// …on this spring, slower than the everyday intro.
    static let arrivalSpring = SpringParameters(response: 2.4, dampingRatio: 1)
    /// Sliding the globe up over a panel and back, and resizing it with it.
    static let framingSpring = SpringParameters(response: 0.8, dampingRatio: 1)
    /// On an open iPhone Duo, the globe gliding onto its page of the spread and back out to
    /// the whole screen: a touch of overshoot, so it lands like something set down.
    static let stageSpring = SpringParameters(response: 0.7, dampingRatio: 0.8)
    /// The view's area changing at least this many times over in one go (iPhone Duo unfolding
    /// doubles it): the globe keeps its size on screen for a moment, then grows into the new
    /// room (or shrinks into it, folding). Smaller changes, like dragging an iPad window, just follow.
    static let resizeCarryOver = 1.3
    static let selectedBrightening: Float = 0.22
    static let wallShade: Float = 0.5

    // MARK: Rivers

    /// The ranks shown in full at the normal size and fully zoomed in; the zoom between
    /// (on a log scale) fades the next ranks in, smaller rivers growing upstream.
    static let riverRanks: ClosedRange<Float> = 3.5...8.5
    /// Width in points at the normal size, from Natural Earth's drawing weight (0.15 for a
    /// stream … 2 for the Amazon's mouth).
    static func riverWidth(weight: Float) -> Float { 0.6 + weight * 1.0 }
    /// Rivers widen with the zoom, but slower than the land grows.
    static let riverWidthZoomExponent = 0.3
    /// How far above the land a river floats, so the land never shows through it.
    static let riverLift: Float = 1.0002
    /// How much brighter than the land the fill wave's front lights the water.
    static let riverGlint: Float = 1.6

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
    /// Near the horizon, where the globe squeezes dots together, names sink back into them:
    /// once a dot faces the camera less squarely than the lower bound (1 head-on, 0 at the
    /// horizon). One comes back above the upper bound, so it doesn't blink at the edge.
    static let cityLabelHorizon = 0.2...0.3

    // MARK: Power

    /// A globe coasting slower than this (points per second on screen) counts as stopped:
    /// it stops drawing until something changes.
    static let restSpeed = 0.5
    /// Frames per second while only the idle spin moves. It's so slow that more frames
    /// look no smoother, and the globe spends most of its on-screen time like this.
    static let idleSpinFrameRate: Float = 30

    // MARK: Taps

    static let tapSlop = 10.0
    static let microStateTapRadius = 14.0

    // MARK: Zoom rail

    /// A finger sliding up or down the screen's right edge zooms (`ZoomRail`): this far doubles
    /// or halves the zoom. The whole range is then about four times this, the rail's own
    /// length, so its fill keeps pace with the finger.
    static let zoomRailPointsPerDoubling = 110.0
    /// How far in from the right edge a touch can start the rail, in points.
    static let zoomRailEdgeWidth = 30.0

    // MARK: Tiny countries

    /// Countries and territories smaller than this (km²) get a dot: Vatican, Monaco, Malta,
    /// Singapore, island nations. Luxembourg (2 600) is big enough to see up close.
    static let microStateAreaKm2 = 1_000.0
    static let microStateDotRadius: Float = 4.2
    /// How strongly the dot of a country not yet visited shows, 0…1: a quiet hint. Marked
    /// or selected, it shows in full.
    static let microStateIdleOpacity = 0.45
    /// The dot fades out between these on-screen radii of the country itself, in points:
    /// once it's big enough to see and tap, it needs no dot.
    static let microStateFade = 3.0...9.0
    /// …and fades in over this zoom: on the whole globe Italy is a few dozen points, and
    /// the Vatican's and San Marino's dots would cover it.
    static let microStateZoom = 1.4...2.2
    /// A tap this close to a tiny country's dot picks it, in points: on the dot itself
    /// always, out to twice as far when the finger is on the sea or on that country.
    /// Further out on a neighbour's land (Rome's suburbs around the Vatican) the land wins.
    static let microStateDotTapRadius = 7.0
    /// Share of the screen's shorter side a tapped country takes once the globe has turned to it:
    /// up close a tap on Russia pulls back, from afar a tap on Belgium moves in.
    static let tapFitFraction = 0.6
    static let tapZoomSpring = SpringParameters(response: 0.8, dampingRatio: 1)

    // MARK: Flight to a country (search)

    /// How close the globe comes when the borders switch to another App Store region's: close
    /// enough to see Crimea and Donbas change hands, wide enough to see both countries.
    static let worldviewZoom = 2.6

    /// Share of the screen's shorter side the country takes when the flight lands.
    static let flightFitFraction = 0.6
    /// Parts of a country farther than this from the middle of its biggest landmass
    /// (radians, ~26°) are ignored when framing it, unless that landmass is wider itself
    /// (Russia): France is framed without French Guiana, the US without Alaska.
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
