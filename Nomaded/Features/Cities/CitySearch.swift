import MapKit
import Observation

/// Finds cities as the user types, from two sources:
/// - the bundled `CityCatalog` first: instant, offline, ranked by match and then by size,
///   so London, UK comes before London, Kentucky, with capitals marked;
/// - then MapKit for everything smaller: names in the user's language, no API key, no
///   location permission, only cities (iOS 18's address filter), minus the ones above.
/// Either the whole world, or strictly one country: the "+ City" button in a country's card.
/// There, an empty field already lists the country's cities, capital first, then by size.
@Observable @MainActor
final class CitySearch: NSObject {
    struct Result: Identifiable {
        fileprivate enum Source {
            case known(KnownCity)
            case maps(MKLocalSearchCompletion)
        }

        let id: String
        let title: String
        let subtitle: String
        let isCapital: Bool
        fileprivate let source: Source
    }

    /// Why there are no results to show.
    enum Problem: Error {
        /// Maps didn't answer, most likely offline.
        case offline
        /// The picked city turned out to be across the border of the country searched.
        case otherCountry
        /// The picked city is somewhere the globe has no country for.
        case notOnGlobe
    }

    private(set) var results: [Result] = []
    private(set) var problem: Problem?
    /// The row being looked up.
    private(set) var resolving: String?

    var query = "" {
        didSet {
            problem = nil
            let trimmed = query.trimmingCharacters(in: .whitespaces)
            completer.queryFragment = trimmed
            if trimmed.isEmpty {
                known = country.map { catalog.cities(in: $0.code) } ?? []
                fromMaps = []
            } else {
                known = catalog.search(trimmed, in: country?.code)
            }
            merge()
        }
    }

    /// The country searched in, if any: its code and its name folded for matching.
    private let country: (code: String, name: String)?
    @ObservationIgnored private let catalog: CityCatalog
    @ObservationIgnored private var known: [KnownCity] = []
    @ObservationIgnored private var fromMaps: [MKLocalSearchCompletion] = []
    @ObservationIgnored private let completer = MKLocalSearchCompleter()
    /// Held while it runs: MapKit cancels a lookup whose object goes away.
    @ObservationIgnored private var lookup: MKLocalSearch?

    /// `countryCode: nil` searches the whole world. With a country, only its cities come
    /// up, and `region` (its box) narrows what Maps looks through.
    init(countryCode: String? = nil, region: MKCoordinateRegion? = nil, catalog: CityCatalog = .bundled) {
        country = countryCode.map { ($0, CountrySearchIndex.fold(RegionDisplay.name(for: $0))) }
        self.catalog = catalog
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
        completer.addressFilter = MKAddressFilter(including: .locality)
        if let region {
            completer.region = region
            completer.regionPriority = .required
        }
    }

    /// Looks up where the picked city is. `nil` when it can't be added; `problem` says why.
    func pick(_ result: Result, knownCountries: Set<String>) async -> CityDraft? {
        guard resolving == nil else { return nil }
        resolving = result.id
        defer { resolving = nil }
        do {
            switch result.source {
            case .known(let city):
                guard knownCountries.contains(city.countryCode) else { throw Problem.notOnGlobe }
                return city.draft
            case .maps(let completion):
                return try await resolve(completion, title: result.title, knownCountries: knownCountries)
            }
        } catch let problem as Problem {
            self.problem = problem
        } catch {
            problem = .offline
        }
        return nil
    }

