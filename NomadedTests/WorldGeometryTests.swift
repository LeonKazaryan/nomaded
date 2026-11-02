import Testing
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
    ])
    func hitTestFindsCountry(_ place: Place) async throws {
        let tester = GlobeHitTester(world: try await WorldGeometry.loadBundled())
        let coordinate = GeoCoordinate(latitude: place.latitude, longitude: place.longitude)
        #expect(tester.country(at: coordinate, tolerance: 0.01) == place.expected)
    }

    @Test func neighboursNeverShareAColor() async throws {
        let world = try await WorldGeometry.loadBundled()
        let slots = Dictionary(uniqueKeysWithValues: world.countries.filter { !$0.code.isEmpty }.map { ($0.code, $0.colorSlot) })
        for (a, b) in [("FR", "ES"), ("FR", "DE"), ("DE", "PL"), ("KZ", "RU"), ("US", "CA"), ("BR", "AR"), ("IN", "PK"), ("ZA", "LS")] {
            #expect(slots[a] != slots[b], "\(a) and \(b) share a color")
        }
    }

    @Test func flagsAndNames() {
        #expect(RegionDisplay.flag(for: "IT") == "🇮🇹")
        #expect(RegionDisplay.flag(for: "kz") == "🇰🇿")
        #expect(!RegionDisplay.name(for: "JP").isEmpty)
    }
}
