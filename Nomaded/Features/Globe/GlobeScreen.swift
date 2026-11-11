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
    /// The places on the globe in its worldview: what every list and count here is made of.
    @State private var places = CountryCatalog.bundled
    #if DEBUG
    @AppStorage("NomadedDebugShowsFrameRate") private var showsFrameRate = true
    @State private var worldviewSwitches = 0
    #endif
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
    /// "Welcome back": the user's world just came back from iCloud.
    @State private var isShowingRestored = false
    @State private var restores = 0
    /// The story being shared, over the statistics.
    @State private var story: StoryContent?
    /// An open iPhone Duo's two pages (ADR-020).
    @State private var spread: Spread?
    /// Where the top bar ends on screen: a globe on the top page stands below it.
    @State private var topBarBottom = 0.0
    /// Where the country card starts on screen, and the window's size: on a short screen the
    /// globe stands above the card.
    @State private var cardTop: Double?
    @State private var windowSize = CGSize.zero

    /// The one split every counter on this screen uses.
    private var visitedPlaces: VisitedPlaces {
        places.split(world.visitedCodes)
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
                // VoiceOver can't spin or tap the globe; everything it does is a list away.
                .accessibilityAction(named: Text("Search countries")) { setSearching(true) }
                .accessibilityAction(named: Text("Visited countries")) { setShowingVisited(true) }
                .accessibilityAction(named: Text("Statistics")) { setShowingStats(true) }
                // Under the statistics the globe steps back and dims, still in view; under a
                // milestone it only dims (the milestone's own dark veil frames it).
                .scaleEffect(isShowingStats && !reduceMotion ? 0.8 : 1)
                .opacity(isGlobeHidden ? 0 : isGlobeBehind ? 0.45 : 1)
                .accessibilityHidden(isShowingStats)
                .accessibilityValue(Text("\(visitedPlaces.countries.count) countries"))

            if let zoomRailSpan {
                // Over the globe, under the bar and the card: they keep their touches.
                ZoomRail(controller: controller, span: zoomRailSpan)
                    .transition(.opacity)
            }

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
                        .onScreenEdge(.bottom) { topBarBottom = $0 }
                        .transition(.opacity)
                    }

                    // The bar spans the screen; the rest keeps to the left page of an open Duo.
                    VStack(spacing: 0) {
                        if isShowingRestored, !isSearching, !isShowingStats, !isShowingVisited, addingCityTo == nil {
                            RestoredBanner(onDismiss: hideRestored)
                                .frame(maxWidth: Metrics.panelWidth)
                                .padding(.top, 12)
                                // Drops out of the counter it's filling, as the list does.
                                .transition(reduceMotion ? .opacity : .scale(scale: 0.5, anchor: counterAnchor).combined(with: .opacity))
                        }

                        if isShowingVisited {
                            VisitedCountriesPanel(
                                places: VisitedPlaces(
                                    countries: RegionDisplay.sortedByName(visitedPlaces.countries),
                                    territories: RegionDisplay.sortedByName(visitedPlaces.territories)
                                ),
                                onPick: flyTo
                            )
                                .frame(maxWidth: Metrics.panelWidth)
                                .padding(.top, 12)
                                // Drops out of the counter above it.
                                .transition(reduceMotion ? .opacity : .scale(scale: 0.5, anchor: counterAnchor).combined(with: .opacity))
                        }

                        Spacer(minLength: 0)

                        if !isSearching, !isShowingVisited, !isShowingStats, addingCityTo == nil, let selected {
                            CountryPeekCard(
                                code: selected,
                                isVisited: world.isVisited(selected),
                                // Newest first: a city just added is the first chip.
                                cities: world.cities(in: selected).reversed().map(shownName),
                                highlightedCity: highlightedCity,
                                visitedSince: awaitingLanding == selected ? nil : world.firstVisits[selected],
                                stampInk: controller.visitedColor(of: selected).map(Color.init(components:)) ?? Palette.accentLight,
                                stampSlams: justMarked == selected,
                                isCovered: shownMilestone != nil,
                                isConfirmingUnmark: Binding(
                                    get: { confirmingUnmark == selected },
                                    set: { if !$0 { confirmingUnmark = nil } }
                                ),
                                onConfirmUnmark: { unmark(selected) },
                                onToggleVisited: { toggleVisited(selected) },
                                onFindNext: { setSearching(true) },
                                onAddCity: { setAddingCity(selected) },
                                onSelectCity: selectCity,
                                onRemoveCity: removeCity,
                                onClose: { select(nil) }
                            )
                            .frame(maxWidth: Metrics.panelWidth)
                            .onScreenEdge(.top) { cardTop = $0 }
                            .id(selected)
                            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .padding(panelInsets)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .ignoresSafeArea(.keyboard)
                .transition(.opacity)
            }

            ZStack {
                if showsDeskPlaque, let spread {
                    DeskPlaque(
                        stats: StatsCalculator.stats(visited: world.visitedCodes, catalog: places, cities: world.cities.count),
                        onOpen: { setShowingStats(true) }
                    )
                    .frame(maxWidth: Metrics.panelWidth)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 16)
                    .padding(spread.insets(confiningTo: spread.secondPage))
                    // Rises onto the stand as the screen bends.
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? Motion.smooth : Motion.bouncy, value: showsDeskPlaque)

            ConfettiView(bursts: confetti)

            if isSearching, let searchIndex {
                SearchPanel(
                    index: searchIndex,
                    visited: world.visitedCodes,
                    knownCountries: Set(controller.countryCodes),
                    cityCatalog: cityCatalog ?? .bundled,
                    world: controller.world,
                    initialQuery: initialSearchQuery,
                    initialMode: initialSearchMode,
                    isFieldFocused: $isSearchFieldFocused,
                    onPickCountry: flyTo,
                    onPickCity: addCity,
                    onCancel: { setSearching(false) }
                )
                .frame(maxWidth: Metrics.panelWidth)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .padding(panelInsets)
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }

            if let code = addingCityTo {
                CitySearchPanel(
                    countryCode: code,
                    bounds: controller.world?.countries.first { $0.code == code }?.bounds,
                    initialQuery: initialCityQuery,
                    knownCountries: Set(controller.countryCodes),
                    catalog: cityCatalog ?? .bundled,
                    world: controller.world,
                    isFieldFocused: $isSearchFieldFocused,
                    onPick: addCity,
                    onCancel: { setAddingCity(nil) }
                )
                .frame(maxWidth: Metrics.panelWidth)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .padding(panelInsets)
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }

            statistics

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
            if showsFrameRate {
                FrameRateBadge(framesPerSecond: controller.framesPerSecond, demand: controller.isPaused ? .none : controller.frameDemand)
            }
            #endif
        }
        .readsSpread($spread)
        .onGeometryChange(for: CGSize.self) { proxy in
            let frame = proxy.frame(in: .global)
            return CGSize(width: frame.maxX + proxy.safeAreaInsets.trailing, height: frame.maxY + proxy.safeAreaInsets.bottom)
        } action: { windowSize = $0 }
        .environment(\.spread, spread)
        .onChange(of: globeStage, initial: true) { _, stage in
            controller.setStage(stage)
        }
        .environment(\.countryCatalog, places)
        .sensoryFeedback(Haptics.select, trigger: selected) { _, new in new != nil }
        .sensoryFeedback(Haptics.markVisited, trigger: celebrations)
        .sensoryFeedback(Haptics.cityLanded, trigger: landings)
        #if DEBUG
        .sensoryFeedback(Haptics.markVisited, trigger: worldviewSwitches)
        #endif
        .sensoryFeedback(Haptics.select, trigger: picks)
        .sensoryFeedback(Haptics.restored, trigger: restores)
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
                if !marksCountry, let city = world.cities.first(where: { $0.id == id }) {
                    announce("\(city.name) added")
                }
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
        .onChange(of: world.lastSync) { _, change in
            if let change { syncArrived(change) }
        }
        .task(id: restores) {
            guard restores > 0 else { return }
            // Long enough to read while the countries sweep in.
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            hideRestored()
        }
        .onChange(of: world.cities, initial: true) { _, cities in
            updateCityMarkers()
            if let highlightedCity, !cities.contains(where: { $0.id == highlightedCity }) {
                self.highlightedCity = nil
            }
        }
        .task {
            // A few megabytes to decompress, off the main thread; search uses it too, so it's
            // ready before anyone types.
            await refreshCityCatalog()
        }
        .onChange(of: controller.isReady) { _, isReady in
            guard isReady else { return }
            // The globe starts flying in now, not at launch: loading can take a moment.
            if onboarding == .welcome, !reduceMotion { warpStart = .now }
            worldDidLoad()
        }
    }

    // MARK: - Worldview

    /// Everything made from the globe's outlines, made again for the borders it now draws:
    /// the places counted, the continent maps, the search, the cities on disputed land.
    private func worldDidLoad() {
        guard let geometry = controller.world else { return }
        let catalog = CountryCatalog.bundled.limited(to: geometry.countries.map(\.code))
        places = catalog
        searchIndex = nil
        // Saved before (or in another App Store region): a city on disputed land goes with it.
        world.reassignCities { geometry.owner(at: $0) }
        Task { continentMaps = await ContinentMaps.build(world: geometry, catalog: catalog) }
        Task { await refreshCityCatalog() }
    }

    /// The bundled cities with disputed land given to its owner in the globe's worldview.
    private func refreshCityCatalog() async {
        let geometry = controller.world
        let worldview = geometry.map { _ in controller.worldview }
        let catalog = await Task.detached(priority: .utility) {
            geometry.map { geometry in CityCatalog.bundled.relabeled { geometry.owner(at: $0) } } ?? CityCatalog.bundled
        }.value
        // Another world came in meanwhile: its own refresh is on the way.
        guard controller.world.map({ _ in controller.worldview }) == worldview else { return }
        cityCatalog = catalog
        updateCityMarkers()
    }

    #if DEBUG
    /// The developer zone forced a worldview (`nil`: back to the storefront's). The statistics
    /// close, and the globe flies to where the borders change and redraws them there.
    private func forceWorldview(_ forced: Worldview?) {
        if let forced {
            UserDefaults.standard.set(forced.rawValue, forKey: WorldviewSource.overrideKey)
        } else {
            UserDefaults.standard.removeObject(forKey: WorldviewSource.overrideKey)
        }
        setShowingStats(false)
        select(nil)
        Task {
            let target = await WorldviewSource.resolve()
            guard target != controller.worldview else { return }
            await controller.switchWorldview(target)
            worldDidLoad()
            worldviewSwitches += 1
        }
    }

    /// The developer zone wiped everything: the first launch again, from the arrival on.
    private func resetProgress() {
        world.resetAll()
        hasOnboarded = false
        AddCityChip.forgetHint()
        setShowingStats(false)
        select(nil)
        justMarked = nil
        milestoneQueue = []
        shownMilestone = nil
        controller.frame(offset: 0, zoom: 1)
        controller.replayArrival()
        if !reduceMotion { warpStart = .now }
        withAnimation(Motion.smooth) { onboarding = .welcome }
    }
    #endif

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

    // MARK: - iCloud

    /// The user's other devices marked or unmarked something, and iCloud brought it here:
    /// the globe shows it happening. A world arriving on an empty globe, or during the
    /// introduction, is a restore (a new device, or the app installed again): the
    /// introduction makes way, and a banner says where it all came from.
    private func syncArrived(_ change: SyncedChange) {
        let isRestore = !change.marked.isEmpty && (change.isRestore || onboarding != nil)
        if isRestore, onboarding != nil { finishOnboarding() }
        change.unmarked.forEach { controller.drain($0) }
        controller.fillIn(change.marked, after: isRestore ? GlobeTuning.restoreFillDelay : 0)
        guard isRestore else { return }
        restores += 1
        announce("Welcome back. Your countries and cities are back from iCloud.")
        withAnimation(Motion.bouncy) { isShowingRestored = true }
    }

    private func hideRestored() {
        withAnimation(Motion.smooth) { isShowingRestored = false }
    }

    private var isGlobeBehind: Bool {
        isShowingStats || shownMilestone != nil
    }

    /// The stretch of the right edge the zoom rail may take, in window points: below the bar,
    /// above the country card, and on an iPhone Duo stood on a table above the fold (held like
    /// a book, the card is on the other page). `nil` while something covers the globe.
    private var zoomRailSpan: ClosedRange<Double>? {
        guard controller.isReady, onboarding == nil, !isSearching, !isShowingVisited, addingCityTo == nil,
              !isShowingStats, story == nil, shownMilestone == nil, !isGlobeHidden
        else { return nil }
        var bottom = windowSize.height
        if let spread, spread.layout == .stacked { bottom = spread.firstPage.maxY }
        if selected != nil, let cardTop, spread?.layout != .sideBySide { bottom = min(bottom, cardTop) }
        let top = topBarBottom + 12
        bottom -= 12
        return top < bottom ? top...bottom : nil
    }

    // MARK: - iPhone Duo

    /// An open iPhone Duo held like a book: the bars, lists and cards keep to the left page,
    /// clear of the fold, as on the phone folded.
    private var panelInsets: EdgeInsets {
        guard let spread, spread.layout == .sideBySide else { return EdgeInsets() }
        return spread.insets(confiningTo: spread.firstPage)
    }

    /// Where the lists that drop out of the counter grow from: the counter sits in the middle
    /// of the bar, or in the left page's top corner on an open Duo held like a book.
    private var counterAnchor: UnitPoint {
        spread?.layout == .sideBySide ? .topLeading : .top
    }

    /// A short screen (iPhone Duo folded, iPhone SE): the country card takes over a third of
    /// it, and a country framed in the middle would sit half under the card. The globe moves up
    /// into the room between the bar and the card instead, keeping its size: a stage as big as
    /// the window, centred on that room.
    private var roomAboveCard: CGRect? {
        guard selected != nil, !isSearching, !isShowingVisited, addingCityTo == nil,
              let cardTop, windowSize.height > 0, (windowSize.height - cardTop) / windowSize.height > 1.0 / 3
        else { return nil }
        let middle = (topBarBottom + cardTop) / 2
        return CGRect(origin: CGPoint(x: 0, y: middle - windowSize.height / 2), size: windowSize)
    }

    /// iPhone Duo half open on a table, nothing else open: a desk globe on the upper half,
    /// its plaque on the lower.
    private var showsDeskPlaque: Bool {
        guard let spread, spread.layout == .stacked, spread.isBent else { return false }
        return onboarding == nil && selected == nil && !isSearching && !isShowingVisited && addingCityTo == nil
            && !isShowingStats && story == nil && shownMilestone == nil
    }

    /// Where the globe stands. The whole screen, unless an open iPhone Duo has something on
    /// the other page (the right one held like a book; below the fold on a table, the card) or
    /// is bent at the fold: then its own page, so the fold never runs through it.
    private var globeStage: CGRect? {
        guard onboarding == nil, !isShowingStats else { return nil }
        guard let spread else { return roomAboveCard }
        let hasPanel = switch spread.layout {
        case .sideBySide: selected != nil || isSearching || isShowingVisited || addingCityTo != nil
        case .stacked: selected != nil && !isSearching && !isShowingVisited && addingCityTo == nil
        }
        guard hasPanel || spread.isBent else { return nil }
        switch spread.layout {
        case .sideBySide:
            return spread.secondPage
        case .stacked:
            // The top page under the bar.
            var page = spread.firstPage
            let top = min(page.maxY, max(page.minY, topBarBottom + 8))
            page.size.height = page.maxY - top
            page.origin.y = top
            return page
        }
    }

    /// A saved city under the name the app's language gives it: the bundled list's, so "Алматы"
    /// saved from a Russian search reads "Almaty" in English, else at least in letters the
    /// language reads ("Талгар" → "Talgar").
    private func shownName(_ city: CityPin) -> CityPin {
        let known = cityCatalog?.city(named: city.name, in: city.countryCode, latitude: city.latitude, longitude: city.longitude)
        return city.renamed(known?.name(in: Locale.preferredLanguages) ?? PlaceNames.readable(city.name))
    }

    private func updateCityMarkers() {
        controller.setCities(cityMarkers)
    }

    private var cityMarkers: [GlobeController.CityMarker] {
        world.cities.map(shownName).map { city in
            GlobeController.CityMarker(
                id: city.id,
                name: city.name,
                countryCode: city.countryCode,
                coordinate: GeoCoordinate(latitude: city.latitude, longitude: city.longitude),
                isCapital: cityCatalog?.isCapital(city) ?? false
            )
        }
    }

    // MARK: - Statistics and story

    /// The statistics, and the story to share over them.
    @ViewBuilder
    private var statistics: some View {
        if isShowingStats {
            StatisticsScreen(
                stats: StatsCalculator.stats(visited: world.visitedCodes, catalog: places, cities: world.cities.count),
                visited: world.visitedCodes,
                maps: continentMaps,
                earned: world.milestones,
                onPick: flyTo,
                onShare: world.visitedCodes.isEmpty ? nil : { shareStory() },
                onClose: { setShowingStats(false) }
            )
            #if DEBUG
            .developerZone(
                worldview: controller.worldview,
                storefront: WorldviewSource.lastStorefront,
                onWorldview: forceWorldview,
                onReset: resetProgress
            )
            #endif
            .transition(.opacity)
        }

        if let story {
            ShareStoryScreen(content: story, onClose: { withAnimation(Motion.smooth) { self.story = nil } })
                .transition(.opacity)
        }
    }

    /// Opens the story of everything visited, with the globe's own outlines and borders.
    private func shareStory() {
        guard let geometry = controller.world else { return }
        let middles = Dictionary(geometry.countries.map { ($0.code, $0.label) }, uniquingKeysWith: { first, _ in first })
        let content = StoryContent(
            places: world.visitedCodes.sorted().compactMap { code in
                middles[code].map { StoryPlan.Place(code: code, latitude: $0.latitude, longitude: $0.longitude) }
            },
            countries: Set(visitedPlaces.countries),
            stats: StatsCalculator.stats(visited: world.visitedCodes, catalog: places, cities: world.cities.count),
            cities: cityMarkers,
            world: geometry,
            worldview: controller.worldview
        )
        withAnimation(Motion.smooth) { story = content }
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
        announce("\(RegionDisplay.name(for: code)) removed from visited")
    }

    /// Said by VoiceOver: the fill, the stamp and the haptic say it to everyone else.
    private func announce(_ message: LocalizedStringResource) {
        AccessibilityNotification.Announcement(String(localized: message)).post()
    }

    /// The SwiftUI half of marking a country, after the globe's fill and ring: the haptic,
    /// confetti thrown from where the fill starts, the stamp slamming into the card.
    private func celebrateMark(_ code: String, at point: CGPoint?) {
        celebrations += 1
        justMarked = code
        queueMilestones(world.earnMilestones(), from: code)
        announce("\(RegionDisplay.name(for: code)) marked as visited")
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
        let stats = StatsCalculator.stats(visited: world.visitedCodes, catalog: places)
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
            // A mark undone right away has already taken its milestones back.
            milestoneQueue += events.filter { world.milestones[$0.milestone] != nil }
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
    /// (`-NomadedDebugTap "186,459;120,300"` taps several times, 3 s apart),
    /// `-NomadedDebugWorldview rus` draws a region's borders (`standard`, `rus`, `chn`),
    /// `-NomadedDebugSwitchWorldview rus` switches to them after the intro, as the developer
    /// zone does, `-NomadedDebugDeveloper YES` (with `-NomadedDebugStats YES`) opens that zone,
    /// `-NomadedDebugReset YES` wipes the progress after the intro, as its button does,
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
    /// types into the pick step's search; `-NomadedDebugOnboardingPicks IT,FR` goes through all of it,
    /// picking those countries, and finishes),
    /// `-NomadedDebugMark IT` flies to a country and marks it, celebration and all
    /// (`-NomadedDebugUnmarkAfter YES` unmarks it 3 s later), `-NomadedDebugMilestone countries.25`
    /// shows a milestone's celebration, `-NomadedDebugSyncMark IT,FR` has those countries
    /// arrive from "another device" 3 s in (with `-NomadedDebugOnboarding YES`: a restore),
    /// `-NomadedDebugShare YES` opens the statistics and the story to share (`-NomadedDebugShareVideo YES`:
    /// and switches it to the video).
    /// These runs use an empty in-memory store (see `NomadedApp`), so they never touch countries marked by hand.
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
        let taps = (defaults.string(forKey: "NomadedDebugTap")?.split(separator: ";") ?? [])
            .map { $0.split(separator: ",").compactMap { Double($0) } }
            .filter { $0.count == 2 }
        let fly = defaults.string(forKey: "NomadedDebugFly")
        let switchesTo = defaults.string(forKey: "NomadedDebugSwitchWorldview").flatMap(Worldview.init(rawValue:))
        let resets = defaults.bool(forKey: "NomadedDebugReset")
        let search = defaults.string(forKey: "NomadedDebugSearch")
        let showsList = defaults.bool(forKey: "NomadedDebugVisitedList")
        let showsStats = defaults.bool(forKey: "NomadedDebugStats")
        let shares = defaults.bool(forKey: "NomadedDebugShare")
        if let picks = defaults.string(forKey: "NomadedDebugOnboardingPicks"), onboarding != nil {
            walkThroughOnboarding(picking: picks.split(separator: ",").map(String.init))
        }
        if let synced = defaults.string(forKey: "NomadedDebugSyncMark") {
            Task {
                try? await Task.sleep(for: .seconds(3))
                world.simulateSync(marking: synced.split(separator: ",").map(String.init))
            }
        }
        guard !taps.isEmpty || fly != nil || switchesTo != nil || resets || search != nil || showsList || showsStats || shares || focusesCity
                || addsCityTo != nil || landsCity != nil || marks != nil || debugMilestone != nil
        else { return }
        Task {
            // Wait for the intro to settle.
            try? await Task.sleep(for: .seconds(4))
            for (index, tap) in taps.enumerated() {
                if index > 0 { try? await Task.sleep(for: .seconds(3)) }
                controller.tap(at: CGPoint(x: tap[0], y: tap[1]))
            }
            if !taps.isEmpty, defaults.bool(forKey: "NomadedDebugMarkAfterTap"), let selected {
                toggleVisited(selected)
            }
            if let fly { flyTo(fly) }
            if resets { resetProgress() }
            if let switchesTo {
                // For this run only, unlike the developer zone's switch.
                await controller.switchWorldview(switchesTo)
                worldDidLoad()
                worldviewSwitches += 1
            }
            if showsList { setShowingVisited(true) }
            if showsStats || shares { setShowingStats(true) }
            if shares { shareStory() }
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

    /// Goes through the first launch the way a person would: the welcome, a few countries
    /// picked one by one, the summary, then "Let's go!".
    private func walkThroughOnboarding(picking codes: [String]) {
        Task {
            try? await Task.sleep(for: .seconds(4))
            withAnimation(Motion.bouncy) { onboarding = .pick }
            for code in codes {
                try? await Task.sleep(for: .seconds(1))
                togglePick(code)
            }
            try? await Task.sleep(for: .seconds(2))
            withAnimation(Motion.bouncy) { onboarding = .ready }
            try? await Task.sleep(for: .seconds(3))
            finishOnboarding()
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

    @Environment(\.spread) private var spread

    var body: some View {
        Group {
            if spread?.layout == .sideBySide {
                // An open iPhone Duo held like a book: the middle of the bar is the fold, so the
                // counter moves to the left page beside the statistics, the page its list
                // drops onto, and the search keeps its corner.
                HStack(spacing: 12) {
                    statsButton
                    counter
                    Spacer(minLength: 0)
                    searchButton
                }
            } else {
                counter
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .leading) { statsButton }
                    .overlay(alignment: .trailing) { searchButton }
            }
        }
        // A bar: it stops growing at the largest regular size, and a long press shows its
        // buttons big instead (the large content viewer).
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var counter: some View {
        Button(action: onToggleVisited) {
            WorldSummaryChip(
                countries: visited.countries.count,
                territories: visited.territories.count,
                isExpanded: isShowingVisited
            )
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .contentShape(.hoverEffect, Capsule())
        }
        .buttonStyle(.pressable)
        // On an iPad keyboard Esc folds the list away again.
        .keyboardShortcut(isShowingVisited ? .cancelAction : nil)
        .accessibilityHint(isShowingVisited ? "Hides the list" : "Shows the countries you've visited")
    }

    private var statsButton: some View {
        RoundButton(title: "Statistics", systemImage: "chart.bar.fill", action: onStats)
            .disabled(!isReady)
    }

    private var searchButton: some View {
        RoundButton(title: "Search countries", systemImage: "magnifyingglass", action: onSearch)
            .keyboardShortcut("f", modifiers: .command)
            .disabled(!isReady)
    }
}

private struct RoundButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(Typography.headline)
                .frame(width: 44, height: 44)
                .glass(Circle())
                .contentShape(.hoverEffect, Circle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(title)
        .accessibilityShowsLargeContentViewer { Label(title, systemImage: systemImage) }
    }
}

/// "90 countries +10": the 195-country count the statistics use, with territories beside
/// it, so marking Greenland still visibly counts. Each new mark sends a "+1" up out of it.
private struct WorldSummaryChip: View {
    let countries: Int
    let territories: Int
    let isExpanded: Bool

    @State private var bumps: [UUID] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.5).combined(with: .opacity))
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
/// or Accessibility → Motion → Limit Frame Rate). "rest" means nothing moves and nothing is
/// drawn; "spin" is the idle spin at its own low rate. The meter only runs while the globe
/// draws at full rate, or it would keep the screen at 120 Hz by itself.
private struct FrameRateBadge: View {
    let framesPerSecond: Int
    let demand: FrameDemand
    @State private var display = DisplayRateMeter()

    var body: some View {
        Text(verbatim: text)
            .font(.system(.caption2, design: .monospaced, weight: .semibold))
            .foregroundStyle(demand != .full || framesPerSecond >= 55 ? .green : .orange)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.black.opacity(0.45), in: Capsule())
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // Under the top bar, clear of its buttons.
            .padding(.leading, 16)
            .padding(.top, 52)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onChange(of: demand == .full, initial: true) { _, isFull in
                if isFull { display.start() } else { display.stop() }
            }
            .onDisappear { display.stop() }
    }

    private var text: String {
        switch demand {
        case .full: "\(framesPerSecond) fps · display \(display.framesPerSecond)"
        case .slow: "\(framesPerSecond) fps · spin"
        case .none: "rest · 0 fps"
        }
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

#if DEBUG
// The scratch store exists in Debug only; Release builds (and archives) skip the preview.
#Preview {
    GlobeScreen()
        .environment(WorldStore.scratch())
        .preferredColorScheme(.dark)
}
#endif
