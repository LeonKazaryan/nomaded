import MapKit
import Observation

/// Finds cities as the user types, from two sources:
/// - the bundled `CityCatalog` first: instant, offline, ranked by match and then by size,
///   so London, UK comes before London, Kentucky, with capitals marked;
/// - then MapKit for everything smaller: no API key, no location permission, only cities
///   (iOS 18's address filter).
/// Every row looks the same whatever it came from: the name, then the country's flag and
/// name in the app's language. A city Maps finds that the bundled list has ("Алматы" for
/// Almaty) shows once, as the list's; one Maps can't place in a country doesn't show.
/// Either the whole world, or strictly one country: the "+ City" button in a country's card.
/// There, an empty field already lists the country's cities, capital first, then by size.
@Observable @MainActor
final class CitySearch: NSObject {
    struct Result: Identifiable {
        fileprivate enum Source {
            case known(KnownCity)
            case maps(MapsHit, place: CompletionPlace, countryCode: String)
        }

        let id: String
        let title: String
        let subtitle: String
        let isCapital: Bool
        fileprivate let source: Source
    }

    /// One Maps suggestion as text, and the completion to look it up with (none in tests).
    struct MapsHit {
        let title: String
        let subtitle: String
        var completion: MKLocalSearchCompletion?
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
                known = country.map { catalog.cities(in: $0) } ?? []
                fromMaps = []
            } else {
                known = catalog.search(trimmed, in: country)
            }
            merge()
        }
    }

    /// The country searched in, if any.
    private let country: String?
    @ObservationIgnored private let catalog: CityCatalog
    /// Tells which country a Maps result is in, from how Maps names it.
    @ObservationIgnored private let countries: CountrySearchIndex
    /// The globe's borders: a city Maps finds on disputed land goes to the country the globe
    /// shows there, whatever Maps calls it.
    @ObservationIgnored private let world: WorldGeometry?
    @ObservationIgnored private var known: [KnownCity] = []
    @ObservationIgnored private var fromMaps: [MapsHit] = []
    @ObservationIgnored private let completer = MKLocalSearchCompleter()
    /// Held while it runs: MapKit cancels a lookup whose object goes away.
    @ObservationIgnored private var lookup: MKLocalSearch?

    /// `countryCode: nil` searches the whole world. With a country, only its cities come
    /// up, and `region` (its box) narrows what Maps looks through.
    init(
        countryCode: String? = nil,
        region: MKCoordinateRegion? = nil,
        catalog: CityCatalog = .bundled,
        world: WorldGeometry? = nil,
        countries: CountrySearchIndex = .places
    ) {
        country = countryCode
        self.catalog = catalog
        self.world = world
        self.countries = countries
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
            case .maps(let hit, let place, _):
                guard let completion = hit.completion else { throw Problem.offline }
                return try await resolve(completion, name: place.name, knownCountries: knownCountries)
            }
        } catch let problem as Problem {
            self.problem = problem
        } catch {
            problem = .offline
        }
        return nil
    }

    private func resolve(_ completion: MKLocalSearchCompletion, name: String, knownCountries: Set<String>) async throws -> CityDraft {
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
        let coordinate = GeoCoordinate(latitude: place.latitude, longitude: place.longitude)
        guard let code = world?.owner(at: coordinate) ?? place.code?.uppercased() else { throw Problem.notOnGlobe }
        if let country, code != country { throw Problem.otherCountry }
        guard knownCountries.contains(code) else { throw Problem.notOnGlobe }
        // Maps may still name a city the bundled list has differently: then it's saved the
        // list's way, so it shows in the app's language like the rest.
        if let known = catalog.city(named: name, in: code, latitude: place.latitude, longitude: place.longitude) {
            return known.draft
        }
        return CityDraft(name: name, region: place.region ?? "", countryCode: code, latitude: place.latitude, longitude: place.longitude)
    }

    fileprivate func update(_ completions: [MKLocalSearchCompletion]) {
        receive(completions.map { MapsHit(title: $0.title, subtitle: $0.subtitle, completion: $0) })
    }

    /// What Maps suggests for the current query.
    func receive(_ hits: [MapsHit]) {
        // A late answer to what was typed before the field was cleared.
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        fromMaps = hits
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

    /// The bundled cities first, then what Maps adds. A Maps city the bundled list has joins
    /// the list's rows instead; one it can't place in a country (or in the one searched) is
    /// left out, since it couldn't go on the globe anyway.
    private func merge() {
        let languages = Locale.preferredLanguages
        var cities = known
        var places: [(hit: MapsHit, place: CompletionPlace, code: String)] = []
        var seen = Set<String>()
        for hit in fromMaps {
            let place = CompletionPlace(title: hit.title, subtitle: hit.subtitle)
            guard let countryName = place.country, let code = countries.code(named: countryName),
                  country == nil || code == country
            else { continue }
            let listed = catalog.cities(named: place.name, in: code)
            if !listed.isEmpty {
                // Several of that name: the list's own results already have them, by size.
                if listed.count == 1, !cities.contains(listed[0]) { cities.append(listed[0]) }
                continue
            }
            guard seen.insert([place.name, code, place.region ?? ""].map(CityCatalog.key).joined(separator: "\u{1F}")).inserted
            else { continue }
            places.append((hit, place, code))
        }

        // Two of one name in one country say which region.
        let titles = cities.map { ($0.name(in: languages), $0.countryCode) } + places.map { ($0.place.name, $0.code) }
        var counts: [String: Int] = [:]
        for (title, code) in titles { counts[CityCatalog.key(title) + code, default: 0] += 1 }
        func isTwin(_ title: String, _ code: String) -> Bool { counts[CityCatalog.key(title) + code, default: 0] > 1 }

        results = cities.enumerated().map { index, city in
            let title = city.name(in: languages)
            return Result(
                id: "known\u{1F}\(index)\u{1F}\(city.name)",
                title: title,
                subtitle: Self.subtitle(city.countryCode, region: isTwin(title, city.countryCode) ? city.region : nil, population: city.population),
                isCapital: city.isCapital,
                source: .known(city)
            )
        } + places.map { hit, place, code in
            Result(
                id: "maps\u{1F}" + hit.title + "\u{1F}" + hit.subtitle,
                title: PlaceNames.readable(place.name),
                subtitle: Self.subtitle(code, region: isTwin(place.name, code) ? place.region : nil, population: 0),
                isCapital: false,
                source: .maps(hit, place: place, countryCode: code)
            )
        }
    }

    /// "🇰🇿 Kazakhstan · 1.2M", with the region first when it tells two cities apart.
    private static func subtitle(_ code: String, region: String?, population: Int) -> String {
        var place = RegionDisplay.name(for: code)
        if let region, !region.isEmpty { place = region + ", " + place }
        let size = population > 0 ? " · " + population.formatted(.number.notation(.compactName)) : ""
        return RegionDisplay.flag(for: code) + " " + place + size
    }
}

extension CountrySearchIndex {
    /// Every country and territory on the globe, to tell which one a Maps result is in.
    static let places = CountrySearchIndex(codes: CountryCatalog.bundled.countries.map(\.code))
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
