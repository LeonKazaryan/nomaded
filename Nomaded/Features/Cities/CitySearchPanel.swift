import MapKit
import SwiftUI

/// "+ City" in a country's card: a search for that country's cities only. Picking one
/// looks up where it is and hands it back; the globe then flies there.
struct CitySearchPanel: View {
    let countryCode: String
    /// Countries the globe has; a city must land on one of them.
    let knownCountries: Set<String>
    /// Owned by the screen, so every way of closing the search drops the keyboard at once.
    let isFieldFocused: FocusState<Bool>.Binding
    let onPick: (CityDraft) -> Void
    let onCancel: () -> Void

    @State private var search: CitySearch

    init(
        countryCode: String,
        bounds: GeoBounds?,
        initialQuery: String = "",
        knownCountries: Set<String>,
        catalog: CityCatalog = .bundled,
        world: WorldGeometry? = nil,
        isFieldFocused: FocusState<Bool>.Binding,
        onPick: @escaping (CityDraft) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.countryCode = countryCode
        self.knownCountries = knownCountries
        self.isFieldFocused = isFieldFocused
        self.onPick = onPick
        self.onCancel = onCancel
        let search = CitySearch(countryCode: countryCode, region: bounds.map(MKCoordinateRegion.init), catalog: catalog, world: world)
        search.query = initialQuery
        _search = State(initialValue: search)
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                SearchField(
                    placeholder: "Cities in \(RegionDisplay.name(for: countryCode))",
                    systemImage: "mappin.and.ellipse",
                    text: $search.query,
                    isFocused: isFieldFocused,
                    onSubmit: { if let first = search.results.first { pick(first) } }
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
            CityResults(search: search, hint: "Start typing a city's name", onPick: pick)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear { isFieldFocused.wrappedValue = true }
    }

    private func pick(_ result: CitySearch.Result) {
        Task {
            if let city = await search.pick(result, knownCountries: knownCountries) { onPick(city) }
        }
    }
}

extension MKCoordinateRegion {
    /// A country's box with a little margin, so border towns still come up.
    init(_ bounds: GeoBounds) {
        let latitude = Double(bounds.maxLatitude - bounds.minLatitude)
        let longitude = Double(bounds.maxLongitude - bounds.minLongitude)
        self.init(
            center: CLLocationCoordinate2D(
                latitude: Double(bounds.minLatitude) + latitude / 2,
                longitude: Double(bounds.minLongitude) + longitude / 2
            ),
            span: MKCoordinateSpan(latitudeDelta: min(180, latitude * 1.1 + 0.5), longitudeDelta: min(360, longitude * 1.1 + 0.5))
        )
    }
}
