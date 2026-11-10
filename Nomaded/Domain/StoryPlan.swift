import Foundation

/// The script of a story film (ADR-019): the globe flies in, turns across the places
/// visited the way the Earth spins (each new place comes round from the left), and fills
/// each one as it nears the front. Longitudes here are unwrapped: they keep going past
/// ±180 so the turn never jumps.
struct StoryPlan: Equatable, Sendable {
    struct Place: Equatable, Sendable {
        let code: String
        let latitude: Double
        let longitude: Double
    }

    struct Spot: Equatable, Sendable {
        let latitude: Double
        let longitude: Double
    }

    /// The whole film, in seconds.
    static let duration = 8.0
    static let framesPerSecond = 30
    /// The turn across the places runs over these seconds, starting as the globe arrives…
    static let sweep = 1.2...5.2
    /// …and after it the globe keeps drifting the same way this fast (degrees a second), so
    /// the finale isn't a still.
    static let drift = 5.0
    /// A place fills when it's this far (degrees) left of the middle, so its fill plays as it
    /// turns to the front.
    static let lead = 22.0
    /// A trip around one region still gets this much turn, so the globe visibly moves. The
    /// extra comes before the places: the film ends on them.
    static let minimumSpan = 100.0
    /// The turn starts this far beyond the first place: just enough that it fills on the move.
    static let margin = 26.0
    /// The latitude the camera looks along stays within this: the poles make a dull view.
    static let latitudes = -20.0...35.0
    /// Places this close (degrees across the globe) count as one crowd for the still.
    static let crowdRadius = 40.0

    /// Where the camera faces before the turn and where the turn ends (unwrapped). The turn
    /// runs west: `end` < `start`.
    let start: Double
    let end: Double
    let latitude: Double
    /// Every place, on the same unwrapped scale as `start`, in the order the turn reaches them.
    let places: [Place]
    /// Where the still faces: the middle of the biggest crowd of places, so the picture
    /// shows as much color as it can.
    let focus: Spot

    /// The turn covers every place but skips the widest stretch with nothing visited: a trip
    /// to Europe and Japan crosses Asia, not the Pacific and the Americas.
    init(places: [Place]) {
        guard !places.isEmpty else {
            start = Self.minimumSpan
            end = 0
            latitude = 25
            self.places = []
            focus = Spot(latitude: 25, longitude: 0)
            return
        }
        let longitudes = places.map { Self.normalized($0.longitude) }.sorted()
        // The places fill the arc from `west` eastward, `span` wide.
        var west = longitudes[0]
        var widestGap = longitudes[0] + 360 - longitudes[longitudes.count - 1]
        for (previous, next) in zip(longitudes, longitudes.dropFirst()) where next - previous > widestGap {
            widestGap = next - previous
            west = next
        }
        let span = 360 - widestGap
        let unwrapped = places
            .map { Place(code: $0.code, latitude: $0.latitude, longitude: west + Self.normalized($0.longitude - west)) }
            .sorted { ($0.longitude, $0.code) > ($1.longitude, $1.code) }
        end = west - 5
        start = end + max(Self.minimumSpan, span + Self.margin + 5)
        let mean = places.map(\.latitude).reduce(0, +) / Double(places.count)
        latitude = Self.clamped(mean)
        self.places = unwrapped
        focus = Self.crowd(in: places)
    }

    /// Where the camera aims `time` seconds in: still until the turn, then easing across
    /// and on into the drift.
    func longitude(at time: Double) -> Double {
        let u = (time - Self.sweep.lowerBound) / (Self.sweep.upperBound - Self.sweep.lowerBound)
        return start - (start - end) * Self.ease(u) - Self.drift * max(0, time - Self.sweep.upperBound)
    }

    /// The places the camera has come round to, facing `longitude`: the ones to fill.
    func reached(atLongitude longitude: Double) -> [Place] {
        places.filter { longitude <= $0.longitude + Self.lead }
    }

    /// Smoothstep: gets going soon and settles without a jolt.
    static func ease(_ u: Double) -> Double {
        let t = min(max(u, 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// The middle of the places around the one with the most others near it.
    private static func crowd(in places: [Place]) -> Spot {
        func isNear(_ a: Place, _ b: Place) -> Bool {
            CityMath.distanceKm(a.latitude, a.longitude, b.latitude, b.longitude) / 111.2 < crowdRadius
        }
        let ordered = places.sorted { $0.code < $1.code }
        let center = ordered.max { lhs, rhs in
            ordered.count(where: { isNear($0, lhs) }) < ordered.count(where: { isNear($0, rhs) })
        } ?? ordered[0]
        let crowd = ordered.filter { isNear($0, center) }
        // Longitudes around the center, so a crowd across ±180 (Fiji, Samoa) averages right.
        let longitude = crowd.map { center.longitude + wrapped($0.longitude - center.longitude) }.reduce(0, +) / Double(crowd.count)
        let latitude = crowd.map(\.latitude).reduce(0, +) / Double(crowd.count)
        return Spot(latitude: clamped(latitude), longitude: longitude)
    }

    private static func clamped(_ latitude: Double) -> Double {
        min(max(latitude, latitudes.lowerBound), latitudes.upperBound)
    }

    /// Into -180…180.
    private static func wrapped(_ longitude: Double) -> Double {
        let value = normalized(longitude)
        return value > 180 ? value - 360 : value
    }

    /// Into 0..<360.
    private static func normalized(_ longitude: Double) -> Double {
        let value = longitude.truncatingRemainder(dividingBy: 360)
        return value < 0 ? value + 360 : value
    }
}
