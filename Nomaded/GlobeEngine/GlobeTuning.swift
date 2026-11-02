/// Everything that defines how the globe feels. Tune on a real iPhone, not the simulator.
enum GlobeTuning {
    // MARK: Size and zoom

    /// Globe diameter as a share of the screen width at zoom 1.
    static let baseDiameterRatio = 0.88
    static let zoomRange = 0.85...4.0

    // MARK: Rotation

    /// How far north/south the globe can tilt, in radians (~69°).
    static let pitchLimit = 1.2
    /// Spin decay per second after a flick. Higher stops sooner.
    static let friction = 1.6
    static let maxSpinVelocity = 9.0
    static let autoRotateDelay = 5.0
    static let autoRotateSpeed = 0.07

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

    // MARK: Taps

    static let tapSlop = 10.0
    static let microStateTapRadius = 14.0

    // MARK: Springs

    static let focusSpring = SpringParameters(response: 0.75, dampingRatio: 1)
    static let introSpring = SpringParameters(response: 1.6, dampingRatio: 1)
    static let zoomSpring = SpringParameters(response: 0.35, dampingRatio: 1)
    static let pitchWallSpring = SpringParameters(response: 0.35, dampingRatio: 1)
    static let liftSpring = SpringParameters(response: 0.5, dampingRatio: 0.55)
    static let colorSpring = SpringParameters(response: 0.55, dampingRatio: 0.7)
}
