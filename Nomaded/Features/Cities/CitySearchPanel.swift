import MapKit
import SwiftUI

/// Floating search for a city in one country: a field on top, matches in a glass card.
/// Picking one looks up where it is and hands it back; the globe then flies there.
struct CitySearchPanel: View {
    let countryCode: String
    /// Countries the globe has, so a city found across a border lands on one of them.
    let knownCountries: Set<String>
    /// Owned by the screen, so every way of closing the search drops the keyboard at once.
    let isFieldFocused: FocusState<Bool>.Binding
    let onPick: (CityDraft) -> Void
    let onCancel: () -> Void

    @State private var search: CitySearch
    /// The row being looked up.
    @State private var resolving: String?
    @State private var failedToResolve = false
    @ScaledMetric(relativeTo: .body) private var rowHeight = 58

    init(
        countryCode: String,
        bounds: GeoBounds?,
        initialQuery: String = "",
        knownCountries: Set<String>,
        isFieldFocused: FocusState<Bool>.Binding,
        onPick: @escaping (CityDraft) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.countryCode = countryCode
        self.knownCountries = knownCountries
        self.isFieldFocused = isFieldFocused
        self.onPick = onPick
        self.onCancel = onCancel
        let search = CitySearch(countryCode: countryCode, region: bounds.map(MKCoordinateRegion.init))
        search.query = initialQuery
        _search = State(initialValue: search)
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                field
                Button("Cancel", action: onCancel)
                    .font(Typography.label)
                    .foregroundStyle(.primary)
                    .frame(minHeight: 44)
                    .buttonStyle(.pressable)
            }

            if let note {
                Text(note)
                    .font(Typography.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: rowHeight)
                    .padding(.horizontal, 16)
                    .glassCard(cornerRadius: 24)
                    .transition(.opacity)
            } else {
                results
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .animation(Motion.snappy, value: note == nil)
        .onAppear { isFieldFocused.wrappedValue = true }
        .onChange(of: search.query) { failedToResolve = false }
    }

    /// What to say instead of results, if anything.
    private var note: LocalizedStringKey? {
        if failedToResolve || search.isOffline { return "Can't reach Maps. Check the connection and try again." }
        if search.query.trimmingCharacters(in: .whitespaces).isEmpty { return "Start typing a city's name" }
        if search.results.isEmpty { return "No cities found" }
        return nil
    }

    private var field: some View {
        HStack(spacing: 10) {
            Image(systemName: "mappin.and.ellipse")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Cities in \(RegionDisplay.name(for: countryCode))", text: $search.query)
                .focused(isFieldFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
                .submitLabel(.search)
                .onSubmit {
                    if let first = search.results.first { pick(first) }
                }
            if !search.query.isEmpty {
                Button {
                    search.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Clear")
                .transition(.scale.combined(with: .opacity))
            }
        }
        .font(Typography.body)
        .padding(.leading, 16)
        .padding(.trailing, search.query.isEmpty ? 16 : 0)
        .frame(minHeight: 48)
        .glass(Capsule())
        .animation(Motion.snappy, value: search.query.isEmpty)
    }

    private var results: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(search.results) { result in
                    Button {
                        pick(result)
                    } label: {
                        row(result)
                    }
                    .buttonStyle(.pressable)
                    .disabled(resolving != nil)
                }
            }
            .padding(.vertical, 6)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: CGFloat(search.results.count) * rowHeight + 12)
        .glassCard(cornerRadius: 24)
    }

    private func row(_ result: CitySearch.Result) -> some View {
        HStack(spacing: 14) {
            Group {
                if resolving == result.id {
                    ProgressView()
                } else {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Palette.accentLight)
                }
            }
            .frame(width: 28)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: result.title)
                    .font(Typography.body)
                    .foregroundStyle(.primary)
                if !result.subtitle.isEmpty {
                    Text(verbatim: result.subtitle)
                        .font(Typography.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .frame(minHeight: rowHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func pick(_ result: CitySearch.Result) {
        guard resolving == nil else { return }
        resolving = result.id
        failedToResolve = false
        Task {
            defer { resolving = nil }
            do {
                onPick(try await search.resolve(result, knownCountries: knownCountries))
            } catch {
                failedToResolve = true
            }
        }
    }
}

private extension MKCoordinateRegion {
    /// The country's box with a little margin, so border towns still come up.
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
