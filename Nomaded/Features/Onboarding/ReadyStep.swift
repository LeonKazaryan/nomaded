import SwiftUI

/// The end of onboarding: every pick lights up again in a wave across the globe, west to
/// east, while the numbers count up and three tips show how the app works. "Let's go!" hands
/// over to the globe.
struct ReadyStep: View {
    let controller: GlobeController
    /// An iPad held sideways: the summary stands left of the globe instead of under it.
    let sideBySide: Bool
    /// The globe stays above (or beside) the summary.
    @Binding var globeRoom: GlobeRoom
    let onFinish: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(WorldStore.self) private var world
    @State private var appeared = false
    @State private var cheers = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var ringSize = 108

    var body: some View {
        Group {
            if sideBySide {
                SideColumn(globeRoom: $globeRoom) { content }
            } else {
                content
                    .centered(maxWidth: Metrics.panelWidth)
                    .onScreenEdge(.top) { globeRoom.bottom = $0 }
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
        }
        .sensoryFeedback(Haptics.markVisited, trigger: cheers)
        .onAppear(perform: play)
    }

    private var content: some View {
        let stats = StatsCalculator.stats(visited: world.visitedCodes, catalog: .bundled)
        return VStack(spacing: 14) {
            Text("Your world")
                .font(Typography.largeTitle)
                .cascade(0, appeared: appeared)

            if world.visitedCodes.isEmpty {
                Text("Your map is empty, for now")
                    .font(Typography.body)
                    .foregroundStyle(.secondary)
                    .cascade(1, appeared: appeared)
            } else {
                summary(stats)
                    .cascade(1, appeared: appeared)
            }

            tips
                .cascade(2, appeared: appeared)

            Button(action: onFinish) {
                Text("Let's go!")
            }
            .buttonStyle(.capsule(.accent))
            .cascade(3, appeared: appeared)
        }
    }

    private func summary(_ stats: WorldStats) -> some View {
        // With the largest text the numbers go under the ring, where they have the width.
        (dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 18))) {
            WorldProgressRing(progress: stats.countries.share)
                .frame(width: ringSize, height: ringSize)
            VStack(alignment: .leading, spacing: 6) {
                HeroNumber(value: stats.countries.visited, caption: "of \(stats.countries.total) countries")
                Text("\(stats.visitedContinents) of \(stats.continents.count) continents")
                    .font(Typography.label)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(18)
        .glassCard(cornerRadius: 28)
    }

    private var tips: some View {
        VStack(alignment: .leading, spacing: 14) {
            tip("hand.tap.fill", "Tap a country to mark it")
            tip("magnifyingglass", "Find countries and cities")
            tip("medal.fill", "Collect medals as you go")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glassCard(cornerRadius: 24)
    }

    private func tip(_ systemImage: String, _ text: LocalizedStringKey) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(Typography.headline)
                .foregroundStyle(Palette.accentLight)
                .frame(width: 28)
                .accessibilityHidden(true)
            Text(text)
                .font(Typography.body)
        }
    }

    private func play() {
        appeared = true
        cheers += 1
        guard !reduceMotion, let world = controller.world else { return }
        // West to east, the whole set inside about a second and a half.
        let labels = Dictionary(world.countries.map { ($0.code, $0.label.longitude) }, uniquingKeysWith: { first, _ in first })
        let codes = self.world.visitedCodes.sorted { (labels[$0] ?? 0) < (labels[$1] ?? 0) }
        let step = min(0.08, 1.4 / Double(max(codes.count, 1)))
        Task {
            try? await Task.sleep(for: .seconds(0.4))
            for code in codes {
                controller.celebrate(code, quietly: true)
                try? await Task.sleep(for: .seconds(step))
            }
        }
    }
}

private extension View {
    /// Rises into place after the parts above it.
    func cascade(_ index: Int, appeared: Bool) -> some View {
        modifier(ReadyCascade(index: index, appeared: appeared))
    }
}

private struct ReadyCascade: ViewModifier {
    let index: Int
    let appeared: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 40)
            .animation(reduceMotion ? Motion.smooth : Motion.bouncy.delay(0.15 + Double(index) * Motion.stagger * 2), value: appeared)
    }
}
