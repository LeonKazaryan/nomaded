import Foundation
import SwiftData
import Testing
@testable import Nomaded

/// Disputed borders by App Store region (ADR-015).
struct WorldviewTests {
    struct Place: Sendable, CustomTestStringConvertible {
        let name: String
        let latitude: Double
        let longitude: Double
        /// Who owns it by default, in Russia's App Store, China's and India's.
        let standard: String
        let russia: String
        let china: String
        let india: String

        var testDescription: String { name }
    }

    @Test(arguments: [
        Place(name: "Simferopol", latitude: 44.95, longitude: 34.1, standard: "UA", russia: "RU", china: "UA", india: "UA"),
        Place(name: "Sevastopol", latitude: 44.6, longitude: 33.52, standard: "UA", russia: "RU", china: "UA", india: "UA"),
        Place(name: "Donetsk", latitude: 48.0, longitude: 37.8, standard: "UA", russia: "RU", china: "UA", india: "UA"),
        Place(name: "Luhansk", latitude: 48.57, longitude: 39.33, standard: "UA", russia: "RU", china: "UA", india: "UA"),
        Place(name: "Mariupol", latitude: 47.1, longitude: 37.55, standard: "UA", russia: "RU", china: "UA", india: "UA"),
        Place(name: "Melitopol", latitude: 46.84, longitude: 35.37, standard: "UA", russia: "RU", china: "UA", india: "UA"),
        Place(name: "Zaporizhzhia", latitude: 47.84, longitude: 35.14, standard: "UA", russia: "RU", china: "UA", india: "UA"),
        Place(name: "Kherson", latitude: 46.66, longitude: 32.62, standard: "UA", russia: "RU", china: "UA", india: "UA"),
        Place(name: "Kyiv", latitude: 50.45, longitude: 30.52, standard: "UA", russia: "UA", china: "UA", india: "UA"),
        Place(name: "Kharkiv", latitude: 49.99, longitude: 36.23, standard: "UA", russia: "UA", china: "UA", india: "UA"),
        Place(name: "Moscow", latitude: 55.75, longitude: 37.62, standard: "RU", russia: "RU", china: "RU", india: "RU"),
        Place(name: "Taipei", latitude: 25.04, longitude: 121.56, standard: "TW", russia: "TW", china: "CN", india: "TW"),
        Place(name: "Itanagar", latitude: 27.1, longitude: 93.62, standard: "IN", russia: "IN", china: "CN", india: "IN"),
        Place(name: "Delhi", latitude: 28.61, longitude: 77.21, standard: "IN", russia: "IN", china: "IN", india: "IN"),
        Place(name: "Thimphu", latitude: 27.47, longitude: 89.64, standard: "BT", russia: "BT", china: "BT", india: "BT"),
        Place(name: "Gilgit", latitude: 35.92, longitude: 74.31, standard: "PK", russia: "PK", china: "PK", india: "IN"),
        Place(name: "Skardu", latitude: 35.3, longitude: 75.63, standard: "PK", russia: "PK", china: "PK", india: "IN"),
        Place(name: "Muzaffarabad", latitude: 34.37, longitude: 73.47, standard: "PK", russia: "PK", china: "PK", india: "IN"),
        Place(name: "Aksai Chin", latitude: 35.2, longitude: 79.2, standard: "CN", russia: "CN", china: "CN", india: "IN"),
        Place(name: "Shaksgam Valley", latitude: 36.1, longitude: 76.5, standard: "CN", russia: "CN", china: "CN", india: "IN"),
        Place(name: "Srinagar", latitude: 34.08, longitude: 74.8, standard: "IN", russia: "IN", china: "IN", india: "IN"),
        Place(name: "Leh", latitude: 34.16, longitude: 77.58, standard: "IN", russia: "IN", china: "IN", india: "IN"),
        Place(name: "Islamabad", latitude: 33.69, longitude: 73.05, standard: "PK", russia: "PK", china: "PK", india: "PK"),
        Place(name: "Kashgar", latitude: 39.47, longitude: 75.99, standard: "CN", russia: "CN", china: "CN", india: "CN"),
    ])
    func eachRegionsGlobeDrawsItsOwnBorders(_ place: Place) async throws {
        let coordinate = GeoCoordinate(latitude: place.latitude, longitude: place.longitude)
        for (worldview, expected) in [(Worldview.standard, place.standard), (.russia, place.russia), (.china, place.china), (.india, place.india)] {
            let world = try await WorldGeometry.loadBundled(worldview)
            let tester = GlobeHitTester(world: world)
            #expect(tester.country(at: coordinate, tolerance: 0.01) == expected, "\(place.name) in \(worldview)")
            // Disputed land says so itself, exactly; elsewhere the outlines decide.
            if let owner = world.owner(at: coordinate) { #expect(owner == expected, "\(place.name) owner in \(worldview)") }
        }
    }

    @Test func overlaysOnlyRedrawWhatTheyChange() async throws {
        let standard = try await WorldGeometry.loadBundled()
        let russia = try await WorldGeometry.loadBundled(.russia)
        let china = try await WorldGeometry.loadBundled(.china)
        let india = try await WorldGeometry.loadBundled(.india)

        #expect(russia.countries.count == standard.countries.count)
        #expect(china.countries.count == standard.countries.count - 1)
        #expect(!china.countries.contains { $0.code == "TW" })
        #expect(india.countries.count == standard.countries.count)
        // Same lakes; rivers still point at real countries.
        for world in [russia, china, india] {
            #expect(world.lakes.count == standard.lakes.count)
            #expect(world.rivers.allSatisfy { $0.country < world.countries.count })
            #expect(abs(world.rivers.count - standard.rivers.count) < 40)
        }
        // Crimea moved: Russia bigger, Ukraine smaller, everyone else untouched.
        let size = { (world: WorldGeometry, code: String) in world.countries.first { $0.code == code }!.vertices.count }
        #expect(size(russia, "RU") > size(standard, "RU"))
        #expect(size(russia, "UA") < size(standard, "UA"))
        #expect(size(russia, "FR") == size(standard, "FR"))
        // Kashmir moved: India bigger, Pakistan and China smaller.
        #expect(size(india, "IN") > size(standard, "IN"))
        #expect(size(india, "PK") < size(standard, "PK"))
        #expect(size(india, "FR") == size(standard, "FR"))
    }

    @Test func storefrontsPickTheirWorldview() {
        #expect(Worldview(storefront: "RUS") == .russia)
        #expect(Worldview(storefront: "CHN") == .china)
        #expect(Worldview(storefront: "IND") == .india)
        #expect(Worldview(storefront: "PAK") == .standard)
        #expect(Worldview(storefront: "rus") == .russia)
        #expect(Worldview(storefront: "KAZ") == .standard)
        #expect(Worldview(storefront: "UKR") == .standard)
        #expect(Worldview(storefront: "TWN") == .standard)
    }

    @Test func citiesOnDisputedLandFollowTheGlobe() async throws {
        let bundled = try CityCatalog.loadBundled()
        // Natural Earth files Crimea's cities under Russia; the default globe shows Ukraine.
        #expect(bundled.cities(named: "Simferopol", in: "UA").count == 1)
        #expect(bundled.cities(named: "Simferopol", in: "RU").isEmpty)

        let russia = try await WorldGeometry.loadBundled(.russia)
        let relabeled = bundled.relabeled { russia.owner(at: $0) }
        #expect(relabeled.cities(named: "Simferopol", in: "RU").count == 1)
        // Russia has a Donetsk of its own, in the Rostov region; Ukraine's joins it.
        #expect(relabeled.cities(named: "Donetsk", in: "RU").count == 2)
        #expect(relabeled.cities(named: "Donetsk", in: "UA").isEmpty)
        #expect(bundled.cities(named: "Donetsk", in: "UA").count == 1)
        #expect(relabeled.cities(named: "Kyiv", in: "UA").count == 1)
        #expect(relabeled.cities(in: "RU", limit: .max).contains { $0.name == "Sevastopol" })

        let china = try await WorldGeometry.loadBundled(.china)
        #expect(bundled.relabeled { china.owner(at: $0) }.cities(named: "Taipei", in: "CN").count == 1)

        #expect(bundled.cities(named: "Gilgit", in: "PK").count == 1)
        let india = try await WorldGeometry.loadBundled(.india)
        #expect(bundled.relabeled { india.owner(at: $0) }.cities(named: "Gilgit", in: "IN").count == 1)
    }

    /// The default file leaves the Siachen Glacier to no one: it's land there, not a hole
    /// down to the ocean, but no country's. India's globe has it in India.
    @Test func siachenIsLandEverywhereAndIndiasInIndia() async throws {
        let siachen = GeoCoordinate(latitude: 35.4, longitude: 77.0)
        let standard = try await WorldGeometry.loadBundled()
        #expect(standard.countries.contains { $0.code.isEmpty && GeoMath.ringsContain($0.rings, longitude: 77.0, latitude: 35.4) })
        #expect(GlobeHitTester(world: standard).country(at: siachen, tolerance: 0.01) == nil)
        #expect(standard.owner(at: siachen) == nil)

        let india = try await WorldGeometry.loadBundled(.india)
        #expect(GlobeHitTester(world: india).country(at: siachen, tolerance: 0.01) == "IN")
        #expect(india.owner(at: siachen) == "IN")
    }

    @Test func countsLeaveOutWhatTheGlobeDoesnt() async throws {
        let china = try await WorldGeometry.loadBundled(.china)
        let places = CountryCatalog.bundled.limited(to: china.countries.map(\.code))
        #expect(places["TW"] == nil)
        #expect(places["CN"] != nil)
        #expect(places.countries.filter(\.isSovereign).count == 195)
    }
}

@MainActor
struct WorldviewStoreTests {
    private let container: ModelContainer

