import Foundation

/// When the country card points out "+ City". Many people mark countries without ever
/// finding out they can add cities, so the card shows them right after a mark: until their
/// first city, and three times at most (docs/02-design.md → Cities).
struct CityHint: Equatable {
    /// How many times it has been shown.
    var shows = 0
    /// A city was added at some point, here or on another device. Removing it later doesn't
    /// bring the hint back: they know.
    var hasAddedCity = false

    static let maxShows = 3

    /// Whether marking a country now should point out its cities. `citiesExist`: whether
    /// any city is saved right now (one may have come from iCloud before this was recorded).
    func isDue(citiesExist: Bool) -> Bool {
        !hasAddedCity && !citiesExist && shows < Self.maxShows
    }

    /// Shown once more.
    mutating func recordShow() {
        shows += 1
    }

    /// Any city on the list counts as having added one.
    mutating func noteCities(exist: Bool) {
        if exist { hasAddedCity = true }
    }
}
