import Foundation
import Testing
import simd
@testable import Nomaded

struct WorldGeometryTests {
    struct Place: Sendable, CustomTestStringConvertible {
        let name: String
        let latitude: Double
        let longitude: Double
        let expected: String?

        var testDescription: String { name }
    }

    @Test func bundledWorldIsComplete() async throws {
        let world = try await WorldGeometry.loadBundled()
        let codes = Set(world.countries.map(\.code))

        #expect(world.countries.count > 200)
        #expect(world.lakes.count > 300)
        for code in ["IT", "VA", "KZ", "UA", "TW", "BR", "AQ", "LS"] {
            #expect(codes.contains(code), "missing \(code)")
        }
        for shape in world.countries {
            #expect(shape.indices.count % 3 == 0)
            #expect(shape.indices.allSatisfy { Int($0) < shape.vertices.count }, "bad index in \(shape.code)")
        }
    }

    @Test(arguments: [
        Place(name: "Rome", latitude: 41.9, longitude: 12.5, expected: "IT"),
        Place(name: "Almaty", latitude: 43.24, longitude: 76.89, expected: "KZ"),
        Place(name: "Simferopol", latitude: 44.95, longitude: 34.1, expected: "UA"),
        Place(name: "Rio de Janeiro", latitude: -22.9, longitude: -43.2, expected: "BR"),
        Place(name: "Maseru (enclave inside South Africa)", latitude: -29.31, longitude: 27.48, expected: "LS"),
        Place(name: "Johannesburg", latitude: -26.2, longitude: 28.05, expected: "ZA"),
        Place(name: "Anchorage", latitude: 61.2, longitude: -149.9, expected: "US"),
        Place(name: "Mid-Atlantic", latitude: 0, longitude: -30, expected: nil),
        Place(name: "Sea just off Monaco", latitude: 43.70, longitude: 7.45, expected: "MC"),
        // Lakes are water on the globe, but a tap on one picks the land around it.
        Place(name: "Lake Baikal", latitude: 53.5, longitude: 108.2, expected: "RU"),
        Place(name: "Lake Ladoga", latitude: 60.8, longitude: 31.5, expected: "RU"),
        Place(name: "Lake Victoria off Entebbe", latitude: 0.0, longitude: 32.6, expected: "UG"),
        Place(name: "Chicago, on Lake Michigan", latitude: 41.88, longitude: -87.63, expected: "US"),
    ])
    func hitTestFindsCountry(_ place: Place) async throws {
        let tester = GlobeHitTester(world: try await WorldGeometry.loadBundled())
        let coordinate = GeoCoordinate(latitude: place.latitude, longitude: place.longitude)
        #expect(tester.country(at: coordinate, tolerance: 0.01) == place.expected)
    }

    /// Long edges far up north once got split along great circles, which bulge toward the
    /// pole: Russia's mesh folded out over the Arctic Ocean. Checks a sample of triangles.
    @Test(arguments: ["RU", "US", "CA", "AQ", "GL", "NO"])
    func meshStaysInsideTheOutline(_ code: String) async throws {
        let world = try await WorldGeometry.loadBundled()
        let shape = try #require(world.countries.first { $0.code == code })
        var area = 0.0, outside = 0.0
        for t in stride(from: 0, to: shape.indices.count, by: 3 * 7) {
            let a = SIMD3<Double>(shape.vertices[Int(shape.indices[t])])
            let b = SIMD3<Double>(shape.vertices[Int(shape.indices[t + 1])])
            let c = SIMD3<Double>(shape.vertices[Int(shape.indices[t + 2])])
            let triangleArea = simd_length(simd_cross(b - a, c - a)) / 2
            let center = GeoMath.coordinate(of: a + b + c)
            area += triangleArea
            if !GeoMath.ringsContain(shape.rings, longitude: Float(center.longitude), latitude: Float(center.latitude)) {
                outside += triangleArea
            }
        }
        #expect(outside / area < 0.005, "\(code): \(outside / area * 100)% of the mesh lies outside its outline")
    }

    /// The land has the larger lakes cut out, so the ocean shows through: also where a lake
    /// lies across a border.
    @Test(arguments: [
        Place(name: "Lake Baikal", latitude: 53.5, longitude: 108.2, expected: "RU"),
        Place(name: "Lake Victoria, Ugandan side", latitude: -0.5, longitude: 33.0, expected: "UG"),
        Place(name: "Lake Victoria, Tanzanian side", latitude: -1.5, longitude: 32.8, expected: "TZ"),
        Place(name: "Lake Superior, Canadian side", latitude: 48.0, longitude: -87.0, expected: "CA"),
        Place(name: "Lake Titicaca", latitude: -15.8, longitude: -69.4, expected: "PE"),
    ])
    func lakesAreCutOutOfTheLand(_ place: Place) async throws {
        let world = try await WorldGeometry.loadBundled()
        let shape = try #require(world.countries.first { $0.code == place.expected })
        #expect(!GeoMath.ringsContain(shape.rings, longitude: Float(place.longitude), latitude: Float(place.latitude)))
        #expect(world.lakes.contains { GeoMath.ringsContain([$0.shore], longitude: Float(place.longitude), latitude: Float(place.latitude)) })
    }

    @Test func neighboursNeverShareAColor() async throws {
        let world = try await WorldGeometry.loadBundled()
        let slots = Dictionary(uniqueKeysWithValues: world.countries.filter { !$0.code.isEmpty }.map { ($0.code, $0.colorSlot) })
        for (a, b) in [("FR", "ES"), ("FR", "DE"), ("DE", "PL"), ("KZ", "RU"), ("US", "CA"), ("BR", "AR"), ("IN", "PK"), ("ZA", "LS")] {
            #expect(slots[a] != slots[b], "\(a) and \(b) share a color")
        }
    }

    @Test func sortsByNameInTheUsersLanguage() {
        // Switzerland/United States in English, but Соединенные Штаты/Швейцария in Russian.
        #expect(RegionDisplay.sortedByName(["US", "CH", "AT"], locale: Locale(identifier: "en_US")) == ["AT", "CH", "US"])
        #expect(RegionDisplay.sortedByName(["US", "CH", "AT"], locale: Locale(identifier: "ru_RU")) == ["AT", "US", "CH"])
    }

    @Test func flagsAndNames() {
        #expect(RegionDisplay.flag(for: "IT") == "🇮🇹")
        #expect(RegionDisplay.flag(for: "kz") == "🇰🇿")
        #expect(!RegionDisplay.name(for: "JP").isEmpty)
    }
}