    init() throws {
        container = try WorldStore.makeContainer(ModelConfiguration(isStoredInMemoryOnly: true))
    }

    /// Saved when the globe still filed Crimea under Russia: the city moves to the country
    /// the globe shows there and marks it; Russia stays marked.
    @Test func savedCitiesMoveToTheGlobesOwner() {
        let store = WorldStore(container: container)
        store.addCity(CityDraft(name: "Simferopol", region: "", countryCode: "RU", latitude: 44.95, longitude: 34.1))
        store.addCity(CityDraft(name: "Moscow", region: "", countryCode: "RU", latitude: 55.75, longitude: 37.62))

        let moved = store.reassignCities { $0.latitude < 46 ? "UA" : nil }

        #expect(moved)
        #expect(store.cities(in: "UA").map(\.name) == ["Simferopol"])
        #expect(store.cities(in: "RU").map(\.name) == ["Moscow"])
        #expect(store.visitedCodes == ["RU", "UA"])
        #expect(!store.reassignCities { $0.latitude < 46 ? "UA" : nil })
    }

    @Test func resetForgetsEverything() {
        let store = WorldStore(container: container)
        store.markVisited("FR")
        store.addCity(CityDraft(name: "Rome", region: "", countryCode: "IT", latitude: 41.9, longitude: 12.5))
        store.earnMilestones()
        #expect(!store.milestones.isEmpty)

        store.resetAll()

        #expect(store.visitedCodes.isEmpty)
        #expect(store.cities.isEmpty)
        #expect(store.milestones.isEmpty)
    }
}
