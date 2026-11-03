import SwiftUI

/// "My world" in numbers, over the receding globe. Cards cascade in, numbers count up,
/// continents fill country by country. Tap a continent to see its countries, pull down past
/// the top or tap ✕ to close.
struct StatisticsScreen: View {
    let stats: WorldStats
    let visited: Set<String>
    /// `nil` while the continent maps are still being built.
    let maps: ContinentMaps?
    /// A country picked in a continent's list: the screen closes and the globe flies there.
    let onPick: (String) -> Void
    let onClose: () -> Void

    @State private var appeared = false
    @State private var pull: CGFloat = 0
    @State private var openContinent: Continent?
    @Namespace private var hero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How far to pull past the top before letting go closes the screen.
    private static let closeDistance: CGFloat = 90

    var body: some View {
        ZStack {
            overview
                // Steps back while a continent is open, the way the globe steps back for this screen.
                .opacity(openContinent == nil ? 1 : 0)
                .scaleEffect(openContinent == nil || reduceMotion ? 1 : 0.94)
                .allowsHitTesting(openContinent == nil)
                .accessibilityHidden(openContinent != nil)

            if let openContinent, let progress = stats.continents.first(where: { $0.continent == openContinent }) {
                ContinentDetail(
                    progress: progress,
                    places: StatsCalculator.places(on: openContinent, visited: visited, catalog: .bundled),
                    outlines: maps?.outlines[openContinent],
                    visited: visited,
                    hero: hero,
                    onPick: onPick,
                    onBack: { open(nil) }
                )
                .transition(.opacity)
            }
        }
        .sensoryFeedback(Haptics.select, trigger: openContinent) { _, new in new != nil }
        #if DEBUG
        .task {
            // `-NomadedDebugContinent europe` opens a continent once the cards are in.
            guard let raw = UserDefaults.standard.string(forKey: "NomadedDebugContinent"),
                  let continent = Continent(rawValue: raw)
            else { return }
            try? await Task.sleep(for: .seconds(1.5))
            open(continent)
        }
        #endif
    }

    private func open(_ continent: Continent?) {
        withAnimation(reduceMotion ? Motion.snappy : Motion.smooth) { openContinent = continent }
    }

    private var overview: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                    .cascade(0, appeared: appeared)
                HeroCard(stats: stats)
                    .cascade(1, appeared: appeared)
                continents
                    .cascade(2, appeared: appeared)
                if stats.regions.isEmpty {
                    emptyHint
                        .cascade(3, appeared: appeared)
                } else {
                    RegionsCard(regions: stats.regions, baseDelay: delay(of: 4))
                        .cascade(3, appeared: appeared)
                    FactsCard(stats: stats)
                        .cascade(4, appeared: appeared)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            // Stretches a little while pulled, like a sheet that's about to let go.
            .scaleEffect(1 - min(pull, 200) / 2400, anchor: .top)
        }
        .scrollIndicators(.hidden)
        .fadingUnderStatusBar()
        .pullToClose($pull, distance: Self.closeDistance, onClose: onClose)
        .onAppear { appeared = true }
    }

    private var header: some View {
        HStack {
            Text("Statistics")
                .font(Typography.largeTitle)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(Typography.headline)
                    .frame(width: 44, height: 44)
                    .glass(Circle())
                    // Turns as you pull, a hint that letting go will close.
                    .rotationEffect(.degrees(Double(min(pull, Self.closeDistance)) / Double(Self.closeDistance) * 90))
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Close")
        }
        .padding(.top, 8)
    }

    private var continents: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Continents") {
                Text("\(stats.visitedContinents) of \(stats.continents.count)")
            }
            let tiles = stats.continents.filter { $0.continent != .antarctica }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(Array(tiles.enumerated()), id: \.element.id) { index, progress in
                    tile(progress, index: index)
                }
            }
            // Antarctica gets a row of its own: it's round, and it has no countries to count.
            if let antarctica = stats.continents.first(where: { $0.continent == .antarctica }) {
                tile(antarctica, index: tiles.count)
            }
        }
    }

    private func tile(_ progress: WorldStats.ContinentProgress, index: Int) -> some View {
        Button {
            open(progress.continent)
        } label: {
            ContinentTile(
                progress: progress,
                outlines: maps?.outlines[progress.continent],
                visited: visited,
                delay: delay(of: 2) + Double(index) * Motion.stagger * 2,
                hero: hero,
                isOpen: openContinent == progress.continent
            )
        }
        .buttonStyle(.pressable)
        .accessibilityHint("Shows the continent's countries")
    }

    private var emptyHint: some View {
        Text("Mark your first country and this page comes alive")
            .font(Typography.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(20)
            .glassCard(cornerRadius: 24)
    }

    /// When a card's own animations start: after it has slid in.
    private func delay(of index: Int) -> Double {
        reduceMotion ? 0 : 0.15 + Double(index) * Motion.stagger
    }
}

