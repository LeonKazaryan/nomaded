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

struct CityMathTests {
    @Test func distanceBetweenKnownCities() {
        // Paris – London is about 344 km.
        let km = CityMath.distanceKm(48.8566, 2.3522, 51.5074, -0.1278)
        #expect(abs(km - 344) < 3)
    }

    @Test func sameCityNeedsSameCountryAndCloseness() {
        let rome = CityPin(id: UUID(), name: "Rome", region: "", countryCode: "IT", latitude: 41.9, longitude: 12.5, createdAt: .now)
        // The same name a few kilometres off: another source's Rome.
        #expect(CityMath.isSamePlace(rome, CityDraft(name: "Rome", region: "", countryCode: "IT", latitude: 41.95, longitude: 12.45)))
        // Another name on the same spot.
        #expect(CityMath.isSamePlace(rome, CityDraft(name: "Roma", region: "", countryCode: "IT", latitude: 41.905, longitude: 12.505)))
        // A town next door is its own city.
        #expect(!CityMath.isSamePlace(rome, CityDraft(name: "Ciampino", region: "", countryCode: "IT", latitude: 41.8, longitude: 12.6)))
        #expect(!CityMath.isSamePlace(rome, CityDraft(name: "Rome", region: "", countryCode: "VA", latitude: 41.9, longitude: 12.45)))
    }
}

struct CityCatalogTests {
    private static func city(_ name: String, ru: String? = nil, _ code: String, pop: Int, capital: Bool = false,
                             lat: Double = 0, lon: Double = 0) -> KnownCity {
        let json = """
        {"name":"\(name)","nameRu":\(ru.map { "\"\($0)\"" } ?? "null"),"aliases":[],"region":null,"code":"\(code)",\
        "lat":\(lat),"lon":\(lon),"population":\(pop),"capital":\(capital)}
        """
        return try! JSONDecoder().decode(KnownCity.self, from: Data(json.utf8))
    }

    private let catalog = CityCatalog([
        city("London", ru: "Лондон", "US", pop: 7_844),
        city("London", ru: "Лондон", "GB", pop: 8_567_000, capital: true, lat: 51.5, lon: -0.12),
        city("London", ru: "Лондон", "CA", pop: 346_765),
        city("Londrina", "BR", pop: 506_000),
        city("New York City", ru: "Нью-Йорк", "US", pop: 19_040_000),
        city("York", "GB", pop: 153_000),
    ])

    @Test func biggerCityWinsAmongEqualMatches() {
        #expect(catalog.search("London").map(\.countryCode) == ["GB", "CA", "US"])
        #expect(catalog.search("лон").map(\.countryCode) == ["GB", "CA", "US"])
    }

    @Test func wholeNameBeatsStartBeatsLaterWord() {
        // All four start with "Lond", so size decides.
        #expect(catalog.search("Lond").map(\.population) == [8_567_000, 506_000, 346_765, 7_844])
        // "York" itself before New York, though New York is bigger.
        #expect(catalog.search("York").map(\.name) == ["York", "New York City"])
    }

    @Test func staysInsideACountry() {
        #expect(catalog.search("London", in: "CA").map(\.countryCode) == ["CA"])
    }

    @Test func countryListPutsTheCapitalFirst() {
        let kazakhstan = CityCatalog([
            Self.city("Shymkent", "KZ", pop: 465_392),
            Self.city("Almaty", "KZ", pop: 1_209_000),
            Self.city("Astana", "KZ", pop: 345_604, capital: true),
            Self.city("Bishkek", "KG", pop: 837_000, capital: true),
        ])
        #expect(kazakhstan.cities(in: "KZ").map(\.name) == ["Astana", "Almaty", "Shymkent"])
        #expect(kazakhstan.cities(in: "KZ", limit: 2).map(\.name) == ["Astana", "Almaty"])
        #expect(kazakhstan.cities(in: "UZ").isEmpty)
    }

