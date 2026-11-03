import Foundation

/// Finds countries by name while the user types. Names are matched in every language the
/// user reads (the app's language, their preferred languages and English), so "Ита",
/// "ital" and "IT" all find Italy.
struct CountrySearchIndex: Sendable {
    private struct Entry: Sendable {
        let code: String
        let foldedCode: String
        /// Folded names in all search languages.
        let names: [String]
    }

    /// Alphabetical by name in the display language.
    private let entries: [Entry]

    /// What people actually type when the system name is long or official: "США" rather than
    /// "Соединенные Штаты", "UK" rather than "United Kingdom". English and Russian.
    static let aliases: [String: [String]] = [
        "US": ["USA", "America", "United States of America", "США", "Америка", "Штаты"],
        "GB": ["UK", "Britain", "Great Britain", "England", "Scotland", "Wales", "Англия", "Британия", "Шотландия", "Уэльс"],
        "AE": ["UAE", "Emirates", "ОАЭ", "Эмираты", "Объединённые Арабские Эмираты"],
        "KR": ["Korea", "Корея", "Южная Корея"],
        "KP": ["DPRK", "Северная Корея"],
        "CZ": ["Czech Republic", "Чешская Республика"],
        "NL": ["Holland", "Голландия"],
        "TR": ["Turkey"],
        "CI": ["Ivory Coast", "Берег Слоновой Кости"],
        "SZ": ["Swaziland", "Свазиленд"],
        "CD": ["DRC", "DR Congo", "ДР Конго", "ДРК"],
        "BY": ["Belorussia", "Белоруссия"],
        "MD": ["Moldavia", "Молдавия"],
        "KG": ["Kirghizia", "Кыргызстан"],
        "TL": ["East Timor", "Восточный Тимор"],
        "RU": ["Russian Federation", "РФ"],
    ]

    init(codes: some Sequence<String>, displayLocale: Locale = .current, searchLocales: [Locale] = Self.userLocales) {
        let named = codes.map { code in
            let systemNames = ([displayLocale] + searchLocales).map { RegionDisplay.name(for: code, locale: $0) }
            let names = (systemNames + (Self.aliases[code] ?? [])).map(Self.fold)
            return (
                display: RegionDisplay.name(for: code, locale: displayLocale),
                entry: Entry(code: code, foldedCode: Self.fold(code), names: Array(Set(names)))
            )
        }
        entries = named
            .sorted { $0.display.compare($1.display, locale: displayLocale) == .orderedAscending }
            .map { $0.entry }
    }

    /// The languages the user reads, most preferred first, plus English.
    static var userLocales: [Locale] {
        (Locale.preferredLanguages + ["en"]).map(Locale.init(identifier:))
    }

    /// Every country alphabetically for an empty query, otherwise the matches, best first.
    func results(for query: String) -> [String] {
        let needle = Self.fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !needle.isEmpty else { return entries.map(\.code) }

        return entries.enumerated()
            .compactMap { position, entry in
                Self.rank(entry, needle).map { (code: entry.code, rank: $0, position: position) }
            }
            .sorted { ($0.rank, $0.position) < ($1.rank, $1.position) }
            .map { $0.code }
    }

    /// Lower is better: exact name or code, then name prefix, then a word prefix
    /// ("korea" → "South Korea"), then anywhere in the name. `nil` = no match.
    private static func rank(_ entry: Entry, _ needle: String) -> Int? {
        if entry.foldedCode == needle { return 0 }
        return entry.names.compactMap { name -> Int? in
            if name == needle { return 0 }
            if name.hasPrefix(needle) { return 1 }
            if name.split(whereSeparator: isWordSeparator).contains(where: { $0.hasPrefix(needle) }) { return 2 }
            if name.contains(needle) { return 3 }
            return nil
        }.min()
    }

    private static func isWordSeparator(_ character: Character) -> Bool {
        !character.isLetter && !character.isNumber
    }

    /// Case, accents and apostrophe style don't matter: "cote d'ivoire" finds "Côte d’Ivoire",
    /// "ё" matches "е".
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .replacingOccurrences(of: "’", with: "'")
    }
}
