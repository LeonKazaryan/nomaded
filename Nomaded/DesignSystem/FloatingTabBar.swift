import SwiftUI

struct FloatingTab<ID: Hashable>: Identifiable {
    let id: ID
    let title: LocalizedStringKey
    let systemImage: String
}

/// The floating "pill" navigation that sits over the globe instead of a standard tab bar.
/// The selected tab grows to show its title; the highlight slides between tabs.
struct FloatingTabBar<ID: Hashable>: View {
    let tabs: [FloatingTab<ID>]
    @Binding var selection: ID

    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tabs) { tab in
                let isSelected = tab.id == selection
                Button {
                    withAnimation(Motion.bouncy) { selection = tab.id }
                } label: {
                    HStack(spacing: 6) {
                        TabIcon(systemImage: tab.systemImage, isSelected: isSelected)
                        if isSelected {
                            Text(tab.title)
                                .lineLimit(1)
                                .transition(.opacity.combined(with: .scale(scale: 0.6, anchor: .leading)))
                        }
                    }
                    .font(Typography.headline)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                    .padding(.horizontal, isSelected ? 18 : 14)
                    .frame(minWidth: 52, minHeight: 48)
                    .background {
                        if isSelected {
                            Capsule()
                                .fill(Palette.accent)
                                .matchedGeometryEffect(id: "highlight", in: highlight)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(Text(tab.title))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(5)
        .glass(Capsule())
        .sensoryFeedback(Haptics.select, trigger: selection)
    }
}

/// Bounces only when its tab becomes selected, not when it's deselected.
private struct TabIcon: View {
    let systemImage: String
    let isSelected: Bool
    @State private var bounce = 0

    var body: some View {
        Image(systemName: systemImage)
            .symbolEffect(.bounce, value: bounce)
            .onChange(of: isSelected) { _, selected in
                if selected { bounce += 1 }
            }
    }
}

#Preview {
    @Previewable @State var selection = 1
    VStack {
        Spacer()
        FloatingTabBar(
            tabs: [
                FloatingTab(id: 0, title: "Countries", systemImage: "list.bullet"),
                FloatingTab(id: 1, title: "Globe", systemImage: "globe.europe.africa.fill"),
                FloatingTab(id: 2, title: "Statistics", systemImage: "chart.bar.fill"),
            ],
            selection: $selection
        )
    }
    .frame(maxWidth: .infinity)
    .background(SpaceBackground())
}
