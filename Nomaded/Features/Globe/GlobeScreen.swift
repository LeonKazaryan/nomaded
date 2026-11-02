import SwiftUI

/// Main screen: the globe as the base layer with floating UI on top.
///
/// M1 spike: visited countries live in memory only. Persistence arrives in M3.
struct GlobeScreen: View {
    @State private var controller = GlobeController(style: .nomaded)
    @State private var visited: Set<String> = []
    @State private var selected: String?
    @State private var celebrations = 0
    @State private var isSearching = false
    @State private var searchIndex: CountrySearchIndex?
    @State private var initialSearchQuery = ""
    /// Reduce Motion: the globe dissolves to a search result instead of flying.
    @State private var isGlobeHidden = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            SpaceBackground()

            GlobeView(controller: controller)
                .ignoresSafeArea()
                .opacity(isGlobeHidden ? 0 : 1)
                .accessibilityValue(Text("\(visited.count) countries"))

            if isSearching {
                // Dims the globe so results stay readable; tapping it cancels the search.
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture { setSearching(false) }
                    .accessibilityHidden(true)
                    .transition(.opacity)
            }

            VStack(spacing: 0) {
                if isSearching, let searchIndex {
                    CountrySearchPanel(
                        index: searchIndex,
                        visited: visited,
                        initialQuery: initialSearchQuery,
                        onPick: flyTo,
                        onCancel: { setSearching(false) }
                    )
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                } else {
                    TopBar(visitedCount: visited.count, canSearch: controller.isReady) {
                        setSearching(true)
                    }
                    .transition(.opacity)

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
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            #if DEBUG
            FrameRateBadge(framesPerSecond: controller.framesPerSecond)
            #endif
        }
        .sensoryFeedback(Haptics.select, trigger: selected) { _, new in new != nil }
        .sensoryFeedback(Haptics.markVisited, trigger: celebrations)
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

    private func setSearching(_ searching: Bool) {
        if searching, searchIndex == nil {
            searchIndex = CountrySearchIndex(codes: controller.countryCodes)
        }
        withAnimation(Motion.bouncy) { isSearching = searching }
        if !searching { initialSearchQuery = "" }
    }

    /// A search result: the panel closes and the globe flies to the country.
    private func flyTo(_ code: String) {
        setSearching(false)
        withAnimation(Motion.bouncy) { selected = code }
        guard reduceMotion else {
            controller.select(code, framing: .flight)
            return
        }
        withAnimation(Motion.snappy) {
            isGlobeHidden = true
        } completion: {
            controller.select(code, framing: .flight)
            withAnimation(Motion.smooth) { isGlobeHidden = false }
        }
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
    /// `-NomadedDebugFly LU` flies to a country after the intro, `-NomadedDebugSearch Ita`
    /// opens the search with a query typed in.
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
        let fly = defaults.string(forKey: "NomadedDebugFly")
        let search = defaults.string(forKey: "NomadedDebugSearch")
        guard (tap?.count == 2) || fly != nil || search != nil else { return }
        Task {
            // Wait for the intro to settle.
            try? await Task.sleep(for: .seconds(4))
            if let tap, tap.count == 2 {
                controller.tap(at: CGPoint(x: tap[0], y: tap[1]))
                if defaults.bool(forKey: "NomadedDebugMarkAfterTap"), let selected {
                    toggleVisited(selected)
                }
            }
            if let fly { flyTo(fly) }
            if let search {
                initialSearchQuery = search
                setSearching(true)
            }
        }
    }
    #endif
}

private struct TopBar: View {
    let visitedCount: Int
    let canSearch: Bool
    let onSearch: () -> Void

    var body: some View {
        WorldSummaryChip(visitedCount: visitedCount)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .trailing) {
                Button(action: onSearch) {
                    Image(systemName: "magnifyingglass")
                        .font(Typography.headline)
                        .frame(width: 44, height: 44)
                        .glass(Circle())
                }
                .buttonStyle(.pressable)
                .disabled(!canSearch)
                .accessibilityLabel("Search countries")
            }
    }
}

private struct WorldSummaryChip: View {
    let visitedCount: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "globe.europe.africa.fill")
                .symbolEffect(.bounce, value: visitedCount)
            Text("\(visitedCount) countries")
                .contentTransition(.numericText(value: Double(visitedCount)))
        }
        .font(Typography.label)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glass(Capsule())
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
