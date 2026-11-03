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
    /// The country whose city search is open.
    @State private var addingCityTo: String?
    /// The city picked in the card or on the globe: its name always shows.
    @State private var highlightedCity: UUID?
    /// The country to unmark once the user confirms losing its cities.
    @State private var confirmingUnmark: String?
    @State private var landings = 0
    @State private var confetti: [ConfettiBurst] = []
    /// The country just marked: its stamp slams into the card instead of just being there.
    @State private var justMarked: String?
    /// A country its first city is about to mark: no stamp until the city lands.
    @State private var awaitingLanding: String?
    @State private var milestoneQueue: [MilestoneEvent] = []
    @State private var shownMilestone: MilestoneEvent?
    /// The bundled city list, loaded off the main thread at launch: capitals get stars.
    @State private var cityCatalog: CityCatalog?
    @State private var initialCityQuery = ""
    /// Built in the background once the globe has loaded, so statistics open instantly.
    @State private var continentMaps: ContinentMaps?
    @State private var searchIndex: CountrySearchIndex?
    @State private var initialSearchQuery = ""
    @State private var initialSearchMode = SearchPanel.Mode.countries
    @FocusState private var isSearchFieldFocused: Bool
    /// Reduce Motion: the globe dissolves to a search result instead of flying.
    @State private var isGlobeHidden = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Set once the first-launch introduction is done (or wasn't needed).
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    /// The first-launch step on screen; `nil` once it's done.
    @State private var onboarding: OnboardingStep?
    /// When the jump out of hyperspace began, on first launch.
    @State private var warpStart: Date?
    @State private var picks = 0

    /// The one split every counter on this screen uses.
    private var visitedPlaces: VisitedPlaces {
        CountryCatalog.bundled.split(world.visitedCodes)
    }

    var body: some View {
        let visitedPlaces = visitedPlaces
        ZStack {
            SpaceBackground()

            if onboarding == .welcome, let warpStart {
                // Behind the globe: the stars stream past it as it arrives.
                WarpField(start: warpStart)
            }

            GlobeView(controller: controller)
                .ignoresSafeArea()
                // Under the statistics the globe steps back and dims, still in view; under a
                // milestone it only dims (the milestone's own dark veil frames it).
                .scaleEffect(isShowingStats && !reduceMotion ? 0.8 : 1)
                .opacity(isGlobeHidden ? 0 : isGlobeBehind ? 0.45 : 1)
                .accessibilityHidden(isShowingStats)
                .accessibilityValue(Text("\(visitedPlaces.countries.count) countries"))

            if isSearching || isShowingVisited || addingCityTo != nil {
                // Dims the globe so lists stay readable; tapping it closes them.
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture {
                        setSearching(false)
                        setShowingVisited(false)
                        setAddingCity(nil)
                    }
                    .accessibilityHidden(true)
                    .transition(.opacity)
            }

            if onboarding == nil {
                // Laid out as if there were no keyboard: right after a search pick the keyboard is
                // still sliding away, and the card must not ride up on it and then drop.
                VStack(spacing: 0) {
                    if !isSearching, !isShowingStats, addingCityTo == nil {
                        TopBar(
                            visited: visitedPlaces,
                            isShowingVisited: isShowingVisited,
                            isReady: controller.isReady,
                            onStats: { setShowingStats(true) },
                            onToggleVisited: { setShowingVisited(!isShowingVisited) },
                            onSearch: { setSearching(true) }
                        )
                        .transition(.opacity)
                    }

                    if isShowingVisited {
                        VisitedCountriesPanel(
                            places: VisitedPlaces(
                                countries: RegionDisplay.sortedByName(visitedPlaces.countries),
                                territories: RegionDisplay.sortedByName(visitedPlaces.territories)
                            ),
                            onPick: flyTo
                        )
                            .padding(.top, 12)
                            // Drops out of the counter above it.
                            .transition(reduceMotion ? .opacity : .scale(scale: 0.5, anchor: .top).combined(with: .opacity))
                    }

                    Spacer(minLength: 0)

                    if !isSearching, !isShowingVisited, !isShowingStats, addingCityTo == nil, let selected {
                        CountryPeekCard(
                            code: selected,
                            isVisited: world.isVisited(selected),
                            // Newest first: a city just added is the first chip.
                            cities: world.cities(in: selected).reversed(),
                            highlightedCity: highlightedCity,
                            visitedSince: awaitingLanding == selected ? nil : world.firstVisits[selected],
                            stampInk: controller.visitedColor(of: selected).map(Color.init(components:)) ?? Palette.accentLight,
                            stampSlams: justMarked == selected,
                            onToggleVisited: { toggleVisited(selected) },
                            onFindNext: { setSearching(true) },
                            onAddCity: { setAddingCity(selected) },
                            onSelectCity: selectCity,
                            onRemoveCity: removeCity,
                            onClose: { select(nil) }
                        )
                        .id(selected)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .ignoresSafeArea(.keyboard)
                .transition(.opacity)
            }

            ConfettiView(bursts: confetti)

            if isSearching, let searchIndex {
                SearchPanel(
                    index: searchIndex,
                    visited: world.visitedCodes,
                    knownCountries: Set(controller.countryCodes),
                    initialQuery: initialSearchQuery,
                    initialMode: initialSearchMode,
                    isFieldFocused: $isSearchFieldFocused,
                    onPickCountry: flyTo,
                    onPickCity: addCity,
                    onCancel: { setSearching(false) }
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }

            if let code = addingCityTo {
                CitySearchPanel(
                    countryCode: code,
                    bounds: controller.world?.countries.first { $0.code == code }?.bounds,
                    initialQuery: initialCityQuery,
                    knownCountries: Set(controller.countryCodes),
                    isFieldFocused: $isSearchFieldFocused,
                    onPick: addCity,
                    onCancel: { setAddingCity(nil) }
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }

            if isShowingStats {
                StatisticsScreen(
                    stats: StatsCalculator.stats(visited: world.visitedCodes, catalog: .bundled, cities: world.cities.count),
                    visited: world.visitedCodes,
                    maps: continentMaps,
                    earned: world.milestones,
                    onPick: flyTo,
                    onClose: { setShowingStats(false) }
                )
                .transition(.opacity)
            }

            if onboarding != nil {
                OnboardingFlow(
                    step: Binding(get: { onboarding ?? .welcome }, set: { onboarding = $0 }),
                    controller: controller,
                    onToggle: togglePick,
                    onFinish: finishOnboarding
                )
                .transition(.opacity)
            }

            if let shownMilestone {
                MilestoneCelebration(
                    event: shownMilestone,
                    outlines: shownMilestone.continent.flatMap { continentMaps?.outlines[$0] },
                    onDismiss: dismissMilestone
                )
                .transition(.opacity)
            }

            #if DEBUG
            FrameRateBadge(framesPerSecond: controller.framesPerSecond)
            #endif
        }
        .sensoryFeedback(Haptics.select, trigger: selected) { _, new in new != nil }
        .sensoryFeedback(Haptics.markVisited, trigger: celebrations)
        .sensoryFeedback(Haptics.cityLanded, trigger: landings)
        .sensoryFeedback(Haptics.select, trigger: picks)
        .confirmationDialog(
            Text("Remove \(RegionDisplay.name(for: confirmingUnmark ?? "")) from visited?"),
            isPresented: Binding(get: { confirmingUnmark != nil }, set: { if !$0 { confirmingUnmark = nil } }),
            titleVisibility: .visible,
            presenting: confirmingUnmark
        ) { code in
            Button("Remove", role: .destructive) { unmark(code) }
            Button("Cancel", role: .cancel) {}
        } message: { code in
            Text("\(world.cities(in: code).count) cities will be removed with it.")
        }
        .onAppear {
            startOnboardingIfNeeded()
            controller.onCountryTap = { code in
                // While picking countries on first launch, a tap ticks the country off.
                if let onboarding {
                    if onboarding == .pick, let code { togglePick(code) }
                } else {
                    select(code)
                }
            }
            controller.onCityTap = { selectCity($0) }
            controller.onCityLanded = { id, point, marksCountry in
                landings += 1
                if marksCountry, let city = world.cities.first(where: { $0.id == id }) {
                    awaitingLanding = nil
                    celebrateMark(city.countryCode, at: point)
                }
            }
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
        .onChange(of: world.cities, initial: true) { _, cities in
            updateCityMarkers()
            if let highlightedCity, !cities.contains(where: { $0.id == highlightedCity }) {
                self.highlightedCity = nil
            }
        }
        .task {
            // About a megabyte to decode; search uses it too, so it's ready before anyone types.
            cityCatalog = await Task.detached(priority: .utility) { CityCatalog.bundled }.value
            updateCityMarkers()
        }
        .onChange(of: controller.isReady) { _, isReady in
            guard isReady, let geometry = controller.world else { return }
            // The globe starts flying in now, not at launch: loading can take a moment.
            if onboarding == .welcome, !reduceMotion { warpStart = .now }
            Task { continentMaps = await ContinentMaps.build(world: geometry, catalog: .bundled) }
        }
    }

    // MARK: - First launch

    /// New users, with nothing marked, get the introduction. Anyone who already has marks
    /// (from before onboarding existed) is simply counted as done.
    private func startOnboardingIfNeeded() {
        var shows = !hasOnboarded && world.visitedCodes.isEmpty
        #if DEBUG
        // Scripted screenshot runs skip it unless they ask for it.
        if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("-NomadedDebug") }) {
            shows = UserDefaults.standard.bool(forKey: "NomadedDebugOnboarding")
        } else if !shows, !hasOnboarded {
            hasOnboarded = true
        }
        #else
        if !shows, !hasOnboarded { hasOnboarded = true }
        #endif
        guard shows else { return }
        onboarding = .welcome
        controller.introStyle = .arrival
    }

    /// A country ticked off in the onboarding list or on the globe: it fills in quietly (no
    /// ring, a small jump) as the globe turns to it; tapped again, it drains away.
    private func togglePick(_ code: String) {
        if world.isVisited(code) {
            world.unmarkVisited(code)
            controller.drain(code)
        } else {
            world.markVisited(code)
            controller.lookAt(code)
            controller.celebrate(code, quietly: true)
        }
        picks += 1
    }

    private func finishOnboarding() {
        controller.frame(offset: 0, zoom: 1)
        // The picks reach their milestones quietly; celebrations start with the next mark.
        world.earnMilestones()
        hasOnboarded = true
        withAnimation(Motion.smooth) {
            onboarding = nil
            warpStart = nil
        }
    }

    private var isGlobeBehind: Bool {
        isShowingStats || shownMilestone != nil
    }

    private func updateCityMarkers() {
        controller.setCities(world.cities.map { city in
            GlobeController.CityMarker(
                id: city.id,
                name: city.name,
                countryCode: city.countryCode,
                coordinate: GeoCoordinate(latitude: city.latitude, longitude: city.longitude),
                isCapital: cityCatalog?.isCapital(city) ?? false
            )
        })
    }

    private func select(_ code: String?) {
        if code != selected { justMarked = nil }
        withAnimation(Motion.bouncy) {
            selected = code
            highlightedCity = nil
        }
        controller.highlightCity(nil)
        controller.select(code)
    }

    private func setAddingCity(_ code: String?) {
        if code == nil {
            isSearchFieldFocused = false
            initialCityQuery = ""
        }
        withAnimation(Motion.bouncy) { addingCityTo = code }
    }

    /// A city picked in either search: it's saved (marking its country if it wasn't, since
    /// you were there), the globe flies there, and the dot drops in once the camera arrives.
    private func addCity(_ draft: CityDraft) {
        let wasVisited = world.isVisited(draft.countryCode)
        setSearching(false)
        setAddingCity(nil)
        let city = world.addCity(draft)
        // A city in a new country: the country is celebrated when the city lands, filling
        // from it, in view rather than mid-flight.
        controller.landCity(city.id, marking: wasVisited ? nil : city.countryCode)
        if !wasVisited { awaitingLanding = city.countryCode }
        focus(on: city)
    }

    /// A city chip or dot: its country is selected and the globe flies close to it.
    private func selectCity(_ id: UUID) {
        guard let city = world.cities.first(where: { $0.id == id }) else { return }
        focus(on: city)
    }

    private func focus(on city: CityPin) {
        withAnimation(Motion.bouncy) {
            selected = city.countryCode
            highlightedCity = city.id
        }
        controller.highlightCity(city.id)
        controller.select(city.countryCode, framing: .point(GeoCoordinate(latitude: city.latitude, longitude: city.longitude)))
    }

    private func removeCity(_ id: UUID) {
        world.removeCity(id)
        if highlightedCity == id {
            withAnimation(Motion.bouncy) { highlightedCity = nil }
            controller.highlightCity(nil)
        }
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
        if !searching {
            initialSearchQuery = ""
            initialSearchMode = .countries
        }
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

    /// A pick from search, the visited list or the statistics: whatever was open closes and
    /// the globe flies there.
    private func flyTo(_ code: String) {
        setSearching(false)
        setShowingVisited(false)
        if isShowingStats { setShowingStats(false) }
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
            // Losing cities is worth a question; a bare mark isn't.
            if world.cities(in: code).isEmpty {
                unmark(code)
            } else {
                confirmingUnmark = code
            }
        } else {
            world.markVisited(code)
            celebrateMark(code, at: controller.celebrate(code))
        }
    }

    /// The color drains away calmly; no confetti for this.
    private func unmark(_ code: String) {
        world.unmarkVisited(code)
        controller.drain(code)
        if justMarked == code { justMarked = nil }
    }

    /// The SwiftUI half of marking a country, after the globe's fill and ring: the haptic,
    /// confetti thrown from where the fill starts, the stamp slamming into the card.
    private func celebrateMark(_ code: String, at point: CGPoint?) {
        celebrations += 1
        justMarked = code
        queueMilestones(world.earnMilestones(), from: code)
        guard !reduceMotion, let point, let color = controller.visitedColor(of: code) else { return }
        let candy = Color(components: color)
        let pale = Color(components: color + (SIMD3(repeating: 1) - color) * 0.5)
        let burst = ConfettiBurst(origin: point, colors: [candy, candy, pale, .white, Palette.capital])
        confetti.append(burst)
        Task {
            try? await Task.sleep(for: .seconds(ConfettiBurst.lifetime + 0.1))
            confetti.removeAll { $0.id == burst.id }
        }
    }

    /// Milestones the mark just reached take the stage once the country's own celebration
    /// has had its moment, one at a time.
    private func queueMilestones(_ milestones: [Milestone], from code: String) {
        guard !milestones.isEmpty else { return }
        let stats = StatsCalculator.stats(visited: world.visitedCodes, catalog: .bundled)
        let events = milestones.map { milestone in
            var remaining: Int?
            if case .continent(let continent) = milestone,
               let progress = stats.continents.first(where: { $0.continent == continent }),
               progress.countries.total > 0 {
                remaining = progress.countries.total - progress.countries.visited
            }
            return MilestoneEvent(milestone: milestone, place: code, worldShare: stats.countries.share, remainingOnContinent: remaining)
        }
        Task {
            try? await Task.sleep(for: .seconds(1.1))
            milestoneQueue += events
            showNextMilestone()
        }
    }

    private func showNextMilestone() {
        guard shownMilestone == nil, !milestoneQueue.isEmpty else { return }
        withAnimation(Motion.smooth) { shownMilestone = milestoneQueue.removeFirst() }
    }

    private func dismissMilestone() {
        withAnimation(Motion.smooth) { shownMilestone = nil }
        Task {
            try? await Task.sleep(for: .seconds(0.4))
            showNextMilestone()
        }
    }

    #if DEBUG
    /// Lets screenshots be scripted from the command line (and later, App Store shots):
    /// `-NomadedDebugVisited IT,FR -NomadedDebugSelect IT -NomadedDebugTap 186,459 -NomadedDebugMarkAfterTap YES`
    /// `-NomadedDebugFly LU` flies to a country after the intro, `-NomadedDebugSearch Ita`
    /// opens the search with a query typed in (`-NomadedDebugSearchCities YES`: on the Cities
    /// tab), `-NomadedDebugSearchPick YES` then picks the
    /// first result, `-NomadedDebugVisitedList YES` opens the visited list,
    /// `-NomadedDebugStats YES` the statistics. `-NomadedDebugCities "Rome:IT:41.9:12.5,…"`
    /// adds cities, `-NomadedDebugCityFocus YES` flies to the first,
    /// `-NomadedDebugAddCity IT` opens the city search (`-NomadedDebugCityQuery Фл` types in it),
    /// `-NomadedDebugLandCity "Genoa:IT:44.41:8.93"` adds one as if picked in search,
    /// `-NomadedDebugOnboarding YES` shows the first-launch introduction
    /// (`-NomadedDebugOnboardingStep pick` or `ready` jumps into it; `-NomadedDebugOnboardingQuery Ита`
    /// types into the pick step's search),
    /// `-NomadedDebugMark IT` flies to a country and marks it, celebration and all
    /// (`-NomadedDebugUnmarkAfter YES` unmarks it 3 s later), `-NomadedDebugMilestone countries.25`
    /// shows a milestone's celebration. These runs
    /// use an empty in-memory store (see `NomadedApp`), so they never touch countries marked by hand.
    private func applyDebugLaunchArguments() {
        let defaults = UserDefaults.standard
        if let list = defaults.string(forKey: "NomadedDebugVisited") {
            list.split(separator: ",").forEach { world.markVisited(String($0)) }
        }
        if let code = defaults.string(forKey: "NomadedDebugSelect") {
            select(code)
        }
        let cities = defaults.string(forKey: "NomadedDebugCities")?.split(separator: ",").compactMap(Self.debugCity) ?? []
        cities.forEach { world.addCity($0) }
        // Seeded marks reach milestones quietly; only the next real mark celebrates.
        world.earnMilestones()
        let debugMilestone = defaults.string(forKey: "NomadedDebugMilestone").flatMap(Milestone.init(id:))
        switch defaults.string(forKey: "NomadedDebugOnboardingStep") {
        case "pick": onboarding = .pick
        case "ready": onboarding = .ready
        default: break
        }
        let focusesCity = defaults.bool(forKey: "NomadedDebugCityFocus")
        let marks = defaults.string(forKey: "NomadedDebugMark")
        let addsCityTo = defaults.string(forKey: "NomadedDebugAddCity")
        let landsCity = defaults.string(forKey: "NomadedDebugLandCity").flatMap { Self.debugCity($0[...]) }
        let tap = defaults.string(forKey: "NomadedDebugTap")?.split(separator: ",").compactMap { Double($0) }
        let fly = defaults.string(forKey: "NomadedDebugFly")
        let search = defaults.string(forKey: "NomadedDebugSearch")
        let showsList = defaults.bool(forKey: "NomadedDebugVisitedList")
        let showsStats = defaults.bool(forKey: "NomadedDebugStats")
        guard (tap?.count == 2) || fly != nil || search != nil || showsList || showsStats || focusesCity
                || addsCityTo != nil || landsCity != nil || marks != nil || debugMilestone != nil
        else { return }
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
            if focusesCity, let first = world.cities.first { focus(on: first) }
            if let addsCityTo {
                select(addsCityTo)
                initialCityQuery = defaults.string(forKey: "NomadedDebugCityQuery") ?? ""
                setAddingCity(addsCityTo)
            }
            if let landsCity { addCity(landsCity) }
            if let debugMilestone {
                milestoneQueue = [MilestoneEvent(milestone: debugMilestone, place: "JP", worldShare: 25.0 / 195, remainingOnContinent: 47)]
                showNextMilestone()
            }
            if let marks {
                flyTo(marks)
                try? await Task.sleep(for: .seconds(2.5))
                toggleVisited(marks)
                if defaults.bool(forKey: "NomadedDebugUnmarkAfter") {
                    try? await Task.sleep(for: .seconds(3))
                    toggleVisited(marks)
                }
            }
            if let search {
                initialSearchQuery = search
                if defaults.bool(forKey: "NomadedDebugSearchCities") { initialSearchMode = .cities }
                setSearching(true)
                if defaults.bool(forKey: "NomadedDebugSearchPick") {
                    try? await Task.sleep(for: .seconds(2))
                    if let first = searchIndex?.results(for: search).first { flyTo(first) }
                }
            }
        }
    }

    /// "Name:CC:latitude:longitude".
    private static func debugCity(_ entry: Substring) -> CityDraft? {
        let parts = entry.split(separator: ":").map(String.init)
        guard parts.count == 4, let latitude = Double(parts[2]), let longitude = Double(parts[3]) else { return nil }
        return CityDraft(name: parts[0], region: "", countryCode: parts[1], latitude: latitude, longitude: longitude)
    }
    #endif
}

private struct TopBar: View {
    let visited: VisitedPlaces
    let isShowingVisited: Bool
    /// The globe has loaded: search and statistics need its countries.
    let isReady: Bool
    let onStats: () -> Void
    let onToggleVisited: () -> Void
    let onSearch: () -> Void

    var body: some View {
        Button(action: onToggleVisited) {
            WorldSummaryChip(
                countries: visited.countries.count,
                territories: visited.territories.count,
                isExpanded: isShowingVisited
            )
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

/// "90 countries +10": the 195-country count the statistics use, with territories beside
/// it, so marking Greenland still visibly counts. Each new mark sends a "+1" up out of it.
private struct WorldSummaryChip: View {
    let countries: Int
    let territories: Int
    let isExpanded: Bool

    @State private var bumps: [UUID] = []

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "globe.europe.africa.fill")
                .symbolEffect(.bounce, value: countries + territories)
            Text("\(countries) countries")
                .contentTransition(.numericText(value: Double(countries)))
            if territories > 0 {
                Text(verbatim: "+\(territories)")
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText(value: Double(territories)))
                    .accessibilityLabel(Text("+\(territories) territories"))
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
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
        .animation(Motion.bouncy, value: countries)
        .animation(Motion.bouncy, value: territories)
        .animation(Motion.snappy, value: isExpanded)
        .overlay(alignment: .trailing) {
            ZStack {
                ForEach(bumps, id: \.self) { _ in PlusOne() }
            }
            .offset(x: 6)
        }
        .onChange(of: countries + territories) { old, new in
            guard new > old else { return }
            let bump = UUID()
            bumps.append(bump)
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                bumps.removeAll { $0 == bump }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Floats up out of the counter and fades.
private struct PlusOne: View {
    @State private var risen = false
    @State private var faded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(verbatim: "+1")
            .font(Typography.headline)
            .foregroundStyle(Palette.accentLight)
            .scaleEffect(risen || reduceMotion ? 1 : 0.4)
            .offset(y: risen && !reduceMotion ? -30 : 0)
            .opacity(faded ? 0 : 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear {
                withAnimation(Motion.bouncy) { risen = true }
                withAnimation(Motion.smooth.delay(0.45)) { faded = true }
            }
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
