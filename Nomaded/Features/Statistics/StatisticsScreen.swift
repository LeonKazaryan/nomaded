import SwiftUI

/// "My world" in numbers, over the receding globe. Cards cascade in, numbers count up,
/// continents fill country by country. Tap the top card for every country, a continent for
/// its own; pull down past the top or tap ✕ to close.
struct StatisticsScreen: View {
    /// What's open on top of the overview.
    private enum Detail: Hashable {
        case world
        case continent(Continent)
    }

    /// The top card's id for the flight into the world list.
    private static let worldHero = "world"

    let stats: WorldStats
    let visited: Set<String>
    /// `nil` while the continent maps are still being built.
    let maps: ContinentMaps?
    /// Milestones reached so far.
    let earned: [Milestone: Date]
    /// A place picked in one of the lists: the screen closes and the globe flies there.
    let onPick: (String) -> Void
    let onClose: () -> Void

    @State private var appeared = false
    @State private var pull: CGFloat = 0
    @State private var openDetail: Detail?
    @Namespace private var hero
    @ScaledMetric(relativeTo: .body) private var detailMapHeight = 230
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How far to pull past the top before letting go closes the screen.
    private static let closeDistance: CGFloat = 90

    var body: some View {
        ZStack {
            overview
                // Steps back while a list is open, the way the globe steps back for this screen.
                .opacity(openDetail == nil ? 1 : 0)
                .scaleEffect(openDetail == nil || reduceMotion ? 1 : 0.94)
                .allowsHitTesting(openDetail == nil)
                .accessibilityHidden(openDetail != nil)

            if let openDetail {
                detail(openDetail)
                    .transition(.opacity)
            }
        }
        .sensoryFeedback(Haptics.select, trigger: openDetail) { _, new in new != nil }
        #if DEBUG
        .task {
            // `-NomadedDebugContinent europe` (or `world`) opens a list once the cards are in.
            guard let raw = UserDefaults.standard.string(forKey: "NomadedDebugContinent") else { return }
            let detail: Detail? = raw == "world" ? .world : Continent(rawValue: raw).map(Detail.continent)
            try? await Task.sleep(for: .seconds(1.5))
            open(detail)
        }
        #endif
    }

    @ViewBuilder
    private func detail(_ detail: Detail) -> some View {
        switch detail {
        case .world:
            PlacesDetail(
                title: "Whole world",
                tally: nil,
                places: StatsCalculator.places(on: nil, visited: visited, catalog: .bundled),
                visited: visited,
                onPick: onPick,
                onBack: { open(nil) },
                allDiscoveredNote: "The whole world is discovered!"
            ) {
                HeroCard(stats: stats)
                    .matchedGeometryEffect(id: Self.worldHero, in: hero)
            }
        case .continent(let continent):
            let progress = stats.continents.first { $0.continent == continent }
            PlacesDetail(
                title: continent.name,
                tally: progress?.countries,
                places: StatsCalculator.places(on: continent, visited: visited, catalog: .bundled),
                visited: visited,
                onPick: onPick,
                onBack: { open(nil) },
                allDiscoveredNote: "The whole continent is discovered!"
            ) {
                ContinentMap(outlines: maps?.outlines[continent] ?? [], visited: visited, delay: reduceMotion ? 0 : 0.35)
                    .frame(height: detailMapHeight)
                    .frame(maxWidth: .infinity)
                    .matchedGeometryEffect(id: continent, in: hero)
                    .padding(16)
                    .glassCard(cornerRadius: 28)
            }
        }
    }

    private func open(_ detail: Detail?) {
        withAnimation(reduceMotion ? Motion.snappy : Motion.smooth) { openDetail = detail }
    }

    private var overview: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                    .cascade(0, appeared: appeared)
                worldCard
                    .cascade(1, appeared: appeared)
                continents
                    .cascade(2, appeared: appeared)
                AchievementsCard(earned: earned, maps: maps, baseDelay: delay(of: 3), appeared: appeared)
                    .cascade(3, appeared: appeared)
                if stats.regions.isEmpty {
                    emptyHint
                        .cascade(4, appeared: appeared)
                } else {
                    RegionsCard(regions: stats.regions, baseDelay: delay(of: 5))
                        .cascade(4, appeared: appeared)
                    FactsCard(stats: stats)
                        .cascade(5, appeared: appeared)
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
            open(.continent(progress.continent))
        } label: {
            ContinentTile(
                progress: progress,
                outlines: maps?.outlines[progress.continent],
                visited: visited,
                delay: delay(of: 2) + Double(index) * Motion.stagger * 2,
                hero: hero,
                isOpen: openDetail == .continent(progress.continent)
            )
        }
        .buttonStyle(.pressable)
        .accessibilityHint("Shows the continent's countries")
    }

    /// The headline card. Tapping it opens every country; it flies up to head that list.
    private var worldCard: some View {
        Button {
            open(.world)
        } label: {
            if openDetail == .world {
                // Keeps its place while the card is up in the list.
                HeroCard(stats: stats).hidden()
            } else {
                HeroCard(stats: stats)
                    .matchedGeometryEffect(id: Self.worldHero, in: hero)
            }
        }
        .buttonStyle(.pressable)
        .accessibilityHint("Shows all countries")
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

/// Every milestone as a medal: earned ones in their colors, the rest grey, something to aim
/// for. Earned medals pop in one after another as the card arrives.
private struct AchievementsCard: View {
    let earned: [Milestone: Date]
    let maps: ContinentMaps?
    let baseDelay: Double
    let appeared: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Achievements") {
                Text("\(earned.count) of \(Milestone.all.count)")
            }
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Array(Milestone.all.enumerated()), id: \.element.id) { index, milestone in
                        medal(milestone, index: index)
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            // Runs to the card's edges, so medals scroll out under its rim.
            .contentMargins(.horizontal, 20, for: .scrollContent)
            .padding(.horizontal, -20)
        }
        .padding(20)
        .glassCard(cornerRadius: 24)
    }

    private func medal(_ milestone: Milestone, index: Int) -> some View {
        let isEarned = earned[milestone] != nil
        let pops = isEarned && !reduceMotion
        return VStack(spacing: 6) {
            MilestoneMedal(
                milestone: milestone,
                outlines: Self.continent(milestone).flatMap { maps?.outlines[$0] },
                size: 58,
                isEarned: isEarned
            )
            .scaleEffect(appeared || !pops ? 1 : 0.4)
            .animation(Motion.bouncy.delay(baseDelay + Double(index) * Motion.stagger), value: appeared)
            Text(Self.label(milestone))
                .font(Typography.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(width: 76)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(Self.label(milestone)))
        .accessibilityValue(isEarned ? Text("Earned") : Text("Not yet"))
    }

    private static func continent(_ milestone: Milestone) -> Continent? {
        if case .continent(let continent) = milestone { continent } else { nil }
    }

    private static func label(_ milestone: Milestone) -> String {
        switch milestone {
        case .countries(let count): String(localized: "\(count) countries")
        case .continent(let continent): String(localized: continent.name)
        }
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
            if stats.cities > 0 {
                FactRow(systemImage: "building.2.fill", title: "Cities") {
                    Text(stats.cities, format: .number)
                }
            }
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
            earned: [.countries(10): .now, .continent(.europe): .now],
            onPick: { _ in },
            onClose: {}
        )
    }
    .preferredColorScheme(.dark)
}
