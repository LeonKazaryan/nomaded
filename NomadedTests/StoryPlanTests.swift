import Testing
@testable import Nomaded

struct StoryPlanTests {
    private static func place(_ code: String, _ latitude: Double, _ longitude: Double) -> StoryPlan.Place {
        StoryPlan.Place(code: code, latitude: latitude, longitude: longitude)
    }

    private static let france = place("FR", 46, 2)
    private static let italy = place("IT", 42, 12)
    private static let japan = place("JP", 36, 138)
    private static let usa = place("US", 39, -98)
    private static let brazil = place("BR", -10, -52)
    private static let australia = place("AU", -25, 134)

    /// Europe and Japan: across Asia, not the long way over the Pacific and the Americas.
    @Test func theTurnSkipsTheEmptySide() {
        let plan = StoryPlan(places: [Self.france, Self.italy, Self.japan])
        #expect(plan.start > 138)
        #expect(plan.end < 2)
        #expect(plan.start - plan.end < 200)
    }

    /// The way the Earth spins: Japan comes round first, France last.
    @Test func placesComeInTurnOrder() {
        let plan = StoryPlan(places: [Self.france, Self.italy, Self.japan])
        #expect(plan.places.map(\.code) == ["JP", "IT", "FR"])
    }

    /// The globe still turns a good way, and comes to rest on the place.
    @Test func aTripToOnePlaceStillTurns() {
        let plan = StoryPlan(places: [Self.italy])
        #expect(plan.start - plan.end >= StoryPlan.minimumSpan)
        #expect(abs(plan.places[0].longitude - plan.end) <= 10)
    }

    @Test func nothingFillsBeforeTheTurnAndEverythingByItsEnd() {
        let plan = StoryPlan(places: [Self.france, Self.italy, Self.japan, Self.usa, Self.brazil, Self.australia])
        #expect(plan.reached(atLongitude: plan.longitude(at: 0)).isEmpty)
        #expect(plan.reached(atLongitude: plan.longitude(at: StoryPlan.sweep.upperBound)).count == 6)
    }

    @Test func theTurnNeverRunsBack() {
        let plan = StoryPlan(places: [Self.france, Self.japan, Self.usa])
        let times = stride(from: 0.0, through: StoryPlan.duration, by: 1.0 / Double(StoryPlan.framesPerSecond))
        let longitudes = times.map(plan.longitude(at:))
        #expect(zip(longitudes, longitudes.dropFirst()).allSatisfy { $0 >= $1 })
        #expect(longitudes.last! < plan.end)
    }

    /// Five places in Europe and one in America: the picture faces Europe.
    @Test func theStillFacesTheCrowd() {
        let europe = [Self.france, Self.italy, Self.place("DE", 51, 10), Self.place("ES", 40, -4), Self.place("CH", 47, 8)]
        let plan = StoryPlan(places: europe + [Self.usa])
        #expect((-10...20).contains(plan.focus.longitude))
        #expect(plan.focus.latitude <= StoryPlan.latitudes.upperBound)
    }

    /// Fiji and Samoa straddle ±180: their middle is out in the Pacific, not over Africa.
    @Test func aCrowdAcrossTheDateLine() {
        let plan = StoryPlan(places: [Self.place("FJ", -17, 178), Self.place("WS", -13, -172)])
        #expect(abs(abs(plan.focus.longitude) - 180) < 10)
    }

    @Test func noPlaces() {
        let plan = StoryPlan(places: [])
        #expect(plan.places.isEmpty)
        #expect(plan.reached(atLongitude: plan.end).isEmpty)
    }
}
