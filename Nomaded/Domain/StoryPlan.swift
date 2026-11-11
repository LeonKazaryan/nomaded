import Foundation

/// The script of a story film (ADR-019): the globe flies in, then tours the places visited
/// stop by stop, the way the Earth spins (east to west, each stop coming round from the
/// left). At each stop the camera comes in close, along the stop's own latitude, so small
/// countries and far-north and far-south ones show; its countries fill one by one, each
/// with its flag; then the camera moves on, pulling back on a long hop. At the end it pulls
/// back to the whole planet for the numbers. Longitudes are unwrapped: they keep going past
/// ±180 so the camera never jumps.
struct StoryPlan: Equatable, Sendable {
    struct Place: Equatable, Sendable {
        let code: String
        /// Its label point: where it fills from and where its flag stands.
        let latitude: Double
        let longitude: Double
        /// The cap around its main land, for framing: its middle and radius (degrees).
        let frame: Spot
        let radius: Double

        init(code: String, latitude: Double, longitude: Double, frame: Spot? = nil, radius: Double = 3) {
            self.code = code
            self.latitude = latitude
            self.longitude = longitude
            self.frame = frame ?? Spot(latitude: latitude, longitude: longitude)
            self.radius = radius
        }
    }

    struct Spot: Equatable, Sendable {
        let latitude: Double
        let longitude: Double
    }

    /// Where the camera looks and how close, at a moment of the film.
    struct Shot: Equatable, Sendable {
        let latitude: Double
        let longitude: Double
        let zoom: Double
    }

    /// One stop of the tour: places close enough to see together.
    struct Stop: Equatable, Sendable {
        /// In the order they fill: east to west.
        let places: [Place]
        let shot: Shot
        /// When the camera gets there, and when it moves on.
        let arrival: Double
        let departure: Double
    }

    /// A place filling in.
    struct Fill: Equatable, Sendable {
        let place: Place
        let time: Double
        /// The first of its stop: it gets the full celebration, ring and all.
        let opensStop: Bool
        /// When the camera moves on from its stop, and its flag goes.
        let departure: Double
    }

    static let framesPerSecond = 30
    /// The globe flies in out of hyperspace, facing the first stop, until this.
    static let arrival = 1.6
    /// Places within this (degrees) of a stop's busiest place are seen at that stop…
    static let crowdRadius = 18.0
    /// …and nearby stops merge until there are no more than this.
    static let maximumStops = 7
    /// A stop never frames less than this (degrees around its middle): a tiny country
    /// alone still shows its neighbours.
    static let closestRadius = 7.0
    /// A big country at a stop's edge may run out of the frame by half: Russia at a stop
    /// with Kazakhstan doesn't push the camera back to the whole planet.
    static let edgeShare = 0.5
    /// A hop between stops takes this long, plus this much per degree, up to the most.
    static let hop = 0.85...1.5
    static let hopPerDegree = 0.007
    /// A stop's places fill this far apart, closer for a crowd: all of them within `fillSpread`.
    static let fillGap = 0.16
    static let fillSpread = 1.2
    /// The first fill starts just before the camera settles, on the move…
    static let fillLead = 0.15
    /// …and the camera stays at least this long at a stop, and this long after its last fill.
    static let shortestStay = 0.85
    static let linger = 0.65
    /// On a hop the camera pulls back toward the whole globe: by a hop this long (degrees),
    /// about all the way.
    static let pullBackSpan = 50.0
    /// The pull back to the whole planet at the end, and the finale on it.
    static let finaleIn = 1.3
    static let finaleHold = 2.2
    /// In the finale the globe drifts on west this fast (degrees a second), so it isn't a still.
    static let drift = 5.0
    static let minimumDuration = 8.0
    /// The camera's latitude stays within this: the poles make a dull view.
    static let latitudes = -45.0...60.0
    /// The picture faces the middle of the biggest crowd, along a latitude within this.
    static let stillLatitudes = -20.0...35.0

    /// The tour's stops, east to west.
    let stops: [Stop]
    /// Every place filling, in time order.
    let fills: [Fill]
    /// The whole film, in seconds.
    let duration: Double
    /// When the camera starts pulling back to the whole planet: the numbers come in then.
    let finale: Double
    /// Where the globe faces as it flies in.
    let opening: Spot
    /// Where the picture faces: the middle of the biggest crowd of places, so it shows as much
    /// color as it can.
    let focus: Spot

    private let wholeZoom: Double
    private let closing: Shot

