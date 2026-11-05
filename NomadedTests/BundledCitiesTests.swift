import Foundation
import Testing
@testable import Nomaded

struct CityKeyTests {
    @Test(arguments: [
        ("Шымкент", "Shymkent"),
        ("Шейх", "Sheikh"),
        ("Боровое", "Borovoe"),
        ("Алма-Ата", "Alma Ata"),
        ("Юрмала", "Jurmala"),
        ("Цахкадзор", "Tsakhkadzor"),
        ("São Paulo", "Sao Paulo"),
        ("L'Aquila", "Laquila"),
    ])
    func spellingsMeet(_ a: String, _ b: String) {
        #expect(CityKey.key(a) == CityKey.key(b))
    }

    @Test func wordsKeepTheirOrder() {
        #expect(CityKey.words("Sharm el-Sheikh") == ["sarm", "el", "seih"])
        #expect(CityKey.words("  ").isEmpty)
    }
}

struct CityTableTests {
    @Test func whatGoesInComesBack() throws {
        let rows = [
            CityTable.Row(name: "Almaty", nameRu: "Алматы", aliases: ["Алма-Ата"], region: .init(name: "Almaty", nameRu: "Алматы"),
                          countryCode: "KZ", latitude: 43.25, longitude: 76.95, population: 1_977_011, isCapital: false, fame: 51),
            CityTable.Row(name: "Astana", nameRu: "Астана", aliases: [], region: nil,
                          countryCode: "KZ", latitude: 51.18, longitude: 71.45, population: 1_544_142, isCapital: true),
            CityTable.Row(name: "Yerevan", nameRu: nil, aliases: [], region: nil,
                          countryCode: "AM", latitude: 40.18, longitude: 44.51, population: 1_093_485, isCapital: true),
        ]
        let table = try CityTable(compressed: CityTable.encode(rows))
        #expect(table.count == 3)
        // By country, the capital first.
        #expect(table.countries["KZ"].map { $0.map(table.name) } == ["Astana", "Almaty"])
        let almaty = try #require(table.countries["KZ"]?.last)
        #expect(table.nameRu(almaty) == "Алматы")
        #expect(table.region(almaty) == .init(name: "Almaty", nameRu: "Алматы"))
        #expect(abs(table.latitude(almaty) - 43.25) < 0.0001)
        #expect(table.population(almaty) == 1_977_011)
        #expect(table.fame(almaty) == 51)
        #expect(!table.isCapital(almaty))
        #expect(table.countryCode(almaty) == "KZ")
        let yerevan = try #require(table.countries["AM"]?.first)
        #expect(table.nameRu(yerevan) == nil)
        #expect(table.isCapital(yerevan))
        // The old name finds it too.
        let key = Array(CityKey.key("Алма-Ата").utf8)
        #expect(table.entries(withPrefix: key).map { table.entry($0).city } == [almaty])
    }
}

/// The real list: ~80,000 places from GeoNames.
struct BundledCitiesTests {
    private let catalog: CityCatalog

    init() throws {
        catalog = try CityCatalog.loadBundled()
    }

    @Test(arguments: [
        ("Боровое", "KZ"), ("Бурабай", "KZ"), ("borovoe", "KZ"),
        ("Шарм-эль-Шейх", "EG"), ("Sharm el Sheikh", "EG"), ("шарм эль шейх", "EG"),
        ("Цахкадзор", "AM"), ("Джермук", "AM"), ("Дилижан", "AM"),
        ("Позитано", "IT"), ("Amalfi", "IT"), ("Куршевель", "FR"), ("Сигнахи", "GE"),
        ("Нур-Султан", "KZ"), ("Ленинакан", "AM"), ("Алма-Ата", "KZ"),
        // One slip of the finger.
        ("Боравое", "KZ"), ("Дилижн", "AM"),
    ])
    func resortsAndOldNamesAreFound(_ query: String, _ country: String) {
        #expect(catalog.search(query).first?.countryCode == country, "\(query)")
    }

    @Test func smallCountriesHaveTheirTowns() {
        #expect(catalog.cityCount(in: "AM") > 150)
        #expect(catalog.cities(in: "AM").first?.name == "Yerevan")
        #expect(catalog.cityCount(in: "GE") > 60)
    }

    /// No two rows for one place, in any search.
    @Test(arguments: ["Рим", "Rome", "Кемер", "Алматы", "Springfield", "Paris", "Москва", "Батуми", "San", "Новый", "Kansas City"])
    func eachPlaceOnce(_ query: String) {
        let results = catalog.search(query, limit: 30)
        for (i, a) in results.enumerated() {
            for b in results.dropFirst(i + 1) where a.countryCode == b.countryCode && CityKey.key(a.name) == CityKey.key(b.name) {
                let km = CityMath.distanceKm(a.latitude, a.longitude, b.latitude, b.longitude)
                #expect(km > CityCatalogBuilderLimits.duplicateKm || a.region != b.region, "\(a.name), \(a.countryCode) twice")
            }
        }
    }

    @Test func russianNamesForTheFamousOnes() {
        for name in ["Rome", "Paris", "Kyiv", "Tbilisi", "Yerevan", "Sharm el Sheikh", "Positano"] {
            #expect(catalog.search(name).first?.nameRu != nil, "\(name)")
        }
    }

    /// Fast enough to search on every keystroke, for every prefix of a long name.
    @Test func searchingIsInstant() {
        let queries = ["a", "al", "alm", "alma", "almat", "almaty", "ш", "ша", "шар", "шарм", "s", "sa", "san", "sant", "santa"]
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            for _ in 0..<4 {
                for query in queries { _ = catalog.search(query, limit: 10) }
            }
        }
        #expect(elapsed < .milliseconds(600), "60 searches took \(elapsed)")
    }

    @Test func opensQuickly() throws {
        let clock = ContinuousClock()
        let elapsed = try clock.measure { _ = try CityCatalog.loadBundled() }
        #expect(elapsed < .milliseconds(500), "opening took \(elapsed)")
    }
}

/// Mirrors `CityCatalogBuilder.duplicateKm` in the geo pipeline.
private enum CityCatalogBuilderLimits {
    static let duplicateKm = 15.0
}