// MARK: - Cards

/// The headline: share of the world on a ring, the country count beside it.
private struct HeroCard: View {
    let stats: WorldStats
    @ScaledMetric(relativeTo: .largeTitle) private var ringSize = 132

    var body: some View {
        HStack(spacing: 20) {
            WorldProgressRing(progress: stats.countries.share)
                .frame(width: ringSize, height: ringSize)
            VStack(alignment: .leading, spacing: 6) {
                HeroNumber(value: stats.countries.visited, caption: "of \(stats.countries.total) countries")
                if stats.territories > 0 {
                    Text("+\(stats.territories) territories")
                        .font(Typography.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(20)
        .glassCard(cornerRadius: 28)
    }
}

/// UN regions you've started, most complete first, each with a meter that fills in turn.
private struct RegionsCard: View {
    let regions: [WorldStats.RegionProgress]
    let baseDelay: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Regions") { EmptyView() }
            ForEach(Array(regions.enumerated()), id: \.element.id) { index, region in
                let delay = baseDelay + Double(index) * Motion.stagger
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(region.subregion.name)
                            .font(Typography.body)
                        Spacer()
                        Text("\(region.countries.visited) of \(region.countries.total)")
                            .font(Typography.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Meter(share: region.countries.share, delay: delay)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(20)
        .glassCard(cornerRadius: 24)
    }
}

private struct FactsCard: View {
    let stats: WorldStats

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Facts") { EmptyView() }
            FactRow(systemImage: "mountain.2.fill", title: "Land") {
                Text("\(stats.landShare.formatted(.percent.precision(.significantDigits(1...2)))) of all land")
            }
            if let largest = stats.largest {
                FactRow(systemImage: "arrow.up.left.and.arrow.down.right", title: "Largest") { place(largest) }
            }
            if let smallest = stats.smallest, smallest != stats.largest {
                FactRow(systemImage: "smallcircle.filled.circle", title: "Smallest") { place(smallest) }
            }
        }
        .padding(20)
        .glassCard(cornerRadius: 24)
    }

    private func place(_ code: String) -> Text {
        Text(verbatim: "\(RegionDisplay.flag(for: code)) \(RegionDisplay.name(for: code))")
    }
}

private struct FactRow<Value: View>: View {
    let systemImage: String
    let title: LocalizedStringKey
    @ViewBuilder var value: Value

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(Palette.accentLight)
                .frame(width: 28)
                .accessibilityHidden(true)
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            value
                .multilineTextAlignment(.trailing)
        }
        .font(Typography.body)
        .accessibilityElement(children: .combine)
    }
}

private struct SectionHeader<Trailing: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(Typography.headline)
            Spacer()
            trailing
                .font(Typography.label)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Motion

private extension View {
    /// Slides up into place after the cards above it, then shrinks and fades a little as
    /// it scrolls past the edges.
    func cascade(_ index: Int, appeared: Bool) -> some View {
        modifier(Cascade(index: index, appeared: appeared))
    }
}

private struct Cascade: ViewModifier {
    let index: Int
    let appeared: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let reduceMotion = reduceMotion
        return content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 60)
            .scaleEffect(appeared || reduceMotion ? 1 : 0.94)
            .animation(reduceMotion ? Motion.smooth : Motion.bouncy.delay(Double(index) * Motion.stagger), value: appeared)
            .scrollTransition { content, phase in
                content
                    .scaleEffect(phase.isIdentity || reduceMotion ? 1 : 0.94)
                    .opacity(phase.isIdentity ? 1 : 0.6)
            }
    }
}

#Preview {
    let catalog = CountryCatalog.bundled
    let visited: Set<String> = ["IT", "FR", "DE", "ES", "PT", "JP", "US", "KZ", "GE", "TR", "GL"]
    ZStack {
        SpaceBackground()
        StatisticsScreen(
            stats: StatsCalculator.stats(visited: visited, catalog: catalog),
            visited: visited,
            maps: nil,
            onPick: { _ in },
            onClose: {}
        )
    }
    .preferredColorScheme(.dark)
}