    private func resolve(_ completion: MKLocalSearchCompletion, title: String, knownCountries: Set<String>) async throws -> CityDraft {
        let lookup = MKLocalSearch(request: MKLocalSearch.Request(completion: completion))
        self.lookup = lookup
        defer { self.lookup = nil }
        // Only plain values leave MapKit's callback, which runs on the main thread.
        let place: (code: String?, region: String?, latitude: Double, longitude: Double) =
            try await withCheckedThrowingContinuation { continuation in
                lookup.start { response, error in
                    if let placemark = response?.mapItems.first?.placemark {
                        continuation.resume(returning: (
                            placemark.isoCountryCode, placemark.administrativeArea,
                            placemark.coordinate.latitude, placemark.coordinate.longitude
                        ))
                    } else {
                        continuation.resume(throwing: error ?? Problem.offline)
                    }
                }
            }
        guard let code = place.code?.uppercased() else { throw Problem.notOnGlobe }
        if let country, code != country.code { throw Problem.otherCountry }
        guard knownCountries.contains(code) else { throw Problem.notOnGlobe }
        return CityDraft(name: title, region: place.region ?? "", countryCode: code, latitude: place.latitude, longitude: place.longitude)
    }

    fileprivate func update(_ completions: [MKLocalSearchCompletion]) {
        // A late answer to what was typed before the field was cleared.
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        fromMaps = completions
        merge()
    }

    /// Maps also "fails" on an empty or abandoned query and when typing outruns it; only a
    /// network error means offline. The bundled cities still work then, so it's only worth
    /// saying when there's nothing else to show.
    fileprivate func fail(isNetworkError: Bool) {
        fromMaps = []
        merge()
        let isTyping = !query.trimmingCharacters(in: .whitespaces).isEmpty
        if isNetworkError, isTyping, results.isEmpty { problem = .offline }
    }

    /// The bundled cities first, then whatever Maps adds that they don't already cover.
    private func merge() {
        let languages = Locale.preferredLanguages
        let names = known.map { CountrySearchIndex.fold($0.name(in: languages)) }
        let knownNames = Set(known.flatMap { city in
            ([city.name, city.nameRu].compactMap { $0 } + city.aliases).map { CountrySearchIndex.fold($0) + "\u{1F}" + city.countryCode }
        })

        var merged = known.enumerated().map { index, city in
            // Two cities of one name in one country: say which region.
            let twin = names.indices.contains { $0 != index && names[$0] == names[index] && known[$0].countryCode == city.countryCode }
            var place = RegionDisplay.name(for: city.countryCode)
            if twin, let region = city.region { place = region + ", " + place }
            let size = city.population > 0 ? " · " + city.population.formatted(.number.notation(.compactName)) : ""
            return Result(
                id: "known\u{1F}\(index)\u{1F}\(city.name)",
                title: city.name(in: languages),
                subtitle: RegionDisplay.flag(for: city.countryCode) + " " + place + size,
                isCapital: city.isCapital,
                source: .known(city)
            )
        }

        for completion in fromMaps {
            let subtitle = CountrySearchIndex.fold(completion.subtitle)
            // A country's region is a box, so its neighbours' towns slip in. Maps names
            // the country in the subtitle ("Lazio, Italy"); keep only those.
            if let country, !subtitle.contains(country.name) { continue }
            // Already above, from the bundled list: same name, same country.
            let title = CountrySearchIndex.fold(completion.title.split(separator: ",").first.map(String.init) ?? completion.title)
            let isDuplicate = known.contains { city in
                knownNames.contains(title + "\u{1F}" + city.countryCode)
                    && subtitle.contains(CountrySearchIndex.fold(RegionDisplay.name(for: city.countryCode)))
            }
            if isDuplicate { continue }
            merged.append(Result(
                id: "maps\u{1F}" + completion.title + "\u{1F}" + completion.subtitle,
                title: completion.title,
                subtitle: completion.subtitle,
                isCapital: false,
                source: .maps(completion)
            ))
        }
        results = merged
    }
}

extension CitySearch: MKLocalSearchCompleterDelegate {
    // MapKit calls these on the main thread. There's one completer, ours, so read it
    // rather than send the argument across.
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        MainActor.assumeIsolated { update(self.completer.results) }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: any Error) {
        let error = error as NSError
        let isNetworkError = error.domain == NSURLErrorDomain
            || (error.domain == MKErrorDomain && error.code == MKError.Code.serverFailure.rawValue)
        MainActor.assumeIsolated { fail(isNetworkError: isNetworkError) }
    }
}
