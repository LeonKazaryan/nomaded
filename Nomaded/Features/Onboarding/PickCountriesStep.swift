import SwiftUI

/// "Where have you been?": the globe above, a glass panel below with search, a continent
/// filter and every country with a check. Each pick turns the globe to the country and fills
/// it in; the globe itself takes taps too. Fast enough to tick off thirty countries in a minute.
struct PickCountriesStep: View {
    let controller: GlobeController
    /// An iPad held sideways: the title and the panel make a column left of the globe.
    let sideBySide: Bool
    /// The globe fits between the title and the panel (or right of them).
    @Binding var globeRoom: GlobeRoom
    let onToggle: (String) -> Void
    let onDone: () -> Void

    /// How much of the screen the panel takes; the globe gets the rest.
    private static let panelShare = 0.52
    /// While typing, the panel rises to the keyboard and leaves the globe this strip on top.
    private static let searchingGlobeStrip = 140.0

    @Environment(WorldStore.self) private var world
    @State private var query = ""
    @State private var continent: Continent?
    @State private var index: CountrySearchIndex?
    @State private var appeared = false
    @FocusState private var isSearchFocused: Bool
    @ScaledMetric(relativeTo: .body) private var rowHeight = 54
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        GeometryReader { proxy in
            Group {
                if sideBySide {
                    // The panel runs the column's height; the keyboard shortens the column,
                    // and the globe beside it moves up with it.
                    SideColumn(globeRoom: $globeRoom) {
                        VStack(spacing: 0) {
                            if !isSearchFocused {
                                appearingHeader
                            }
                            panel
                                .frame(maxHeight: .infinity)
                                .modifier(PanelEntrance(appeared: appeared, distance: proxy.size.height))
                        }
                    }
                } else {
                    VStack(spacing: 0) {
                        if !isSearchFocused {
                            appearingHeader
                                .onScreenEdge(.bottom) { globeRoom.top = $0 }
                        }
                        Spacer(minLength: 0)
                        panel
                            .frame(height: panelHeight(in: proxy.size.height))
                            .modifier(PanelEntrance(appeared: appeared, distance: proxy.size.height * Self.panelShare))
                            .onScreenEdge(.top) { globeRoom.bottom = $0 }
                    }
                    .frame(maxWidth: Metrics.panelWidth)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                }
            }
            .animation(reduceMotion ? Motion.smooth : Motion.snappy, value: isSearchFocused)
        }
        .onAppear {
            withAnimation(reduceMotion ? Motion.smooth : Motion.bouncy) { appeared = true }
            #if DEBUG
            if let debugQuery = UserDefaults.standard.string(forKey: "NomadedDebugOnboardingQuery") {
                query = debugQuery
                isSearchFocused = true
            }
            #endif
        }
        .onChange(of: isSearchFocused) { _, isFocused in
            // The globe shrinks to the strip above the panel; the title gives it the room.
            if isFocused, !sideBySide { globeRoom.top = nil }
        }
        .onChange(of: controller.isReady, initial: true) { _, isReady in
            // The countries come with the globe.
            if isReady, index == nil { index = CountrySearchIndex(codes: controller.countryCodes) }
        }
    }

    private var appearingHeader: some View {
        header
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : -20)
            .transition(.opacity)
    }

    private var header: some View {
        // With the largest text "Skip" gets a row of its own, so the title has the width.
        let isLarge = dynamicTypeSize.isAccessibilitySize
        return (isLarge ? AnyLayout(VStackLayout(alignment: .trailing, spacing: 0)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12))) {
            if isLarge { skip }
            VStack(alignment: .leading, spacing: 4) {
                Text("Where have you been?")
                    .font(Typography.title)
                Text("Tap the countries you've visited. You can change this any time.")
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !isLarge { skip }
        }
        .padding(.top, 8)
    }

    private var skip: some View {
        Button("Skip", action: onDone)
            .font(Typography.label)
            .foregroundStyle(.secondary)
            .frame(minHeight: 44)
            .buttonStyle(.pressable)
    }

    private func panelHeight(in height: Double) -> Double {
        isSearchFocused ? max(height - Self.searchingGlobeStrip, height * Self.panelShare) : height * Self.panelShare
    }

    private var panel: some View {
        VStack(spacing: 12) {
            SearchField(placeholder: "Search countries", text: $query, isFocused: $isSearchFocused)
            // While typing, the search is the filter, and the list gets the room.
            if !isSearchFocused {
                ContinentFilter(selection: $continent)
                    .transition(.opacity)
            }
            list
            if !isSearchFocused {
                continueButton
                    .transition(.opacity)
            }
        }
        .padding(16)
        .glassCard(cornerRadius: 32)
        .padding(.bottom, 8)
    }

    private var codes: [String] {
        guard let index else { return [] }
        let all = index.results(for: query)
        guard let continent else { return all }
        let catalog = CountryCatalog.bundled
        return all.filter { catalog[$0]?.continent == continent }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(codes, id: \.self) { code in
                    Button {
                        onToggle(code)
                    } label: {
                        PickRow(code: code, isOn: world.isVisited(code))
                            .frame(minHeight: rowHeight)
                    }
                    .buttonStyle(.pressable)
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .overlay {
            if codes.isEmpty {
                Text("No countries found")
                    .font(Typography.body)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var continueButton: some View {
        let count = world.visitedCodes.count
        return Button(action: onDone) {
            HStack(spacing: 8) {
                Text("Continue")
                if count > 0 {
                    Text(count, format: .number)
                        .monospacedDigit()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.white.opacity(0.25), in: Capsule())
                        .contentTransition(.numericText(value: Double(count)))
                        .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
                }
            }
            .animation(Motion.bouncy, value: count)
        }
        .buttonStyle(.capsule(.accent))
    }
}

/// The panel rising into place from below the screen.
private struct PanelEntrance: ViewModifier {
    let appeared: Bool
    let distance: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .offset(y: appeared || reduceMotion ? 0 : distance)
            .opacity(appeared ? 1 : 0)
    }
}

/// A country with a check that pops when it's picked.
private struct PickRow: View {
    let code: String
    let isOn: Bool

    var body: some View {
        HStack(spacing: 14) {
            Text(verbatim: RegionDisplay.flag(for: code))
                .font(.system(size: 28))
                .accessibilityHidden(true)
            Text(verbatim: RegionDisplay.name(for: code))
                .font(Typography.body)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(isOn ? AnyShapeStyle(Palette.accentLight) : AnyShapeStyle(.tertiary))
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: isOn)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// "All" and the seven continents as capsules; the picked one fills with the accent.
private struct ContinentFilter: View {
    @Binding var selection: Continent?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                chip(nil, title: Text("All"))
                ForEach(Continent.allCases, id: \.self) { continent in
                    chip(continent, title: Text(continent.name))
                }
            }
        }
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .padding(.horizontal, -16)
        .sensoryFeedback(Haptics.select, trigger: selection)
    }

    private func chip(_ continent: Continent?, title: Text) -> some View {
        let isSelected = selection == continent
        return Button {
            withAnimation(Motion.snappy) { selection = continent }
        } label: {
            title
                .font(Typography.label)
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .background(isSelected ? AnyShapeStyle(Palette.accent) : AnyShapeStyle(.white.opacity(0.12)), in: Capsule())
                .padding(.vertical, 4)
                .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
