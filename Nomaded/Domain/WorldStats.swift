import Foundation

/// Everything the statistics screen shows. Never stored: always calculated from the
/// visited places, so it can't drift from them.
struct WorldStats: Equatable, Sendable {
    struct Tally: Equatable, Sendable {
        var visited: Int
        var total: Int

        /// 0…1.
        var share: Double { total > 0 ? Double(visited) / Double(total) : 0 }
    }

    struct ContinentProgress: Equatable, Sendable, Identifiable {
        let continent: Continent
        /// Of the 195 countries only. Antarctica has none.
        let countries: Tally
        /// Any visited place counts here, territories and Antarctica included.
        let isVisited: Bool

        var id: Continent { continent }
    }

    struct RegionProgress: Equatable, Sendable, Identifiable {
        let subregion: Subregion
        let countries: Tally

        var id: Subregion { subregion }
    }

    /// Of the 195.
    let countries: Tally
    /// Visited places outside the 195: Greenland, Puerto Rico, Hong Kong…
    let territories: Int
    /// All seven, in display order.
    let continents: [ContinentProgress]
    /// Regions with at least one visited country, most complete first.
    let regions: [RegionProgress]
    /// Visited area over all land on the globe, Antarctica included. 0…1.
    let landShare: Double
    /// Biggest and smallest visited place by area. `nil` with nothing visited.
    let largest: String?
    let smallest: String?

    var visitedContinents: Int { continents.filter(\.isVisited).count }
}

enum StatsCalculator {
    static func stats(visited: Set<String>, catalog: CountryCatalog) -> WorldStats {
        let places = visited.compactMap { catalog[$0] }
        let all = catalog.countries
        let sovereign = all.filter(\.isSovereign)

        func tally(_ scope: [Country]) -> WorldStats.Tally {
            WorldStats.Tally(visited: scope.filter { visited.contains($0.code) }.count, total: scope.count)
        }

        let continents = Continent.allCases.map { continent in
            WorldStats.ContinentProgress(
                continent: continent,
                countries: tally(sovereign.filter { $0.continent == continent }),
                isVisited: places.contains { $0.continent == continent }
            )
        }

        let regions = Dictionary(grouping: sovereign, by: \.subregion)
            .map { WorldStats.RegionProgress(subregion: $0.key, countries: tally($0.value)) }
            .filter { $0.countries.visited > 0 }
            .sorted { a, b in
                if a.countries.share != b.countries.share { return a.countries.share > b.countries.share }
                if a.countries.visited != b.countries.visited { return a.countries.visited > b.countries.visited }
                return a.subregion.rawValue < b.subregion.rawValue
            }

        let totalArea = all.reduce(0) { $0 + $1.areaKm2 }
        let visitedArea = places.reduce(0) { $0 + $1.areaKm2 }
        let bySize = places.sorted { ($0.areaKm2, $0.code) < ($1.areaKm2, $1.code) }

        return WorldStats(
            countries: tally(sovereign),
            territories: places.filter { !$0.isSovereign }.count,
            continents: continents,
            regions: regions,
            landShare: totalArea > 0 ? visitedArea / totalArea : 0,
            largest: bySize.last?.code,
            smallest: bySize.first?.code
        )
    }
}
