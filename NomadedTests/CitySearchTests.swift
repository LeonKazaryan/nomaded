import Foundation
import Testing
@testable import Nomaded

struct CompletionPlaceTests {
    @Test(arguments: [
        ("San Antonio, TX", "United States", "San Antonio", "TX", "United States"),
        ("Sancaktepe, Istanbul, Türkiye", "", "Sancaktepe", "Istanbul", "Türkiye"),
        ("Almirante Tamandaré - PR", "Brazil", "Almirante Tamandaré", "PR", "Brazil"),
        ("Almora", "Uttarakhand, India", "Almora", "Uttarakhand", "India"),
        ("Olmaliq, Uzbekistan", "", "Olmaliq", nil, "Uzbekistan"),
        ("Almere", "Netherlands", "Almere", nil, "Netherlands"),
        ("Село Боровое", "Новосибирская область, Россия", "Боровое", "Новосибирская область", "Россия"),
        ("посёлок городского типа Боровский", "Тюменская область, Россия", "Боровский", "Тюменская область", "Россия"),
        ("Селомка", "Россия", "Селомка", nil, "Россия"),
    ] as [(String, String, String, String?, String)])
    func takesMapsWordingApart(title: String, subtitle: String, name: String, region: String?, country: String) {
        let place = CompletionPlace(title: title, subtitle: subtitle)
        #expect(place.name == name)
        #expect(place.region == region)
        #expect(place.country == country)
    }

    @Test func aNameAloneHasNoCountry() {
        #expect(CompletionPlace(title: "Almere", subtitle: "").country == nil)
    }
}

struct PlaceNamesTests {
    @Test(arguments: [
        ("Талгар", "en", "Talgar"),
        ("Шымкент", "en", "Shymkent"),
        ("Усть-Каменогорск", "en", "Ust-Kamenogorsk"),
        ("Қапшағай", "en", "Kapshagay"),
        ("Almora", "en", "Almora"),
        ("Talgar", "en", "Talgar"),
        ("Талгар", "ru", "Талгар"),
        ("Almirante Tamandaré", "ru", "Almirante Tamandaré"),
        ("北京", "ru", "Bei Jing"),
    ])
    func namesComeInLettersTheAppReads(name: String, language: String, shown: String) {
        #expect(PlaceNames.readable(name, language: language) == shown)
    }
}

@MainActor
struct CitySearchTests {
    private static func city(_ name: String, ru: String? = nil, aliases: [String] = [], region: String? = nil, _ code: String,
                             pop: Int, capital: Bool = false) -> KnownCity {
        let json = """
        {"name":"\(name)","nameRu":\(ru.map { "\"\($0)\"" } ?? "null"),"aliases":[\(aliases.map { "\"\($0)\"" }.joined(separator: ","))],\
        "region":\(region.map { "\"\($0)\"" } ?? "null"),"code":"\(code)","lat":0,"lon":0,"population":\(pop),"capital":\(capital)}
        """
        return try! JSONDecoder().decode(KnownCity.self, from: Data(json.utf8))
    }

    private let catalog = CityCatalog([
        city("Almaty", ru: "Алматы", aliases: ["Алма-Ата"], "KZ", pop: 1_209_000),
        city("Olmaliq", "UZ", pop: 121_000),
        city("Springfield", region: "Illinois", "US", pop: 117_000),
        city("Springfield", region: "Missouri", "US", pop: 160_000),
    ])
    private let countries = CountrySearchIndex(
        codes: ["KZ", "UZ", "US", "IN"],
        displayLocale: Locale(identifier: "en_US"),
        searchLocales: [Locale(identifier: "en"), Locale(identifier: "ru")]
    )

    @Test func oneCityShowsOnceWhateverMapsCallsIt() {
        let search = CitySearch(catalog: catalog, countries: countries)
        search.query = "Ol"
        search.receive([
            .init(title: "Алматы", subtitle: "Алматинская область, Казахстан"),
            .init(title: "Olmaliq, Uzbekistan", subtitle: ""),
            .init(title: "Talgar", subtitle: "Almaty Region, Kazakhstan"),
            .init(title: "Talgar", subtitle: "Almaty Region, Kazakhstan"),
            .init(title: "Almora", subtitle: "उत्तराखण्ड, Индия"),
            .init(title: "Almere", subtitle: ""),
        ])
        // Olmaliq from the list's own search, then Almaty taken over from Maps, then the
        // two only Maps has. The one without a country is left out.
        #expect(search.results.count == 4)
        #expect(search.results.suffix(2).map(\.title) == ["Talgar", "Almora"])
        // Every row: a flag, the country, nothing else from Maps' wording.
        #expect(search.results.allSatisfy { (0x1F1E6...0x1F1FF).contains($0.subtitle.unicodeScalars.first!.value) })
        #expect(search.results.allSatisfy { !$0.subtitle.contains("Region") && !$0.subtitle.contains("उत्तराखण्ड") })
    }

    @Test func aCountrysSearchKeepsToIt() {
        let search = CitySearch(countryCode: "KZ", catalog: catalog, countries: countries)
        search.query = "Tal"
        search.receive([
            .init(title: "Talgar", subtitle: "Almaty Region, Kazakhstan"),
            .init(title: "Talas", subtitle: "Kyrgyzstan"),
            .init(title: "Almora", subtitle: "Uttarakhand, India"),
        ])
        #expect(search.results.map(\.title) == ["Talgar"])
    }

    @Test func namesakesSayWhichRegionAndMapsDoesntRepeatThem() {
        let search = CitySearch(catalog: catalog, countries: countries)
        search.query = "Springfield"
        search.receive([.init(title: "Springfield, IL", subtitle: "United States")])
        #expect(search.results.count == 2)
        #expect(search.results.contains { $0.subtitle.contains("Illinois") })
        #expect(search.results.contains { $0.subtitle.contains("Missouri") })
    }
}
