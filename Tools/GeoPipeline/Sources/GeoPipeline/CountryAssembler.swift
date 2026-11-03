/// Turns Natural Earth features into one entry per ISO country code.
/// Border policy is documented in docs/03-architecture.md (ADR-008).
enum CountryAssembler {
    /// Tiny disputed reefs with no clear owner; they add nothing visually.
    static let droppedAdm0: Set<String> = ["PGA", "SCR"]

    static func assemble(_ features: [SourceFeature]) -> [CountryInput] {
        var byCode: [String: [SourceFeature]] = [:]
        var order: [String] = []
        for feature in features where !droppedAdm0.contains(feature.adm0) {
            // Features without an ISO code (sovereign base areas, Bir Tawil…) become
            // unclaimed land: drawn on the globe, but not selectable.
            let code = feature.code == "-99" ? "" : feature.code
            if byCode[code] == nil { order.append(code) }
            byCode[code, default: []].append(feature)
        }
        return order.map { code in
            let parts = byCode[code]!
            // Several features can share a code (e.g. Georgia and its breakaway regions);
            // the label comes from the largest one.
            let main = parts.max { $0.vertexCount < $1.vertexCount }!
            return CountryInput(code: code, label: main.label, main: main, polygons: parts.flatMap(\.polygons))
        }
    }
}