    /// `wholeZoom`: the zoom that shows the whole planet in the frame. `zoomFitting` gives
    /// the zoom at which a cap of so many degrees fills the frame.
    init(places: [Place], wholeZoom: Double, zoomFitting: (Double) -> Double) {
        self.wholeZoom = wholeZoom
        focus = places.isEmpty ? Spot(latitude: 25, longitude: 0) : Self.crowd(in: places)

        var time = Self.arrival
        var previous: Spot?
        var stops: [Stop] = []
        var fills: [Fill] = []
        for crowd in Self.tour(of: places) {
            let (middle, radius) = Self.reach(of: crowd)
            let shot = Shot(latitude: Self.clamped(middle.latitude), longitude: middle.longitude, zoom: zoomFitting(max(Self.closestRadius, radius)))
            let distance = previous.map { Self.degrees(between: $0, middle) } ?? 0
            let arrival = time + min(Self.hop.upperBound, Self.hop.lowerBound + distance * Self.hopPerDegree)
            let gap = crowd.count > 1 ? min(Self.fillGap, Self.fillSpread / Double(crowd.count - 1)) : 0
            let spread = gap * Double(crowd.count - 1)
            let departure = arrival + max(Self.shortestStay, spread + Self.linger - Self.fillLead)
            for (index, place) in crowd.enumerated() {
                fills.append(Fill(place: place, time: arrival - Self.fillLead + gap * Double(index), opensStop: index == 0, departure: departure))
            }
            stops.append(Stop(places: crowd, shot: shot, arrival: arrival, departure: departure))
            previous = middle
            time = departure
        }
        self.stops = stops
        self.fills = fills
        let last = stops.last?.shot ?? Shot(latitude: 25, longitude: 0, zoom: wholeZoom)
        opening = stops.first.map { Spot(latitude: $0.shot.latitude, longitude: $0.shot.longitude) } ?? Spot(latitude: 25, longitude: 0)
        finale = time
        // The planet ends a little west of the last stop, along a latitude that shows a lot of it.
        closing = Shot(
            latitude: min(max(last.latitude, Self.stillLatitudes.lowerBound), Self.stillLatitudes.upperBound),
            longitude: last.longitude - Self.drift * Self.finaleIn / 2,
            zoom: wholeZoom
        )
        duration = max(Self.minimumDuration, time + Self.finaleIn + Self.finaleHold)
    }

    /// Where the camera looks `time` seconds in: on the first stop while the globe flies in,
    /// then hopping from stop to stop and holding at each, then back out to the whole planet.
    func shot(at time: Double) -> Shot {
        let opening = Shot(latitude: self.opening.latitude, longitude: self.opening.longitude, zoom: wholeZoom)
        var from = opening
        var leaving = Self.arrival
        for stop in stops {
            if time < stop.arrival {
                return Self.hop(from: from, to: stop.shot, progress: (time - leaving) / (stop.arrival - leaving), wholeZoom: wholeZoom)
            }
            if time < stop.departure { return stop.shot }
            from = stop.shot
            leaving = stop.departure
        }
        if time < finale + Self.finaleIn {
            return Self.hop(from: from, to: closing, progress: (time - finale) / Self.finaleIn, wholeZoom: wholeZoom)
        }
        return Shot(latitude: closing.latitude, longitude: closing.longitude - Self.drift * (time - finale - Self.finaleIn), zoom: wholeZoom)
    }

    /// Between two shots: across on a smooth ease, pulling back on the way the farther it goes.
    private static func hop(from a: Shot, to b: Shot, progress: Double, wholeZoom: Double) -> Shot {
        let u = min(max(progress, 0), 1)
        let e = ease(u)
        let distance = degrees(between: Spot(latitude: a.latitude, longitude: a.longitude), Spot(latitude: b.latitude, longitude: b.longitude))
        let straight = log(a.zoom) + (log(b.zoom) - log(a.zoom)) * e
        // How far back the middle of the hop goes: toward the whole globe, all the way by `pullBackSpan`.
        let middle = (log(a.zoom) + log(b.zoom)) / 2
        let cruise = middle + (log(wholeZoom) - middle) * min(1, distance / pullBackSpan)
        let dip = min(0, cruise - middle) * sin(.pi * u)
        return Shot(
            latitude: a.latitude + (b.latitude - a.latitude) * e,
            longitude: a.longitude + (b.longitude - a.longitude) * e,
            zoom: exp(straight + dip)
        )
    }

    /// Smootherstep: no jolt at either end, in speed or in acceleration.
    static func ease(_ u: Double) -> Double {
        let t = min(max(u, 0), 1)
        return t * t * t * (t * (6 * t - 15) + 10)
    }

    // MARK: - The tour

