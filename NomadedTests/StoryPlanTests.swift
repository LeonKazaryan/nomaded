import Testing
@testable import Nomaded

struct StoryPlanTests {
    private static func place(_ code: String, _ latitude: Double, _ longitude: Double, radius: Double = 3) -> StoryPlan.Place {
        StoryPlan.Place(code: code, latitude: latitude, longitude: longitude, radius: radius)
    }

    /// Stands in for the globe: the smaller the cap, the closer, within the film's range.
    private static let wholeZoom = 0.78
    private static func plan(_ places: [StoryPlan.Place]) -> StoryPlan {
        StoryPlan(places: places, wholeZoom: wholeZoom, zoomFitting: { min(4.2, max(wholeZoom, 40 / $0)) })
    }

    private static let france = place("FR", 46, 2)
    private static let italy = place("IT", 42, 12)
    private static let germany = place("DE", 51, 10)
    private static let spain = place("ES", 40, -4)
    private static let switzerland = place("CH", 47, 8)
    private static let japan = place("JP", 36, 138)
    private static let usa = place("US", 39, -98, radius: 20)
    private static let brazil = place("BR", -10, -52, radius: 18)
    private static let australia = place("AU", -25, 134, radius: 20)
    private static let norway = place("NO", 61, 9)
    private static let newZealand = place("NZ", -41, 174)
    private static let europe = [france, italy, germany, spain, switzerland]

    private static func times(_ plan: StoryPlan) -> [Double] {
        Array(stride(from: 0.0, through: plan.duration, by: 1.0 / Double(StoryPlan.framesPerSecond)))
    }

    @Test func aRegionIsOneStop() {
        let plan = Self.plan(Self.europe)
        #expect(plan.stops.count == 1)
        #expect(plan.stops[0].places.count == 5)
    }

    /// Europe and Japan: from Japan west across Asia to Europe, not over the Pacific and the
    /// Americas; each stop's countries east to west too.
    @Test func theTourGoesWestAndSkipsTheEmptySide() {
        let plan = Self.plan([Self.france, Self.italy, Self.japan])
        #expect(plan.stops.map { $0.places.map(\.code) } == [["JP"], ["IT", "FR"]])
        #expect(plan.stops[0].shot.longitude - plan.stops[1].shot.longitude < 180)
    }

    @Test func everyPlaceFillsOnceAtItsStop() {
        let places = Self.europe + [Self.japan, Self.usa, Self.brazil, Self.australia, Self.norway, Self.newZealand]
        let plan = Self.plan(places)
        #expect(plan.fills.count == places.count)
        #expect(Set(plan.fills.map(\.place.code)) == Set(places.map(\.code)))
        #expect(zip(plan.fills, plan.fills.dropFirst()).allSatisfy { $0.time <= $1.time })
        for stop in plan.stops {
            let fills = plan.fills.filter { fill in stop.places.contains { $0.code == fill.place.code } }
            #expect(fills.count == stop.places.count)
            #expect(fills.allSatisfy { $0.time >= stop.arrival - StoryPlan.fillLead && $0.time < stop.departure })
            #expect(fills.filter(\.opensStop).count == 1)
        }
    }

    /// Frame to frame the camera glides, even on the longest hop: no jump in where it looks
    /// or how close it is, where one stretch of the film hands over to the next.
    @Test func theCameraNeverJumps() {
        let plan = Self.plan(Self.europe + [Self.japan, Self.usa, Self.brazil, Self.australia, Self.newZealand, Self.norway])
        let shots = Self.times(plan).map(plan.shot(at:))
        let steps = zip(shots, shots.dropFirst())
        #expect(steps.map { abs($1.latitude - $0.latitude) }.max()! < 5)
        #expect(steps.map { abs($1.longitude - $0.longitude) }.max()! < 8)
        #expect(steps.map { max($0.zoom, $1.zoom) / min($0.zoom, $1.zoom) }.max()! < 1.2)
    }

