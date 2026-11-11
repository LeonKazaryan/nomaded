import SwiftUI

/// The world in one card: the share of it on a ring, the countries counting up, the
/// continents. The end of onboarding shows it, and so does the desk globe's plaque.
struct WorldSummaryCard: View {
    let stats: WorldStats

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var ringSize = 108

    var body: some View {
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
}

/// iPhone Duo stood half open on a table, like a laptop: the globe turns slowly on the upper
/// half like a desk globe, and the lower half is its stand, with the plaque that says how
/// much of the world is yours. Tapping it opens the statistics.
struct DeskPlaque: View {
    let stats: WorldStats
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            WorldSummaryCard(stats: stats)
                .contentShape(.hoverEffect, RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .buttonStyle(.pressable)
        .accessibilityHint("Opens the statistics")
    }
}
