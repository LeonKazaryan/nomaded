import Foundation
import Testing
@testable import Nomaded

struct WorldStatsTests {
    private let catalog = CountryCatalog([
        Country(code: "FR", continent: .europe, subregion: .westernEurope, isSovereign: true, areaKm2: 640_000),
        Country(code: "DE", continent: .europe, subregion: .westernEurope, isSovereign: true, areaKm2: 357_000),
        Country(code: "IT", continent: .europe, subregion: .southernEurope, isSovereign: true, areaKm2: 301_000),
        Country(code: "VA", continent: .europe, subregion: .southernEurope, isSovereign: true, areaKm2: 0.44),
        Country(code: "JP", continent: .asia, subregion: .easternAsia, isSovereign: true, areaKm2: 378_000),
        Country(code: "GL", continent: .northAmerica, subregion: .northernAmerica, isSovereign: false, areaKm2: 2_160_000),
        Country(code: "AQ", continent: .antarctica, subregion: .antarctica, isSovereign: false, areaKm2: 14_000_000),
    ])

    @Test func nothingVisited() {
        let stats = StatsCalculator.stats(visited: [], catalog: catalog)
        #expect(stats.countries == .init(visited: 0, total: 5))
        #expect(stats.territories == 0)
        #expect(stats.visitedContinents == 0)
        #expect(stats.regions.isEmpty)
        #expect(stats.landShare == 0)
        #expect(stats.largest == nil && stats.smallest == nil)
    }

    @Test func countriesAndTerritoriesCountSeparately() {
        let stats = StatsCalculator.stats(visited: ["FR", "VA", "GL"], catalog: catalog)
        #expect(stats.countries == .init(visited: 2, total: 5))
        #expect(stats.countries.share == 0.4)
        #expect(stats.territories == 1)
    }

    @Test func aTerritoryStillVisitsItsContinent() {
        let stats = StatsCalculator.stats(visited: ["GL", "AQ"], catalog: catalog)
        let byContinent = Dictionary(uniqueKeysWithValues: stats.continents.map { ($0.continent, $0) })

        #expect(stats.continents.map(\.continent) == Continent.allCases)
        #expect(byContinent[.northAmerica]?.isVisited == true)
        #expect(byContinent[.northAmerica]?.countries == .init(visited: 0, total: 0))
        #expect(byContinent[.antarctica]?.isVisited == true)
        #expect(byContinent[.europe]?.isVisited == false)
        #expect(stats.visitedContinents == 2)
    }

    @Test func regionsMostCompleteFirst() {
        let stats = StatsCalculator.stats(visited: ["IT", "VA", "FR", "JP"], catalog: catalog)
        // Both complete regions first; on a tie, the one with more countries visited.
        #expect(stats.regions.map(\.subregion) == [.southernEurope, .easternAsia, .westernEurope])
        #expect(stats.regions.last?.countries == .init(visited: 1, total: 2))
    }

    @Test func largestSmallestAndLand() {
        let stats = StatsCalculator.stats(visited: ["FR", "VA", "JP"], catalog: catalog)
        #expect(stats.largest == "FR")
        #expect(stats.smallest == "VA")
        let total = catalog.countries.reduce(0) { $0 + $1.areaKm2 }
        let visited: Double = 640_000 + 0.44 + 378_000
        #expect(abs(stats.landShare - visited / total) < 1e-12)
    }

    @Test func continentPlacesSplitAndSort() {
        let places = StatsCalculator.places(on: .europe, visited: ["IT", "FR"], catalog: catalog, locale: Locale(identifier: "en_US"))
        #expect(places.discovered == ["FR", "IT"])
        #expect(places.undiscovered == ["DE", "VA"])
        #expect(places.discoveredTerritories.isEmpty && places.undiscoveredTerritories.isEmpty)

        let north = StatsCalculator.places(on: .northAmerica, visited: ["GL"], catalog: catalog)
        #expect(north.discoveredTerritories == ["GL"])
        #expect(north.discovered.isEmpty && north.undiscovered.isEmpty)
    }

    @Test func worldPlacesCoverEveryContinent() {
        let world = StatsCalculator.places(on: nil, visited: ["JP", "GL"], catalog: catalog, locale: Locale(identifier: "en_US"))
        #expect(world.discovered == ["JP"])
        // France, Germany, Italy, Vatican City.
        #expect(world.undiscovered == ["FR", "DE", "IT", "VA"])
        #expect(world.discoveredTerritories == ["GL"])
        #expect(world.undiscoveredTerritories == ["AQ"])
    }

    /// The top counter, the visited list and the statistics all count through `split`.
    @Test func splitSeparatesCountriesFromTerritories() {
        let places = catalog.split(["GL", "FR", "ZZ", "AQ", "VA"])
        #expect(places == VisitedPlaces(countries: ["FR", "VA"], territories: ["GL", "AQ"]))

        let stats = StatsCalculator.stats(visited: ["GL", "FR", "ZZ", "AQ", "VA"], catalog: catalog)
        #expect(stats.countries.visited == places.countries.count)
        #expect(stats.territories == places.territories.count)
    }

    @Test func unknownCodesAreIgnored() {
        let stats = StatsCalculator.stats(visited: ["FR", "ZZ"], catalog: catalog)
        #expect(stats.countries.visited == 1)
    }

    /// Each continent's mini-map frames its own countries and marks them as home.
    @Test func continentMapsFrameTheirCountries() async throws {
        let maps = await ContinentMaps.build(world: try await WorldGeometry.loadBundled(), catalog: try CountryCatalog.loadBundled())
        for (continent, code) in [(Continent.europe, "FR"), (.asia, "JP"), (.africa, "KE"), (.northAmerica, "MX"),
                                  (.southAmerica, "PE"), (.oceania, "NZ"), (.antarctica, "AQ")] {
            let outline = try #require(maps.outlines[continent]?.first { $0.code == code }, "\(code) missing on \(continent)")
            #expect(outline.isHome)
            #expect(abs(outline.center.x) < 1.6 && abs(outline.center.y) < 1.2, "\(code) is off the \(continent) tile")
        }
        // The far side of the Earth never reaches a tile.
        #expect(maps.outlines[.europe]?.first { $0.code == "AU" } == nil)
    }

    /// The bundled catalog matches the product's definitions and the globe's countries.
    @Test func bundledCatalogMatchesTheGlobe() async throws {
        let catalog = try CountryCatalog.loadBundled()
        let globe = Set(try await WorldGeometry.loadBundled().countries.map(\.code).filter { !$0.isEmpty })

        #expect(catalog.countries.filter(\.isSovereign).count == 195)
        #expect(Set(catalog.countries.map(\.code)) == globe)
        #expect(catalog["VA"]?.isSovereign == true && catalog["PS"]?.isSovereign == true)
        #expect(catalog["TW"]?.isSovereign == false && catalog["GL"]?.isSovereign == false)
        #expect(catalog["RU"]?.continent == .europe && catalog["KZ"]?.continent == .asia)

        let land = catalog.countries.reduce(0) { $0 + $1.areaKm2 }
        #expect(land > 140_000_000 && land < 150_000_000)
    }
}
