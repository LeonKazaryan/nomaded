/// Gives every country one of `slotCount` color slots so that neighbours never share one.
/// The app maps slots to palette colors: candy colors once visited, land shades before.
enum ColorAssigner {
    static func assign(_ countries: [CountryInput], slotCount: Int) -> [Int] {
        let neighbours = adjacency(countries)

        // Smallest-last ordering: repeatedly set aside the country with the fewest remaining
        // neighbours, then color in reverse. Maps like this one need far fewer than six colors.
        var remaining = Set(countries.indices)
        var degree = neighbours.map(\.count)
        var order: [Int] = []
        while let next = remaining.min(by: { degree[$0] != degree[$1] ? degree[$0] < degree[$1] : $0 < $1 }) {
            remaining.remove(next)
            order.append(next)
            for n in neighbours[next] where remaining.contains(n) { degree[n] -= 1 }
        }

        var slots = [Int](repeating: -1, count: countries.count)
        for index in order.reversed() {
            let taken = Set(neighbours[index].map { slots[$0] })
            // Start from a hash of the code so colors don't all cluster on slot 0.
            let preferred = Int(stableHash(countries[index].code) % UInt32(slotCount))
            slots[index] = (0..<slotCount).map { (preferred + $0) % slotCount }.first { !taken.contains($0) } ?? preferred
        }
        return slots
    }

    /// Countries that share at least one border point are neighbours.
    private static func adjacency(_ countries: [CountryInput]) -> [Set<Int>] {
        var owners: [GeoPoint: Set<Int>] = [:]
        for (index, country) in countries.enumerated() where !country.code.isEmpty {
            for polygon in country.polygons {
                for ring in polygon.rings {
                    for point in ring { owners[point, default: []].insert(index) }
                }
            }
        }
        var neighbours = [Set<Int>](repeating: [], count: countries.count)
        for group in owners.values where group.count > 1 {
            for index in group { neighbours[index].formUnion(group.subtracting([index])) }
        }
        return neighbours
    }

    /// FNV-1a, stable across runs.
    private static func stableHash(_ text: String) -> UInt32 {
        text.unicodeScalars.reduce(2_166_136_261) { ($0 ^ $1.value) &* 16_777_619 }
    }
}
