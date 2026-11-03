import SwiftUI

/// One continent up close: its map flies up from the tile, then the countries you've been
/// to (Nomaded) and the ones still waiting (Undiscovered). Tapping a country closes the
/// statistics and flies the globe there, ready to be marked.
struct ContinentDetail: View {
    enum Segment: Hashable {
        case discovered, undiscovered
    }

    let progress: WorldStats.ContinentProgress
    let places: ContinentPlaces
    /// `nil` while the maps are still being built.
    let outlines: [ContinentMaps.Outline]?
    let visited: Set<String>
    /// Shared with the tiles, so the map flies between them.
    let hero: Namespace.ID
    let onPick: (String) -> Void
    let onBack: () -> Void

    @State private var segment: Segment
    @State private var pull: CGFloat = 0
    @ScaledMetric(relativeTo: .body) private var mapHeight = 230
    @ScaledMetric(relativeTo: .body) private var rowHeight = 56
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        progress: WorldStats.ContinentProgress,
        places: ContinentPlaces,
        outlines: [ContinentMaps.Outline]?,
        visited: Set<String>,
        hero: Namespace.ID,
        onPick: @escaping (String) -> Void,
        onBack: @escaping () -> Void
    ) {
        self.progress = progress
        self.places = places
        self.outlines = outlines
        self.visited = visited
        self.hero = hero
        self.onPick = onPick
        self.onBack = onBack
        // Open on what's there: your countries if you have some, otherwise what's waiting.
        let hasDiscovered = !places.discovered.isEmpty || !places.discoveredTerritories.isEmpty
        _segment = State(initialValue: hasDiscovered ? .discovered : .undiscovered)
    }

    /// Antarctica has no countries, only the territory itself: one list, no picker.
    private var hasCountries: Bool { progress.countries.total > 0 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                ContinentMap(outlines: outlines ?? [], visited: visited, delay: reduceMotion ? 0 : 0.35)
                    .frame(height: mapHeight)
                    .frame(maxWidth: .infinity)
                    .matchedGeometryEffect(id: progress.continent, in: hero)
                    .padding(16)
                    .glassCard(cornerRadius: 28)

                if hasCountries {
                    PillPicker(
                        options: [
                            .init(id: .discovered, title: "Nomaded", count: places.discovered.count),
                            .init(id: .undiscovered, title: "Undiscovered", count: places.undiscovered.count),
                        ],
                        selection: $segment
                    )
                    list(for: segment)
                        .id(segment)
                        .transition(reduceMotion ? AnyTransition.opacity : AnyTransition(.blurReplace))
                } else {
                    placeList(
                        countries: [],
                        territories: places.discoveredTerritories + places.undiscoveredTerritories,
                        marksVisited: true
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .fadingUnderStatusBar()
        .pullToClose($pull, onClose: onBack)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(Typography.headline)
                    .frame(width: 44, height: 44)
                    .glass(Circle())
                    // Turns to point down as you pull, a hint that letting go goes back.
                    .rotationEffect(.degrees(-90 * Double(min(pull, 90)) / 90))
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Back")

            VStack(alignment: .leading, spacing: 4) {
                Text(progress.continent.name)
                    .font(Typography.largeTitle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if hasCountries {
                    HStack(spacing: 8) {
                        Text("\(progress.countries.visited) of \(progress.countries.total)")
                            .font(Typography.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Meter(share: progress.countries.share, delay: reduceMotion ? 0 : 0.3)
                    }
                }
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private func list(for segment: Segment) -> some View {
        switch segment {
        case .discovered:
            if places.discovered.isEmpty, places.discoveredTerritories.isEmpty {
                emptyNote("None yet. Time to go!")
            } else {
                placeList(countries: places.discovered, territories: places.discoveredTerritories, marksVisited: false)
            }
        case .undiscovered:
            if places.undiscovered.isEmpty, places.undiscoveredTerritories.isEmpty {
                emptyNote("The whole continent is discovered!")
            } else {
                placeList(countries: places.undiscovered, territories: places.undiscoveredTerritories, marksVisited: false)
            }
        }
    }

    private func placeList(countries: [String], territories: [String], marksVisited: Bool) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(countries, id: \.self) { row($0, marksVisited: marksVisited) }
            if !territories.isEmpty {
                Text("Territories")
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 18)
                    .padding(.top, countries.isEmpty ? 6 : 14)
                    .padding(.bottom, 2)
                    .accessibilityAddTraits(.isHeader)
                ForEach(territories, id: \.self) { row($0, marksVisited: marksVisited) }
            }
        }
        .padding(.vertical, 6)
        .glassCard(cornerRadius: 24)
    }

    private func row(_ code: String, marksVisited: Bool) -> some View {
        Button {
            onPick(code)
        } label: {
            CountryRow(code: code, isMarked: marksVisited && visited.contains(code))
                .frame(minHeight: rowHeight)
        }
        .buttonStyle(.pressable)
    }

    private func emptyNote(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(Typography.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: rowHeight)
            .padding(.vertical, 8)
            .glassCard(cornerRadius: 24)
    }
}