    @Test @MainActor func emptyFieldListsOnlyACountrysCities() {
        let catalog = CityCatalog([
            Self.city("Almaty", "KZ", pop: 1_209_000),
            Self.city("Astana", "KZ", pop: 345_604, capital: true),
            Self.city("Bishkek", "KG", pop: 837_000, capital: true),
        ])
        let inCountry = CitySearch(countryCode: "KZ", catalog: catalog)
        inCountry.query = ""
        #expect(inCountry.results.map(\.title) == ["Astana", "Almaty"])
        #expect(inCountry.results.first?.isCapital == true)
        inCountry.query = "Alm"
        #expect(inCountry.results.map(\.title) == ["Almaty"])

        // The whole world is too much to list: it waits for a name.
        let worldwide = CitySearch(catalog: catalog)
        worldwide.query = ""
        #expect(worldwide.results.isEmpty)
    }

    @Test func bundledCountryListsLeadWithTheirCapital() throws {
        let bundled = try CityCatalog.loadBundled()
        #expect(bundled.cities(in: "IT").prefix(3).map(\.name) == ["Rome", "Milan", "Naples"])
        #expect(bundled.cities(in: "US").first?.name == "Washington")
        #expect(bundled.cities(in: "RU").count == 50)
        #expect(bundled.cities(in: "VA").map(\.name) == ["Vatican City"])
        // Renamed back in 2022; the old name still finds it.
        #expect(bundled.cities(in: "KZ").first?.name == "Astana")
        #expect(bundled.search("Нур-Султан").first?.name == "Astana")
    }

    @Test func spellingsAndScriptsMeet() {
        #expect(CityCatalog.key("Алматы") == CityCatalog.key("Almaty"))
        #expect(CityCatalog.key("São Paulo") == "saopaulo")
        #expect(CityCatalog.key("Alma-Ata") == "almaata")
    }

    @Test func savedCitiesFindTheirListEntry() {
        let catalog = CityCatalog([
            Self.city("Almaty", ru: "Алматы", "KZ", pop: 1_209_000, lat: 43.27, lon: 76.91),
            Self.city("Talgar", "KZ", pop: 45_000, lat: 43.3, lon: 77.24),
        ])
        // Saved from a Russian search: the same city by name, a few kilometres off.
        #expect(catalog.city(named: "Алматы", in: "KZ", latitude: 43.24, longitude: 76.95)?.name == "Almaty")
        // Right on top of it, whatever it's called.
        #expect(catalog.city(named: "Medeu", in: "KZ", latitude: 43.275, longitude: 76.915)?.name == "Almaty")
        // A town nearby isn't the city.
        #expect(catalog.city(named: "Boraldai", in: "KZ", latitude: 43.36, longitude: 76.86) == nil)
        #expect(catalog.cities(named: "Talgar", in: "KZ").count == 1)
        #expect(catalog.cities(named: "Talgar", in: "KG").isEmpty)
    }

    @Test func bundledListHasEachCityOnce() throws {
        let bundled = try CityCatalog.loadBundled()
        #expect(bundled.cities(named: "Aktau", in: "KZ").count == 1)
        #expect(bundled.cities(named: "Denpasar", in: "ID").count == 1)
        // Twin cities across a state line stay two.
        #expect(bundled.cities(named: "Kansas City", in: "US").count == 2)
        #expect(bundled.cities(in: "KZ").first { $0.name == "Almaty" }?.nameRu == "Алматы")
        #expect(bundled.search("Алма-Ата").first?.name == "Almaty")
    }

    @Test func findsCapitalsNearby() {
        let westminster = CityPin(id: UUID(), name: "London", region: "", countryCode: "GB", latitude: 51.51, longitude: -0.13, createdAt: .now)
        let ontario = CityPin(id: UUID(), name: "London", region: "", countryCode: "CA", latitude: 42.97, longitude: -81.25, createdAt: .now)
        #expect(catalog.isCapital(westminster))
        #expect(!catalog.isCapital(ontario))
    }

    @Test func bundledListHasTheCapitals() throws {
        let bundled = try CityCatalog.loadBundled()
        #expect(bundled.cities.count > 7_000)
        let london = try #require(bundled.search("London").first)
        #expect(london.countryCode == "GB" && london.isCapital)
        #expect(bundled.search("Москва").first?.countryCode == "RU")
        #expect(bundled.cities.filter(\.isCapital).count >= 195)
    }
}
