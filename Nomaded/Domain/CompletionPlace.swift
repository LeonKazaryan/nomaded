import Foundation

/// A city as Apple Maps' search completer words it, taken apart. Maps has no fixed shape:
/// "San Antonio, TX" over "United States", "Sancaktepe, Istanbul, Türkiye" with nothing
/// under it, "Almirante Tamandaré - PR" over "Brazil", "Almora" over "Uttarakhand, India".
struct CompletionPlace: Equatable, Sendable {
    /// The city alone, without its state or country.
    let name: String
    /// The part right before the country ("TX", "Istanbul"), if there is one.
    let region: String?
    /// The last part, as Maps names it. `nil` when Maps gave only the name.
    let country: String?

    init(title: String, subtitle: String) {
        var titleParts = Self.parts(of: title)
        var head = titleParts.isEmpty ? title : titleParts.removeFirst()
        // Brazil's style: "Almirante Tamandaré - PR".
        var shortRegion: String?
        if let dash = head.range(of: " - ") {
            shortRegion = String(head[dash.upperBound...]).trimmingCharacters(in: .whitespaces)
            head = String(head[..<dash.lowerBound])
        }
        let rest = titleParts + Self.parts(of: subtitle)
        name = head.trimmingCharacters(in: .whitespaces)
        country = rest.last
        region = rest.dropLast().last ?? shortRegion.flatMap { $0.isEmpty ? nil : $0 }
    }

    private static func parts(of text: String) -> [String] {
        text.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
