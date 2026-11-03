import MapKit
import Observation

/// Finds cities as the user types, with MapKit: names in the user's language, no API key,
/// no location permission. Only cities (iOS 18's address filter), and only inside the
/// country's region.
@Observable @MainActor
final class CitySearch: NSObject {
    struct Result: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        fileprivate let completion: MKLocalSearchCompletion
    }

    enum Failure: Error {
        case notFound
    }

    private(set) var results: [Result] = []
    /// The last lookup failed, most likely offline.
    private(set) var isOffline = false

    var query = "" {
        didSet { completer.queryFragment = query.trimmingCharacters(in: .whitespaces) }
    }

    /// The country being searched, the one a city goes to if Maps names another one the
    /// globe doesn't have.
    private let countryCode: String
    private let countryName: String
    @ObservationIgnored private let completer = MKLocalSearchCompleter()
    /// Held while it runs: MapKit cancels a lookup whose object goes away.
    @ObservationIgnored private var lookup: MKLocalSearch?

    init(countryCode: String, region: MKCoordinateRegion?) {
        self.countryCode = countryCode
        countryName = CountrySearchIndex.fold(RegionDisplay.name(for: countryCode))
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
        completer.addressFilter = MKAddressFilter(including: .locality)
        if let region {
            completer.region = region
            completer.regionPriority = .required
        }
    }

    /// Where the picked city actually is.
    func resolve(_ result: Result, knownCountries: Set<String>) async throws -> CityDraft {
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
                        continuation.resume(throwing: error ?? Failure.notFound)
                    }
                }
            }
        // A region's box overlaps its neighbours: Zurich can come up in Italy, and goes to
        // Switzerland. Codes the globe doesn't know stay with the country searched.
        let code = place.code?.uppercased() ?? countryCode
        return CityDraft(
            name: result.title,
            region: place.region ?? "",
            countryCode: knownCountries.contains(code) ? code : countryCode,
            latitude: place.latitude,
            longitude: place.longitude
        )
    }

    fileprivate func update(_ completions: [MKLocalSearchCompletion]) {
        isOffline = false
        let all = completions.map { completion in
            Result(id: completion.title + "\u{1F}" + completion.subtitle, title: completion.title, subtitle: completion.subtitle, completion: completion)
        }
        // The region is a box, so neighbours slip in; prefer the ones Maps places in this
        // country, but don't come up empty.
        let here = all.filter { $0.subtitle.isEmpty || CountrySearchIndex.fold($0.subtitle).contains(countryName) }
        results = here.isEmpty ? all : here
    }

    fileprivate func fail() {
        isOffline = true
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
