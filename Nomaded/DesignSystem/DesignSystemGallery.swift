#if DEBUG
import SwiftUI

/// Every design-system piece on one screen, with controls to replay the animations.
/// Open it in Xcode's canvas, or launch the app with `-NomadedGallery YES`.
struct DesignSystemGallery: View {
    @State private var visited = 27
    @State private var tab = 1
    @State private var isVisited = false

    private let worldTotal = 195

    var body: some View {
        ZStack(alignment: .bottom) {
            SpaceBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text(verbatim: "Design system")
                        .font(Typography.title)

                    GallerySection(title: "Hero number + ring") {
                        HStack(spacing: 20) {
                            HeroNumber(value: visited, caption: "Countries visited")
                            WorldProgressRing(progress: Double(visited) / Double(worldTotal))
                                .frame(width: 150, height: 150)
                        }
                        .frame(maxWidth: .infinity)
                    }

                    GallerySection(title: "Stat tiles") {
                        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                            GridRow {
                                StatTile(label: "Continents", value: min(7, 1 + visited / 6), systemImage: "globe.americas.fill", detail: "of \(7)")
                                StatTile(label: "Cities", value: visited * 3, systemImage: "building.2.fill")
                            }
                        }
                    }

                    GallerySection(title: "Candy palette (visited countries)") {
                        HStack(spacing: 8) {
                            ForEach(Palette.candy.indices, id: \.self) { index in
                                VStack(spacing: 6) {
                                    Circle()
                                        .fill(Palette.candy[index])
                                        .frame(width: 40, height: 40)
                                    Text(verbatim: Palette.candyNames[index])
                                        .font(Typography.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                    }

                    GallerySection(title: "Buttons") {
                        VStack(spacing: 12) {
                            Button(isVisited ? "Visited" : "Mark as visited") {
                                withAnimation(Motion.snappy) { isVisited.toggle() }
                            }
                            .buttonStyle(.capsule(isVisited ? .inverted : .accent))
                            .sensoryFeedback(Haptics.markVisited, trigger: isVisited) { _, new in new }

                            Button(String(localized: "Close")) {}
                                .buttonStyle(.capsule(.subtle))
                        }
                    }

                    GallerySection(title: "Replay") {
                        HStack(spacing: 12) {
                            Button(verbatim: "−1") { visited = max(0, visited - 1) }
                                .buttonStyle(.capsule(.subtle))
                            Button(verbatim: "+1") { visited += 1 }
                                .buttonStyle(.capsule(.subtle))
                            Button(verbatim: "+10") { visited += 10 }
                                .buttonStyle(.capsule(.subtle))
                        }
                    }
                }
                .padding(16)
                .padding(.bottom, 96)
            }

            FloatingTabBar(
                tabs: [
                    FloatingTab(id: 0, title: "Countries", systemImage: "list.bullet"),
                    FloatingTab(id: 1, title: "Globe", systemImage: "globe.europe.africa.fill"),
                    FloatingTab(id: 2, title: "Statistics", systemImage: "chart.bar.fill"),
                ],
                selection: $tab
            )
            .padding(.bottom, 8)
        }
        .preferredColorScheme(.dark)
    }
}

private struct GallerySection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: title.uppercased())
                .font(Typography.caption)
                .foregroundStyle(.secondary)
            content
        }
    }
}

private extension Button where Label == Text {
    init(verbatim title: String, action: @escaping () -> Void) {
        self.init(action: action) { Text(verbatim: title) }
    }
}

#Preview {
    DesignSystemGallery()
}
#endif
