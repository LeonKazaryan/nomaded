/// Which way the globe draws disputed borders: by the law of the App Store region the app
/// was downloaded from (ADR-015). Each one but the default is a small overlay the geo
/// pipeline writes next to world.nmgeo (Tools/GeoPipeline/Sources/GeoPipeline/Worldview.swift).
enum Worldview: String, CaseIterable, Sendable {
    /// Natural Earth's "USA" worldview: Crimea and Donbas in Ukraine, Taiwan on its own.
    case standard
    /// Russia's App Store: Crimea, Sevastopol and the Donetsk, Luhansk, Zaporizhzhia and
    /// Kherson regions in Russia.
    case russia = "rus"
    /// China's App Store: Taiwan and Arunachal Pradesh in China.
    case china = "chn"
    /// India's App Store: all of Jammu and Kashmir and Ladakh in India, Gilgit-Baltistan,
    /// Azad Kashmir, Aksai Chin, the Shaksgam Valley and the Siachen Glacier included.
    case india = "ind"

    /// The overlay laid over world.nmgeo.
    var overlayName: String? { self == .standard ? nil : "world-\(rawValue)" }

    /// The worldview for an App Store storefront, given as StoreKit does: ISO 3166-1 alpha-3.
    init(storefront countryCode: String) {
        switch countryCode.uppercased() {
        case "RUS": self = .russia
        case "CHN": self = .china
        case "IND": self = .india
        default: self = .standard
        }
    }

    /// Where the borders differ from the default: the globe turns there on a switch.
    var focus: GeoCoordinate? {
        switch self {
        case .standard: nil
        case .russia: GeoCoordinate(latitude: 46.8, longitude: 35.8)
        case .china: GeoCoordinate(latitude: 25.5, longitude: 108)
        case .india: GeoCoordinate(latitude: 34.5, longitude: 76.5)
        }
    }
}
