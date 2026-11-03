import MapKit
import Observation

/// Finds cities as the user types, with MapKit: names in the user's language, no API key,
/// no location permission, only cities (iOS 18's address filter). Either the whole world,
/// or strictly one country: the "+ City" button in a country's card.
@Observable @MainActor
final class CitySearch: NSObject {
    struct Result: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        fileprivate let completion: MKLocalSearchCompletion
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
            completer.queryFragment = query.trimmingCharacters(in: .whitespaces)
            if query.trimmingCharacters(in: .whitespaces).isEmpty { results = [] }
        }
    }

    /// The country searched in, if any: its code and its name folded for matching.
    private let country: (code: String, name: String)?
    @ObservationIgnored private let completer = MKLocalSearchCompleter()
    /// Held while it runs: MapKit cancels a lookup whose object goes away.
    @ObservationIgnored private var lookup: MKLocalSearch?

    /// `countryCode: nil` searches the whole world. With a country, only its cities come
    /// up, and `region` (its box) narrows what Maps looks through.
    init(countryCode: String? = nil, region: MKCoordinateRegion? = nil) {
        country = countryCode.map { ($0, CountrySearchIndex.fold(RegionDisplay.name(for: $0))) }
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
            return try await resolve(result, knownCountries: knownCountries)
        } catch let problem as Problem {
            self.problem = problem
        } catch {
            problem = .offline
        }
        return nil
    }

    private func resolve(_ result: Result, knownCountries: Set<String>) async throws -> CityDraft {
        let lookup = MKLocalSearch(request: MKLocalSearch.Request(completion: result.completion))
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
        return CityDraft(name: result.title, region: place.region ?? "", countryCode: code, latitude: place.latitude, longitude: place.longitude)
    }

    fileprivate func update(_ completions: [MKLocalSearchCompletion]) {
        let all = completions.map { completion in
            Result(id: completion.title + "\u{1F}" + completion.subtitle, title: completion.title, subtitle: completion.subtitle, completion: completion)
        }
        // A country's region is a box, so its neighbours' towns slip in. Maps names the
        // country in the subtitle ("Lazio, Italy"); keep only those.
        guard let country else {
            results = all
            return
        }
        results = all.filter { CountrySearchIndex.fold($0.subtitle).contains(country.name) }
    }

    fileprivate func fail() {
        problem = .offline
        results = []
    }
}

extension CitySearch: MKLocalSearchCompleterDelegate {
    // MapKit calls these on the main thread. There's one completer, ours, so read it
    // rather than send the argument across.
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        MainActor.assumeIsolated { update(self.completer.results) }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: any Error) {
        MainActor.assumeIsolated { fail() }
    }
}
