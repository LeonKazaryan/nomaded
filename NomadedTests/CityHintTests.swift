import Testing
@testable import Nomaded

struct CityHintTests {
    @Test func aNewUserGetsIt() {
        #expect(CityHint().isDue(citiesExist: false))
    }

    @Test func itStopsAfterThreeShows() {
        var hint = CityHint()
        for _ in 0..<CityHint.maxShows {
            #expect(hint.isDue(citiesExist: false))
            hint.recordShow()
        }
        #expect(!hint.isDue(citiesExist: false))
    }

    /// Cities saved before the hint existed (an update from 1.1), or synced from an iPad.
    @Test func anyCityOnTheListMeansTheyKnow() {
        #expect(!CityHint().isDue(citiesExist: true))
    }

    @Test func removingTheOnlyCityDoesNotBringItBack() {
        var hint = CityHint()
        hint.noteCities(exist: true)
        hint.noteCities(exist: false)
        #expect(hint.hasAddedCity)
        #expect(!hint.isDue(citiesExist: false))
    }

    @Test func anEmptyListIsNotACity() {
        var hint = CityHint(shows: 1)
        hint.noteCities(exist: false)
        #expect(!hint.hasAddedCity)
        #expect(hint.isDue(citiesExist: false))
    }
}
