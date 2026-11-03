import Foundation

/// Something worth a big celebration, earned once and kept even if a mark is taken back.
enum Milestone: Hashable, Sendable {
    /// Reached this many of the 195 countries.
    case countries(Int)
    /// First place on a continent, territories included (Greenland opens North America).
    case continent(Continent)

    static let countryThresholds = [10, 25, 50, 100, 150, 195]

    /// Every milestone there is, in the order the statistics list them.
    static let all: [Milestone] = countryThresholds.map(Milestone.countries) + Continent.allCases.map(Milestone.continent)

    /// How it's stored.
    var id: String {
        switch self {
        case .countries(let count): "countries.\(count)"
        case .continent(let continent): "continent.\(continent.rawValue)"
        }
    }

    init?(id: String) {
        let parts = id.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        switch parts[0] {
        case "countries":
            guard let count = Int(parts[1]), Self.countryThresholds.contains(count) else { return nil }
            self = .countries(count)
        case "continent":
            guard let continent = Continent(rawValue: parts[1]) else { return nil }
            self = .continent(continent)
        default:
            return nil
        }
    }

    /// The country threshold after this one, if any.
    var nextCountryThreshold: Int? {
        guard case .countries(let count) = self else { return nil }
        return Self.countryThresholds.first { $0 > count }
    }
}

enum MilestoneRules {
    /// Every milestone the visited places reach. Countries count the 195 only, the way the
    /// counter and the statistics do; continents count any place on them.
    static func reached(visited: Set<String>, catalog: CountryCatalog) -> Set<Milestone> {
        let places = catalog.split(visited)
        var reached = Set(Milestone.countryThresholds.filter { places.countries.count >= $0 }.map(Milestone.countries))
        for code in visited {
            if let continent = catalog[code]?.continent { reached.insert(.continent(continent)) }
        }
        return reached
    }

    /// The order to celebrate several at once: continents first, then the biggest count last,
    /// so the evening ends on the headline.
    static func celebrationOrder(_ milestones: some Sequence<Milestone>) -> [Milestone] {
        milestones.sorted { a, b in
            switch (a, b) {
            case (.continent(let x), .continent(let y)):
                Continent.allCases.firstIndex(of: x)! < Continent.allCases.firstIndex(of: y)!
            case (.continent, .countries): true
            case (.countries, .continent): false
            case (.countries(let x), .countries(let y)): x < y
            }
        }
    }
}
