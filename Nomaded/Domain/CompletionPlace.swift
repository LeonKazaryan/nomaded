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
        name = Self.withoutKind(head.trimmingCharacters(in: .whitespaces))
        country = rest.last
        region = rest.dropLast().last ?? shortRegion.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Russian Maps put the kind of place first: "село Боровое", "посёлок Боровое". The
    /// name is the rest.
    private static let kinds = [
        "посёлок городского типа", "поселок городского типа", "рабочий посёлок", "рабочий поселок",
        "село", "деревня", "посёлок", "поселок", "пгт", "хутор", "станица", "аул", "город", "местечко",
    ]

    private static func withoutKind(_ name: String) -> String {
        for kind in kinds {
            guard name.count > kind.count + 1,
                  name.lowercased().hasPrefix(kind + " ")
            else { continue }
            return String(name.dropFirst(kind.count + 1))
        }
        return name
    }

    private static func parts(of text: String) -> [String] {
        text.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
