import SwiftUI

/// Main screen: the globe as the base layer with floating UI on top.
struct GlobeScreen: View {
    @Environment(WorldStore.self) private var world
    @State private var controller = GlobeController(style: .nomaded)
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
                .accessibilityValue(Text("\(world.visitedCodes.count) countries"))

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
                        visited: world.visitedCodes,
                        initialQuery: initialSearchQuery,
                        onPick: flyTo,
                        onCancel: { setSearching(false) }
                    )
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                } else {
                    TopBar(visitedCount: world.visitedCodes.count, canSearch: controller.isReady) {
                        setSearching(true)
                    }
                    .transition(.opacity)

                    Spacer()

                    if let selected {
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
        .onChange(of: world.visitedCodes, initial: true) { _, codes in
            controller.setVisited(codes)
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
    /// opens the search with a query typed in. These runs use an empty in-memory store
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
            .padding(.leading, 16)
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
