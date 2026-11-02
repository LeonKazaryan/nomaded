import Foundation

/// User-facing name and flag for an ISO 3166-1 alpha-2 region code.
enum RegionDisplay {
    /// Apple's own localized name in the user's language ("IT" → "Italy" / "Италия").
    /// Using the system names also keeps us consistent with how Apple labels regions.
    static func name(for code: String, locale: Locale = .current) -> String {
        locale.localizedString(forRegionCode: code) ?? code
    }

    /// Emoji flag built from regional indicator symbols ("IT" → 🇮🇹).
    static func flag(for code: String) -> String {
        let regionalIndicatorA: UInt32 = 0x1F1E6
        let scalars = code.uppercased().unicodeScalars.compactMap { scalar in
            Unicode.Scalar(regionalIndicatorA + scalar.value - Unicode.Scalar("A").value)
        }
        return String(String.UnicodeScalarView(scalars))
    }
}
