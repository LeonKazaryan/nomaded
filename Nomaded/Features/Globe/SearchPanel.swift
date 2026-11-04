import SwiftUI

/// The main search over the globe: a field, a Countries / Cities switch, and the matches in
/// a glass card. A country flies the globe there; a city is added there (marking its
/// country) and lands. What's typed carries over when switching.
struct SearchPanel: View {
    enum Mode: Hashable {
        case countries, cities
    }

    let index: CountrySearchIndex
    let visited: Set<String>
    /// Countries the globe has; a city must land on one of them.
    let knownCountries: Set<String>
    /// Owned by the screen, so every way of closing the search drops the keyboard at once.
    let isFieldFocused: FocusState<Bool>.Binding
    let onPickCountry: (String) -> Void
    let onPickCity: (CityDraft) -> Void
    let onCancel: () -> Void

    @State private var mode: Mode
    @State private var query: String
    /// The whole world's cities, for the Cities tab.
    @State private var cities: CitySearch
    @ScaledMetric(relativeTo: .body) private var rowHeight = 56
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        index: CountrySearchIndex,
        visited: Set<String>,
        knownCountries: Set<String>,
        cityCatalog: CityCatalog = .bundled,
        world: WorldGeometry? = nil,
        initialQuery: String = "",
        initialMode: Mode = .countries,
        isFieldFocused: FocusState<Bool>.Binding,
        onPickCountry: @escaping (String) -> Void,
        onPickCity: @escaping (CityDraft) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.index = index
        self.visited = visited
        self.knownCountries = knownCountries
        self.isFieldFocused = isFieldFocused
        self.onPickCountry = onPickCountry
        self.onPickCity = onPickCity
        self.onCancel = onCancel
        _query = State(initialValue: initialQuery)
        _mode = State(initialValue: initialMode)
        _cities = State(initialValue: CitySearch(catalog: cityCatalog, world: world))
    }

    var body: some View {
        let countries = index.results(for: query)

        VStack(spacing: 12) {
            HStack(spacing: 12) {
                SearchField(
                    placeholder: mode == .countries ? "Search countries" : "Search cities",
                    systemImage: mode == .countries ? "magnifyingglass" : "mappin.and.ellipse",
                    text: $query,
                    isFocused: isFieldFocused,
                    onSubmit: { submit(firstCountry: countries.first) }
                )
                Button("Cancel", action: onCancel)
                    .font(Typography.label)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(minHeight: 44)
                    .buttonStyle(.pressable)
            }
            // Bars stop growing at the largest regular size.
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)

            PillPicker(
                options: [
                    .init(id: .countries, title: "Countries"),
                    .init(id: .cities, title: "Cities"),
                ],
                selection: $mode
            )
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)

            Group {
                switch mode {
                case .countries:
                    countryResults(countries)
                case .cities:
                    CityResults(search: cities, hint: "Start typing a city's name", onPick: pick)
                }
            }
            .id(mode)
            .transition(reduceMotion ? AnyTransition.opacity : AnyTransition(.blurReplace))
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear { isFieldFocused.wrappedValue = true }
        .onChange(of: query, initial: true) { _, query in
            if mode == .cities { cities.query = query }
        }
        .onChange(of: mode) { _, mode in
            if mode == .cities { cities.query = query }
        }
    }

    @ViewBuilder
    private func countryResults(_ countries: [String]) -> some View {
        if countries.isEmpty {
            Text("No countries found")
                .font(Typography.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: rowHeight)
                .glassCard(cornerRadius: 24)
        } else {
            CountryList(codes: countries, marked: visited, onPick: onPickCountry)
                .scrollDismissesKeyboard(.interactively)
        }
    }

    private func submit(firstCountry: String?) {
        switch mode {
        case .countries:
            if let firstCountry { onPickCountry(firstCountry) }
        case .cities:
            if let first = cities.results.first { pick(first) }
        }
    }

    private func pick(_ result: CitySearch.Result) {
        Task {
            if let city = await cities.pick(result, knownCountries: knownCountries) { onPickCity(city) }
        }
    }
}

#Preview {
    @Previewable @FocusState var isFocused: Bool
    ZStack {
        SpaceBackground()
        SearchPanel(
            index: CountrySearchIndex(codes: ["IT", "IS", "IN", "ID", "IE", "IL", "KZ"]),
            visited: ["IT"],
            knownCountries: ["IT", "IS", "IN", "ID", "IE", "IL", "KZ"],
            initialQuery: "I",
            isFieldFocused: $isFocused,
            onPickCountry: { _ in },
            onPickCity: { _ in },
            onCancel: {}
        )
        .padding(16)
    }
    .preferredColorScheme(.dark)
}
