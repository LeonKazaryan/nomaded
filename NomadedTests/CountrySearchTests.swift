import Foundation
import Testing
@testable import Nomaded

struct CountrySearchTests {
    private let index = CountrySearchIndex(
        codes: ["IT", "IS", "IN", "DE", "DK", "KR", "KP", "CI", "CW", "US", "ZA", "KZ"],
        displayLocale: Locale(identifier: "en_US"),
        searchLocales: [Locale(identifier: "en"), Locale(identifier: "ru")]
    )

    @Test func emptyQueryListsEverythingAlphabetically() {
        let english = Locale(identifier: "en_US")
        let names = index.results(for: "  ").map { RegionDisplay.name(for: $0, locale: english) }
        #expect(names.count == 12)
        #expect(names == names.sorted { $0.compare($1, locale: english) == .orderedAscending })
    }

    @Test func prefixFindsTheCountryFirst() {
        #expect(index.results(for: "ital").first == "IT")
        #expect(index.results(for: "Kaz") == ["KZ"])
    }

    @Test func otherLanguagesMatchToo() {
        #expect(index.results(for: "Ита") == ["IT"])
        #expect(index.results(for: "казахстан") == ["KZ"])
    }

    @Test func exactCodeBeatsNamePrefix() {
        // "de" is Germany's code and also the start of "Denmark".
        #expect(index.results(for: "de").prefix(2) == ["DE", "DK"])
    }

    @Test func wordPrefixFindsLaterWords() {
        #expect(Set(index.results(for: "korea")) == ["KR", "KP"])
        #expect(index.results(for: "afr") == ["ZA"])
    }

    @Test func accentsAndApostrophesDontMatter() {
        #expect(index.results(for: "cote d'ivoire") == ["CI"])
        #expect(index.results(for: "curacao") == ["CW"])
    }

    @Test func noMatchIsEmpty() {
        #expect(index.results(for: "zzzz").isEmpty)
    }
}