    /// The places as stops, east to west, each stop's places east to west too. Longitudes
    /// come back unwrapped: the tour starts past the widest stretch with nothing visited (a
    /// trip to Europe and Japan crosses Asia, not the Pacific and the Americas) and only
    /// ever goes west.
    private static func tour(of places: [Place]) -> [[Place]] {
        guard !places.isEmpty else { return [] }
        var crowds = crowds(of: places)
        while crowds.count > maximumStops {
            // The two crowds that make the tightest stop together become one: Australia and
            // New Zealand before Europe and the Middle East, so the busiest stop stays close.
            var best = (first: 0, second: 1, radius: Double.infinity)
            for first in crowds.indices {
                for second in crowds.indices where second > first {
                    let radius = reach(of: crowds[first] + crowds[second]).radius
                    if radius < best.radius { best = (first, second, radius) }
                }
            }
            crowds[best.first] += crowds[best.second]
            crowds.remove(at: best.second)
        }

        let middles = crowds.map { middle(of: $0.map(\.frame)) }
        let west = westEnd(of: middles.map(\.longitude))
        func unwrapped(_ longitude: Double) -> Double { west + normalized(longitude - west) }
        return zip(crowds, middles)
            .sorted { (unwrapped($0.1.longitude), $0.0[0].code) > (unwrapped($1.1.longitude), $1.0[0].code) }
            .map { crowd, middle in
                // Unwrapped around the stop's own middle, then onto the tour's scale.
                let base = unwrapped(middle.longitude)
                return crowd
                    .map { place in
                        Place(
                            code: place.code,
                            latitude: place.latitude,
                            longitude: base + wrapped(place.longitude - middle.longitude),
                            frame: Spot(latitude: place.frame.latitude, longitude: base + wrapped(place.frame.longitude - middle.longitude)),
                            radius: place.radius
                        )
                    }
                    .sorted { ($0.longitude, $0.code) > ($1.longitude, $1.code) }
            }
    }

    /// Crowds of places: the place with the most others within `crowdRadius` and those
    /// others, then the same among what's left, until none are.
    private static func crowds(of places: [Place]) -> [[Place]] {
        // By code, so a tie goes the same way every time.
        var left = places.sorted { $0.code < $1.code }
        var crowds: [[Place]] = []
        while !left.isEmpty {
            let neighbours = left.map { place in left.filter { degrees(between: $0.frame, place.frame) <= crowdRadius } }
            let busiest = neighbours.indices.max { neighbours[$0].count < neighbours[$1].count || (neighbours[$0].count == neighbours[$1].count && $0 > $1) }!
            let crowd = neighbours[busiest]
            crowds.append(crowd)
            left.removeAll { place in crowd.contains { $0.code == place.code } }
        }
        return crowds
    }

    /// The west end of the arc `longitudes` fill, leaving out the widest gap between them: a
    /// tour going west from the arc's east end to here never crosses that gap.
    private static func westEnd(of longitudes: [Double]) -> Double {
        let sorted = longitudes.map(normalized).sorted()
        var west = sorted[0]
        var widestGap = sorted[0] + 360 - sorted[sorted.count - 1]
        for (previous, next) in zip(sorted, sorted.dropFirst()) where next - previous > widestGap {
            widestGap = next - previous
            west = next
        }
        return west
    }

    // MARK: - On the sphere

    /// A stop's middle and how far around it (degrees) the camera must take in. Alone, a
    /// country is framed whole; in a crowd, one at the edge may run out by `edgeShare`.
    private static func reach(of crowd: [Place]) -> (middle: Spot, radius: Double) {
        let middle = middle(of: crowd.map(\.frame))
        let share = crowd.count == 1 ? 1 : edgeShare
        return (middle, crowd.map { degrees(between: middle, $0.frame) + $0.radius * share }.max() ?? 0)
    }

    /// Degrees across the globe between two points.
    static func degrees(between a: Spot, _ b: Spot) -> Double {
        CityMath.distanceKm(a.latitude, a.longitude, b.latitude, b.longitude) / 111.2
    }

    /// The middle of some points on the globe: their average direction, so a crowd across
    /// ±180 (Fiji, Samoa) or around a pole lands right. Longitude near the first point's.
    private static func middle(of spots: [Spot]) -> Spot {
        var sum = (x: 0.0, y: 0.0, z: 0.0)
        for spot in spots {
            let latitude = spot.latitude * .pi / 180, longitude = spot.longitude * .pi / 180
            sum.x += cos(latitude) * cos(longitude)
            sum.y += cos(latitude) * sin(longitude)
            sum.z += sin(latitude)
        }
        let length = (sum.x * sum.x + sum.y * sum.y + sum.z * sum.z).squareRoot()
        guard length > 1e-9 else { return spots[0] }
        let latitude = asin(sum.z / length) * 180 / .pi
        let longitude = atan2(sum.y, sum.x) * 180 / .pi
        return Spot(latitude: latitude, longitude: spots[0].longitude + wrapped(longitude - spots[0].longitude))
    }

    /// The middle of the places around the one with the most others near it.
    private static func crowd(in places: [Place]) -> Spot {
        let crowd = crowds(of: places)[0]
        let middle = middle(of: crowd.map { Spot(latitude: $0.latitude, longitude: $0.longitude) })
        return Spot(
            latitude: min(max(middle.latitude, stillLatitudes.lowerBound), stillLatitudes.upperBound),
            longitude: wrapped(middle.longitude)
        )
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
