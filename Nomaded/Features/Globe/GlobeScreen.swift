import SwiftUI

/// Main screen: the globe as the base layer with floating UI on top.
struct GlobeScreen: View {
    @Environment(WorldStore.self) private var world
    @State private var controller = GlobeController(style: .nomaded)
    @State private var selected: String?
    @State private var celebrations = 0
    @State private var isSearching = false
    @State private var isShowingVisited = false
    @State private var isShowingStats = false
    /// Built in the background once the globe has loaded, so statistics open instantly.
    @State private var continentMaps: ContinentMaps?
    @State private var searchIndex: CountrySearchIndex?
    @State private var initialSearchQuery = ""
    @FocusState private var isSearchFieldFocused: Bool
    /// Reduce Motion: the globe dissolves to a search result instead of flying.
    @State private var isGlobeHidden = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            SpaceBackground()

            GlobeView(controller: controller)
                .ignoresSafeArea()
                // Under the statistics the globe steps back and dims, still in view.
                .scaleEffect(isShowingStats && !reduceMotion ? 0.8 : 1)
                .opacity(isGlobeHidden ? 0 : isShowingStats ? 0.45 : 1)
                .accessibilityHidden(isShowingStats)
                .accessibilityValue(Text("\(world.visitedCodes.count) countries"))

            if isSearching || isShowingVisited {
                // Dims the globe so lists stay readable; tapping it closes them.
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture {
                        setSearching(false)
                        setShowingVisited(false)
                    }
                    .accessibilityHidden(true)
                    .transition(.opacity)
            }

            // Laid out as if there were no keyboard: right after a search pick the keyboard is
            // still sliding away, and the card must not ride up on it and then drop.
            VStack(spacing: 0) {
                if !isSearching, !isShowingStats {
                    TopBar(
                        visitedCount: world.visitedCodes.count,
                        isShowingVisited: isShowingVisited,
                        isReady: controller.isReady,
                        onStats: { setShowingStats(true) },
                        onToggleVisited: { setShowingVisited(!isShowingVisited) },
                        onSearch: { setSearching(true) }
                    )
                    .transition(.opacity)
                }

                if isShowingVisited {
                    VisitedCountriesPanel(codes: RegionDisplay.sortedByName(world.visitedCodes), onPick: flyTo)
                        .padding(.top, 12)
                        // Drops out of the counter above it.
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.5, anchor: .top).combined(with: .opacity))
                }

                Spacer(minLength: 0)

                if !isSearching, !isShowingVisited, !isShowingStats, let selected {
                    CountryPeekCard(
                        code: selected,
                        isVisited: world.isVisited(selected),
                        onToggleVisited: { toggleVisited(selected) },
                        onFindNext: { setSearching(true) },
                        onClose: { select(nil) }
                    )
                    .id(selected)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .ignoresSafeArea(.keyboard)

            if isSearching, let searchIndex {
                CountrySearchPanel(
                    index: searchIndex,
                    visited: world.visitedCodes,
                    initialQuery: initialSearchQuery,
                    isFieldFocused: $isSearchFieldFocused,
                    onPick: flyTo,
                    onCancel: { setSearching(false) }
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }

            if isShowingStats {
                StatisticsScreen(
                    stats: StatsCalculator.stats(visited: world.visitedCodes, catalog: .bundled),
                    visited: world.visitedCodes,
                    maps: continentMaps,
                    onClose: { setShowingStats(false) }
                )
                .transition(.opacity)
            }

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
        .onChange(of: world.visitedCodes, initial: true) { _, codes in
            controller.setVisited(codes)
        }
        .onChange(of: controller.isReady) { _, isReady in
            guard isReady, let geometry = controller.world else { return }
            Task { continentMaps = await ContinentMaps.build(world: geometry, catalog: .bundled) }
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
        // Drop the keyboard right away. Otherwise it leaves only once the panel's exit
        // animation is over, after the globe has already started flying.
        if !searching { isSearchFieldFocused = false }
        withAnimation(Motion.bouncy) {
            isSearching = searching
            if searching { isShowingVisited = false }
        }
        if !searching { initialSearchQuery = "" }
    }

    private func setShowingVisited(_ showing: Bool) {
        withAnimation(Motion.bouncy) { isShowingVisited = showing }
    }

    private func setShowingStats(_ showing: Bool) {
        if showing {
            setSearching(false)
            setShowingVisited(false)
        }
        withAnimation(Motion.smooth) { isShowingStats = showing }
        // Nothing on the globe changes while it's covered, so it needn't redraw.
        controller.isPaused = showing
    }

    /// A pick from search or the visited list: the list closes and the globe flies there.
    private func flyTo(_ code: String) {
        setSearching(false)
        setShowingVisited(false)
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
        if world.isVisited(code) {
            world.unmarkVisited(code)
        } else {
            world.markVisited(code)
            controller.celebrate(code)
            celebrations += 1
        }
    }

    #if DEBUG
    /// Lets screenshots be scripted from the command line (and later, App Store shots):
    /// `-NomadedDebugVisited IT,FR -NomadedDebugSelect IT -NomadedDebugTap 186,459 -NomadedDebugMarkAfterTap YES`
    /// `-NomadedDebugFly LU` flies to a country after the intro, `-NomadedDebugSearch Ita`
    /// opens the search with a query typed in, `-NomadedDebugSearchPick YES` then picks the
    /// first result, `-NomadedDebugVisitedList YES` opens the visited list,
    /// `-NomadedDebugStats YES` the statistics. These runs use an empty in-memory store
    /// (see `NomadedApp`), so they never touch countries marked by hand.
    private func applyDebugLaunchArguments() {
        let defaults = UserDefaults.standard
        if let list = defaults.string(forKey: "NomadedDebugVisited") {
            list.split(separator: ",").forEach { world.markVisited(String($0)) }
        }
        if let code = defaults.string(forKey: "NomadedDebugSelect") {
            select(code)
        }
        let tap = defaults.string(forKey: "NomadedDebugTap")?.split(separator: ",").compactMap { Double($0) }
        let fly = defaults.string(forKey: "NomadedDebugFly")
        let search = defaults.string(forKey: "NomadedDebugSearch")
        let showsList = defaults.bool(forKey: "NomadedDebugVisitedList")
        let showsStats = defaults.bool(forKey: "NomadedDebugStats")
        guard (tap?.count == 2) || fly != nil || search != nil || showsList || showsStats else { return }
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
            if showsList { setShowingVisited(true) }
            if showsStats { setShowingStats(true) }
            if let search {
                initialSearchQuery = search
                setSearching(true)
                if defaults.bool(forKey: "NomadedDebugSearchPick") {
                    try? await Task.sleep(for: .seconds(2))
                    if let first = searchIndex?.results(for: search).first { flyTo(first) }
                }
            }
        }
    }
    #endif
}