    /// The way the Earth spins: the camera only ever moves west.
    @Test func theCameraOnlyGoesWest() {
        let plan = Self.plan(Self.europe + [Self.japan, Self.usa, Self.brazil, Self.australia])
        let longitudes = Self.times(plan).map { plan.shot(at: $0).longitude }
        #expect(zip(longitudes, longitudes.dropFirst()).allSatisfy { $0 >= $1 - 1e-9 })
    }

    /// Far north and far south, the camera looks along the stop's own latitude, not one
    /// latitude for the whole film, so Norway and New Zealand are in the frame.
    @Test func farNorthAndFarSouthAreSeenFromTheirOwnLatitude() {
        let plan = Self.plan([Self.norway, Self.newZealand, Self.japan])
        let latitudes = Dictionary(uniqueKeysWithValues: plan.stops.map { ($0.places[0].code, $0.shot.latitude) })
        #expect(latitudes["NO"]! > 55)
        #expect(latitudes["NZ"]! < -35)
    }

    /// A small country alone comes as close as the film goes; a big one, less.
    @Test func smallPlacesComeCloser() {
        let luxembourg = Self.plan([Self.place("LU", 49.8, 6.1, radius: 0.5)])
        let russia = Self.plan([Self.place("RU", 62, 94, radius: 40)])
        #expect(luxembourg.stops[0].shot.zoom > russia.stops[0].shot.zoom)
        #expect(luxembourg.stops[0].shot.zoom > 2)
    }

    /// Around the whole world the tour still makes few stops and a short film.
    @Test func theWholeWorldStaysShort() {
        let places = stride(from: -170.0, to: 180, by: 9).enumerated().map { index, longitude in
            Self.place("X\(index)", Double(index % 7) * 12 - 36, longitude)
        }
        let plan = Self.plan(places)
        #expect(plan.stops.count <= StoryPlan.maximumStops)
        #expect(plan.fills.count == places.count)
        #expect(plan.duration <= 26)
    }

    @Test func oneTripIsStillAFilm() {
        let plan = Self.plan([Self.italy])
        #expect(plan.stops.count == 1)
        #expect(plan.duration == StoryPlan.minimumDuration)
        #expect(plan.fills[0].opensStop)
    }

    /// The film opens on the first stop and ends on the whole planet, after every fill.
    @Test func theFinaleShowsTheWholePlanet() {
        let plan = Self.plan(Self.europe + [Self.japan, Self.usa])
        #expect(plan.shot(at: 0).zoom == Self.wholeZoom)
        #expect(plan.shot(at: plan.duration).zoom == Self.wholeZoom)
        #expect(plan.finale >= plan.stops.last!.departure)
        #expect(plan.fills.allSatisfy { $0.time < plan.finale })
        #expect(plan.stops.allSatisfy { $0.shot.zoom > Self.wholeZoom })
    }

    /// Five places in Europe and one in America: the picture faces Europe.
    @Test func theStillFacesTheCrowd() {
        let plan = Self.plan(Self.europe + [Self.usa])
        #expect((-10...20).contains(plan.focus.longitude))
        #expect(plan.focus.latitude <= StoryPlan.stillLatitudes.upperBound)
    }

    /// Fiji and Samoa straddle ±180: one stop, out in the Pacific, not over Africa.
    @Test func aCrowdAcrossTheDateLine() {
        let plan = Self.plan([Self.place("FJ", -17, 178), Self.place("WS", -13, -172)])
        #expect(abs(abs(plan.focus.longitude) - 180) < 10)
        #expect(plan.stops.count == 1)
        #expect(abs(plan.stops[0].places[0].longitude - plan.stops[0].places[1].longitude) < 20)
    }

    @Test func noPlaces() {
        let plan = Self.plan([])
        #expect(plan.stops.isEmpty)
        #expect(plan.fills.isEmpty)
        #expect(plan.duration == StoryPlan.minimumDuration)
        #expect(Self.times(plan).allSatisfy { plan.shot(at: $0).zoom == Self.wholeZoom })
    }
}
