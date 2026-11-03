import SwiftUI

/// A list inside the statistics, for one continent or the whole world: the countries you've
/// been to (Nomaded) and the ones still waiting (Undiscovered), territories under their own
/// heading in each. Its top card flies up from the overview. Tapping a place closes the
/// statistics and flies the globe there, ready to be marked.
struct PlacesDetail<Hero: View>: View {
    enum Segment: Hashable {
        case discovered, undiscovered
    }

    let title: LocalizedStringResource
    /// Shown under the title with a meter. `nil` when the top card already says it.
    let tally: WorldStats.Tally?
    let places: PlaceLists
    let visited: Set<String>
    let onPick: (String) -> Void
    let onBack: () -> Void
    /// Shown in Undiscovered once nothing is left there.
    let allDiscoveredNote: LocalizedStringKey
    /// The card that flew up from the overview: a continent's map, or the world's ring.
    let hero: Hero

    @State private var segment: Segment
    @State private var pull: CGFloat = 0
    @ScaledMetric(relativeTo: .body) private var rowHeight = 56
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        title: LocalizedStringResource,
        tally: WorldStats.Tally?,
        places: PlaceLists,
        visited: Set<String>,
        onPick: @escaping (String) -> Void,
        onBack: @escaping () -> Void,
        allDiscoveredNote: LocalizedStringKey,
        @ViewBuilder hero: () -> Hero
    ) {
        self.title = title
        self.tally = tally
        self.places = places
        self.visited = visited
        self.onPick = onPick
        self.onBack = onBack
        self.allDiscoveredNote = allDiscoveredNote
        self.hero = hero()
        // Open on what's there: your places if you have some, otherwise what's waiting.
        let hasDiscovered = !places.discovered.isEmpty || !places.discoveredTerritories.isEmpty
        _segment = State(initialValue: hasDiscovered ? .discovered : .undiscovered)
    }

    /// Antarctica has no countries, only the territory itself: one list, no picker.
    private var hasCountries: Bool { !places.discovered.isEmpty || !places.undiscovered.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                hero

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
                Text(title)
                    .font(Typography.largeTitle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let tally, tally.total > 0 {
                    HStack(spacing: 8) {
                        Text("\(tally.visited) of \(tally.total)")
                            .font(Typography.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Meter(share: tally.share, delay: reduceMotion ? 0 : 0.3)
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
                emptyNote(allDiscoveredNote)
            } else {
                placeList(countries: places.undiscovered, territories: places.undiscoveredTerritories, marksVisited: false)
            }
        }
    }

    private func placeList(countries: [String], territories: [String], marksVisited: Bool) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(countries, id: \.self) { row($0, marksVisited: marksVisited) }
            if !territories.isEmpty {
                // Territories don't count toward the picker's numbers, so they carry their own.
                HStack(spacing: 6) {
                    Text("Territories")
                    Text(territories.count, format: .number)
                        .monospacedDigit()
                        .opacity(0.7)
                }
                .font(Typography.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 18)
                .padding(.top, countries.isEmpty ? 6 : 14)
                .padding(.bottom, 2)
                .accessibilityElement(children: .combine)
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