private struct TopBar: View {
    let visitedCount: Int
    let isShowingVisited: Bool
    /// The globe has loaded: search and statistics need its countries.
    let isReady: Bool
    let onStats: () -> Void
    let onToggleVisited: () -> Void
    let onSearch: () -> Void

    var body: some View {
        Button(action: onToggleVisited) {
            WorldSummaryChip(visitedCount: visitedCount, isExpanded: isShowingVisited)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityHint(isShowingVisited ? "Hides the list" : "Shows the countries you've visited")
        .frame(maxWidth: .infinity)
        .overlay(alignment: .leading) {
            RoundButton(systemImage: "chart.bar.fill", action: onStats)
                .disabled(!isReady)
                .accessibilityLabel("Statistics")
        }
        .overlay(alignment: .trailing) {
            RoundButton(systemImage: "magnifyingglass", action: onSearch)
                .disabled(!isReady)
                .accessibilityLabel("Search countries")
        }
    }
}

private struct RoundButton: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(Typography.headline)
                .frame(width: 44, height: 44)
                .glass(Circle())
        }
        .buttonStyle(.pressable)
    }
}

private struct WorldSummaryChip: View {
    let visitedCount: Int
    let isExpanded: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "globe.europe.africa.fill")
                .symbolEffect(.bounce, value: visitedCount)
            Text("\(visitedCount) countries")
                .contentTransition(.numericText(value: Double(visitedCount)))
            // Hints that the counter opens the list.
            Image(systemName: "chevron.down")
                .font(Typography.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                .accessibilityHidden(true)
        }
        .font(Typography.label)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glass(Capsule())
        .animation(Motion.bouncy, value: visitedCount)
        .animation(Motion.snappy, value: isExpanded)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
/// The globe's render rate next to the rate the screen can give the app. "60 fps · display 120"
/// means the renderer holds the globe at 60; both at 60 means the phone does (Low Power Mode,
/// or Accessibility → Motion → Limit Frame Rate).
private struct FrameRateBadge: View {
    let framesPerSecond: Int
    @State private var display = DisplayRateMeter()

    var body: some View {
        Text(verbatim: "\(framesPerSecond) fps · display \(display.framesPerSecond)")
            .font(.system(.caption2, design: .monospaced, weight: .semibold))
            .foregroundStyle(framesPerSecond >= 55 ? .green : .orange)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.black.opacity(0.45), in: Capsule())
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // Under the top bar, clear of its buttons.
            .padding(.leading, 16)
            .padding(.top, 52)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear { display.start() }
            .onDisappear { display.stop() }
    }
}

/// Counts the frames a display link asking for 120 Hz actually gets.
@Observable @MainActor
private final class DisplayRateMeter: NSObject {
    private(set) var framesPerSecond = 0
    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private var sample = (frames: 0, start: CACurrentMediaTime())

    func start() {
        guard link == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(step))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func step() {
        sample.frames += 1
        let elapsed = CACurrentMediaTime() - sample.start
        guard elapsed >= 0.5 else { return }
        framesPerSecond = Int((Double(sample.frames) / elapsed).rounded())
        sample = (0, CACurrentMediaTime())
    }
}
#endif

#Preview {
    GlobeScreen()
        .environment(WorldStore.scratch())
        .preferredColorScheme(.dark)
}
