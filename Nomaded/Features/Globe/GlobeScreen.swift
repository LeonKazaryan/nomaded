import SwiftUI

/// Main screen: the globe as the base layer with floating UI on top.
///
/// M1 spike: visited countries live in memory only. Persistence arrives in M3.
struct GlobeScreen: View {
    @State private var controller = GlobeController(style: .nomaded)
    @State private var visited: Set<String> = []
    @State private var selected: String?
    @State private var celebrations = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            SpaceBackground()

            GlobeView(controller: controller)
                .ignoresSafeArea()
                .accessibilityValue(Text("\(visited.count) countries"))

            VStack(spacing: 0) {
                WorldSummaryChip(visitedCount: visited.count)
                Spacer()
                if let selected {
                    CountryPeekCard(
                        code: selected,
                        isVisited: visited.contains(selected),
                        onToggleVisited: { toggleVisited(selected) },
                        onClose: { select(nil) }
                    )
                    .id(selected)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            #if DEBUG
            FrameRateBadge(framesPerSecond: controller.framesPerSecond)
            #endif
        }
        .sensoryFeedback(.selection, trigger: selected) { _, new in new != nil }
        .sensoryFeedback(.success, trigger: celebrations)
        .onAppear {
            controller.onCountryTap = { select($0) }
            #if DEBUG
            applyDebugLaunchArguments()
            #endif
        }
        .onChange(of: reduceMotion, initial: true) { _, value in
            controller.reduceMotion = value
        }
    }

    private func select(_ code: String?) {
        withAnimation(Motion.bouncy) { selected = code }
        controller.select(code)
    }

    private func toggleVisited(_ code: String) {
        if visited.contains(code) {
            visited.remove(code)
            controller.setVisited(visited)
        } else {
            visited.insert(code)
            controller.setVisited(visited)
            controller.celebrate(code)
            celebrations += 1
        }
    }

    #if DEBUG
    /// Lets screenshots be scripted from the command line (and later, App Store shots):
    /// `-NomadedDebugVisited IT,FR -NomadedDebugSelect IT -NomadedDebugTap 186,459 -NomadedDebugMarkAfterTap YES`
    private func applyDebugLaunchArguments() {
        let defaults = UserDefaults.standard
        if let list = defaults.string(forKey: "NomadedDebugVisited") {
            visited = Set(list.split(separator: ",").map(String.init))
            controller.setVisited(visited)
        }
        if let code = defaults.string(forKey: "NomadedDebugSelect") {
            select(code)
        }
        let tap = defaults.string(forKey: "NomadedDebugTap")?.split(separator: ",").compactMap { Double($0) }
        if let tap, tap.count == 2 {
            Task {
                // Wait for the intro to settle.
                try? await Task.sleep(for: .seconds(4))
                controller.tap(at: CGPoint(x: tap[0], y: tap[1]))
                if defaults.bool(forKey: "NomadedDebugMarkAfterTap"), let selected {
                    toggleVisited(selected)
                }
            }
        }
    }
    #endif
}

private struct WorldSummaryChip: View {
    let visitedCount: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "globe.europe.africa.fill")
                .symbolEffect(.bounce, value: visitedCount)
            Text("\(visitedCount) countries")
                .contentTransition(.numericText(value: Double(visitedCount)))
                .monospacedDigit()
        }
        .font(.system(.subheadline, design: .rounded, weight: .bold))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .animation(Motion.bouncy, value: visitedCount)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
private struct FrameRateBadge: View {
    let framesPerSecond: Int

    var body: some View {
        Text(verbatim: "\(framesPerSecond) fps")
            .font(.system(.caption2, design: .monospaced, weight: .semibold))
            .foregroundStyle(framesPerSecond >= 55 ? .green : .orange)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.black.opacity(0.45), in: Capsule())
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.leading, 16)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
#endif

#Preview {
    GlobeScreen()
        .preferredColorScheme(.dark)
}
