import Foundation
import simd

/// Takes the larger lakes out of the countries, so the ocean shows through them on the
/// globe and a raised country lifts its shores around them. A lake on a border is cut
/// along it, each side losing its own part. Islands in a lake stay land.
///
/// Runs on the unsimplified outlines, before `TopologySimplifier`: a lake's shore is then
/// simplified like any coast, and the points where it meets a border are shared by both
/// neighbours, so the cut stays crack-free.
enum LakeCutter {
    /// About 17 × 17 km: a few points across fully zoomed in. Smaller lakes would only
    /// speckle the land.
    static let minimumAreaKm2 = 300.0
    /// Natural Earth's rank. Lakes this important stay even when small (Lake Winnebago).
    static let alwaysKeptRank = 3
    /// Islands in a lake, and separate parts of one, smaller than this are left out.
    static let minimumIslandKm2 = 30.0
    /// Slivers left where a shore runs along a border (square degrees, about 1 km²).
    static let minimumPieceArea = 1e-4
    /// How far lake vertices are nudged, in degrees (about a millimetre), so none sits
    /// exactly on a border, which the clipper can't handle.
    static let nudge = 1e-8
    /// How far apart two lakes that touch at a point are pulled (degrees, about 10 cm).
    static let pinchGap = 1e-6

    typealias Lake = (name: String, polygon: GeoPolygon)

    struct Result {
        var countries: [CountryInput]
        /// The outer shore of every lake that took land, for the app's tap test.
        var shores: [[GeoPoint]]
        /// "Lake / country" pairs that couldn't be cut and were left as land.
        var skipped: [String]
    }

    /// The lakes worth drawing, largest first, one polygon each. Lakes that share a shore
    /// line (Lake Huron and Georgian Bay) are joined into one first.
    static func select(_ lakes: [SourceLake]) -> [Lake] {
        let kept = lakes
            .filter { lake in
                lake.scaleRank <= alwaysKeptRank || lake.polygons.reduce(0) { $0 + Sphere.areaKm2($1) } >= minimumAreaKm2
            }
            // A big lake's stray specks (a separate pond in the same feature) are dropped.
            .flatMap { lake in lake.polygons.filter { Sphere.areaKm2($0) >= minimumIslandKm2 }.map { (lake.name, $0) } }
        return separated(dissolve(withoutInnerParts(kept)))
            .map { ($0.name, nudged($0.polygon)) }
            .sorted { Sphere.areaKm2($0.1) > Sphere.areaKm2($1.1) }
    }

    /// Joins lakes that share edges. Natural Earth draws neighbouring lakes with exactly the
    /// same points along their common line, so every shared edge shows up twice, once in
    /// each direction; dropping both copies and chaining what's left gives the joined shore.
    static func dissolve(_ lakes: [Lake]) -> [Lake] {
        struct Key: Hashable {
            let x: UInt64, y: UInt64
            init(_ p: GeoPoint) { x = p.x.bitPattern; y = p.y.bitPattern }
        }
        // Outer rings counter-clockwise, islands clockwise, so shared edges run opposite ways.
        let oriented = lakes.map { lake in
            GeoPolygon(rings: lake.polygon.rings.enumerated().map { k, ring in
                isCounterClockwise(ring) == (k == 0) ? ring : Array(ring.reversed())
            })
        }

        var edgeOwner: [[Key]: Int] = [:]
        var groups = Array(lakes.indices)
        func root(_ i: Int) -> Int { groups[i] == i ? i : root(groups[i]) }
        for (i, polygon) in oriented.enumerated() {
            for ring in polygon.rings {
                for k in ring.indices {
                    let a = Key(ring[k]), b = Key(ring[(k + 1) % ring.count])
                    if let j = edgeOwner[[b, a]], root(j) != root(i) { groups[root(i)] = root(j) }
                    edgeOwner[[a, b]] = i
                }
            }
        }

        var members: [Int: [Int]] = [:]
        for i in lakes.indices { members[root(i), default: []].append(i) }
        return members.values.sorted { $0[0] < $1[0] }.flatMap { group -> [Lake] in
            guard group.count > 1 else { return [lakes[group[0]]] }
            let name = group.map { lakes[$0].name }.filter { !$0.isEmpty }.joined(separator: " + ")
            return joined(group.map { oriented[$0] }).map { (name, $0) }
        }
    }

    /// Natural Earth also draws some bays of the big lakes on their own, on top of the lake
    /// (Georgian Bay and North Channel inside Lake Huron). They add no water and, sharing its
    /// shores point for point, would trip the clipper. A lake on an island in a bigger lake stays.
    static func withoutInnerParts(_ lakes: [Lake]) -> [Lake] {
        var kept: [(lake: Lake, points: Set<Key2>, box: (min: GeoPoint, max: GeoPoint))] = []
        for lake in lakes.sorted(by: { Sphere.areaKm2($0.1) > Sphere.areaKm2($1.1) }) {
            let shore = lake.polygon.rings[0]
            let box = PolygonClipper.bounds(shore)
            let isInner = kept.contains { bigger in
                guard box.min.x >= bigger.box.min.x, box.max.x <= bigger.box.max.x,
                      box.min.y >= bigger.box.min.y, box.max.y <= bigger.box.max.y
                else { return false }
                let rings = bigger.lake.polygon.rings
                let covered = shore.filter { point in
                    bigger.points.contains(Key2(point))
                        || (PolygonClipper.contains(rings[0], point) && !rings.dropFirst().contains { PolygonClipper.contains($0, point) })
                }
                return Double(covered.count) >= Double(shore.count) * 0.98
            }
            // Its islands' shores too: North Channel runs along Manitoulin Island.
            if !isInner { kept.append((lake, Set(lake.polygon.rings.joined().map(Key2.init)), box)) }
        }
        return kept.map(\.lake)
    }

    /// Lakes can still touch at single points (a strait drawn down to one vertex), which
    /// the clipper can't handle either. Each lake's copy of such a point is pulled a hair
    /// into its own water, so no two shores touch.
    static func separated(_ lakes: [Lake]) -> [Lake] {
        var uses: [Key2: Int] = [:]
        for lake in lakes {
            for point in lake.polygon.rings.joined() { uses[Key2(point), default: 0] += 1 }
        }
        func left(_ edge: GeoPoint) -> GeoPoint {
            let normal = GeoPoint(-edge.y, edge.x)
            return simd_length(normal) > 0 ? simd_normalize(normal) : normal
        }
        return lakes.map { lake in
            let rings = lake.polygon.rings.enumerated().map { k, ring -> [GeoPoint] in
                // Outer shore counter-clockwise, islands clockwise: the water is on the left.
                let ring = isCounterClockwise(ring) == (k == 0) ? ring : Array(ring.reversed())
                return ring.indices.map { i in
                    guard uses[Key2(ring[i]), default: 0] > 1 else { return ring[i] }
                    let previous = ring[(i + ring.count - 1) % ring.count], next = ring[(i + 1) % ring.count]
                    var inward = left(ring[i] - previous) + left(next - ring[i])
                    if simd_length(inward) < 1e-9 { inward = left(next - ring[i]) }
                    return simd_length(inward) > 0 ? ring[i] + simd_normalize(inward) * pinchGap : ring[i]
                }
            }
            return (lake.name, GeoPolygon(rings: rings))
        }
    }

    /// The rings left once edges shared by two of the polygons cancel out, sorted back
    /// into outer shores and their islands.
    private static func joined(_ polygons: [GeoPolygon]) -> [GeoPolygon] {
        struct Edge: Hashable {
            let a: GeoPoint, b: GeoPoint
            func hash(into hasher: inout Hasher) {
                hasher.combine(a.x.bitPattern); hasher.combine(a.y.bitPattern)
                hasher.combine(b.x.bitPattern); hasher.combine(b.y.bitPattern)
            }
        }
        var edges: [Edge: Int] = [:]
        for ring in polygons.flatMap(\.rings) {
            for k in ring.indices {
                let edge = Edge(a: ring[k], b: ring[(k + 1) % ring.count])
                let reverse = Edge(a: edge.b, b: edge.a)
                if let count = edges[reverse], count > 0 {
                    edges[reverse] = count - 1
                } else {
                    edges[edge, default: 0] += 1
                }
            }
        }

        // In a fixed order, so the file comes out the same on every run.
        func before(_ a: GeoPoint, _ b: GeoPoint) -> Bool { (a.x, a.y) < (b.x, b.y) }
        var outgoing: [Key2: [GeoPoint]] = [:]
        for (edge, count) in edges.sorted(by: { before($0.key.a, $1.key.a) || ($0.key.a == $1.key.a && before($0.key.b, $1.key.b)) }) where count > 0 {
            for _ in 0..<count { outgoing[Key2(edge.a), default: []].append(edge.b) }
        }
        let starts = outgoing.keys.sorted { before($0.point, $1.point) }
        var rings: [[GeoPoint]] = []
        while let startKey = starts.first(where: { !(outgoing[$0]?.isEmpty ?? true) }), let first = outgoing[startKey]?.first {
            var ring = [startKey.point]
            outgoing[startKey]!.removeFirst()
            var current = first
            while Key2(current) != startKey, var nexts = outgoing[Key2(current)], !nexts.isEmpty {
                ring.append(current)
                let next = nexts.removeFirst()
                outgoing[Key2(current)] = nexts
                current = next
            }
            // Slivers where the shared line didn't quite match up are no lake.
            if ring.count >= 3, abs(Planar.signedArea(ring)) > minimumPieceArea { rings.append(ring) }
        }

        var result = rings.filter(isCounterClockwise).map { GeoPolygon(rings: [$0]) }
        for island in rings where !isCounterClockwise(island) {
            let around = result.indices
                .filter { PolygonClipper.contains(result[$0].rings[0], island[0]) }
                .min { abs(Planar.signedArea(result[$0].rings[0])) < abs(Planar.signedArea(result[$1].rings[0])) }
            if let around { result[around].rings.append(island) }
        }
        return result
    }

    private struct Key2: Hashable {
        let point: GeoPoint
        init(_ point: GeoPoint) { self.point = point }
        func hash(into hasher: inout Hasher) {
            hasher.combine(point.x.bitPattern)
            hasher.combine(point.y.bitPattern)
        }
    }

    static func cut(_ countries: [CountryInput], lakes: [Lake]) -> Result {
        var countries = countries
        var shores: [[GeoPoint]] = []
        var skipped: [String] = []
        // Cutting only takes land away, so these stay valid.
        let countryBounds = countries.map { country in
            PolygonClipper.bounds(country.polygons.flatMap { $0.rings[0] })
        }

        for lake in lakes {
            let shore = lake.polygon.rings[0]
            let box = PolygonClipper.bounds(shore)
            var tookLand = false

            for c in countries.indices where overlaps(countryBounds[c], box) {
                var polygons: [GeoPolygon] = []
                var formerOuters: [[GeoPoint]] = []
                for polygon in countries[c].polygons {
                    let outer = polygon.rings[0]
                    guard overlaps(PolygonClipper.bounds(outer), box) else {
                        polygons.append(polygon)
                        continue
                    }
                    switch cut(shore, from: outer, holes: Array(polygon.rings.dropFirst())) {
                    case .unchanged:
                        polygons.append(polygon)
                    case .cut(let pieces):
                        polygons += pieces
                        formerOuters.append(outer)
                    case .failed:
                        polygons.append(polygon)
                        let center = (box.min + box.max) / 2
                        let place = lake.name.isEmpty ? String(format: "lake at %.2f, %.2f", center.y, center.x) : lake.name
                        skipped.append("\(place) / \(countries[c].code)")
                    }
                }
                guard !formerOuters.isEmpty else { continue }

                for island in lake.polygon.rings.dropFirst() where Sphere.areaKm2(GeoPolygon(rings: [island])) >= minimumIslandKm2 {
                    for outer in formerOuters {
                        polygons += land(of: island, within: outer).map { GeoPolygon(rings: [$0]) }
                    }
                }
                countries[c].polygons = polygons
                tookLand = true
            }
            if tookLand { shores.append(shore) }
        }
        return Result(countries: countries, shores: shores, skipped: skipped)
    }

    private enum Cut {
        case unchanged
        case cut([GeoPolygon])
        case failed
    }

    /// One polygon of a country, minus the lake.
    private static func cut(_ shore: [GeoPoint], from outer: [GeoPoint], holes: [[GeoPoint]]) -> Cut {
        if holes.contains(where: { crosses($0, shore) }) { return .failed }
        // In an enclave (or an earlier lake), the water isn't this polygon's to lose. Tested
        // at a shore point the hole doesn't share: neighbouring lakes may touch at one.
        if holes.contains(where: { hole in
            let shared = Set(hole.map { [$0.x.bitPattern, $0.y.bitPattern] })
            guard let probe = shore.first(where: { !shared.contains([$0.x.bitPattern, $0.y.bitPattern]) }) else { return true }
            return PolygonClipper.contains(hole, probe)
        }) { return .unchanged }

        switch PolygonClipper.clip(outer, by: shore, .difference) {
        case .disjoint:
            return .unchanged
        case .subjectInside:
            return .cut([])
        case .clipInside:
            let hole = isCounterClockwise(shore) == isCounterClockwise(outer) ? Array(shore.reversed()) : shore
            return .cut([GeoPolygon(rings: [outer] + holes + [hole])])
        case .failed:
            return .failed
        case .rings(let pieces):
            // What's left and what went under water must add up to what there was.
            guard case .rings(let wet) = PolygonClipper.clip(outer, by: shore, .intersection) else { return .failed }
            let total = abs(Planar.signedArea(outer))
            let parts = (pieces + wet).reduce(0) { $0 + abs(Planar.signedArea($1)) }
            guard abs(parts - total) <= total * 1e-6 else { return .failed }

            var polygons = pieces
                .filter { abs(Planar.signedArea($0)) > minimumPieceArea }
                .map { GeoPolygon(rings: [$0]) }
            // Holes the polygon had (enclaves, earlier lakes) go with the piece around them.
            for hole in holes {
                if let k = polygons.firstIndex(where: { PolygonClipper.contains($0.rings[0], hole[0]) }) {
                    polygons[k].rings.append(hole)
                }
            }
            return .cut(polygons)
        }
    }

    /// The part of a lake's island inside a country's (former) outline, wound like it.
    private static func land(of island: [GeoPoint], within outer: [GeoPoint]) -> [[GeoPoint]] {
        let rings: [[GeoPoint]]
        switch PolygonClipper.clip(island, by: outer, .intersection) {
        case .subjectInside: rings = [island]
        case .clipInside: rings = [outer]
        case .rings(let pieces): rings = pieces
        case .disjoint, .failed: rings = []
        }
        return rings.map { isCounterClockwise($0) == isCounterClockwise(outer) ? $0 : Array($0.reversed()) }
    }

    private static func crosses(_ a: [GeoPoint], _ b: [GeoPoint]) -> Bool {
        let boxA = PolygonClipper.bounds(a), boxB = PolygonClipper.bounds(b)
        guard overlaps(boxA, boxB) else { return false }
        for i in a.indices {
            let p = a[i], q = a[(i + 1) % a.count]
            guard overlaps((simd_min(p, q), simd_max(p, q)), boxB) else { continue }
            for j in b.indices where PolygonClipper.crossing(p, q, b[j], b[(j + 1) % b.count]) != nil {
                return true
            }
        }
        return false
    }

    private static func overlaps(_ a: (min: GeoPoint, max: GeoPoint), _ b: (min: GeoPoint, max: GeoPoint)) -> Bool {
        a.max.x >= b.min.x && a.min.x <= b.max.x && a.max.y >= b.min.y && a.min.y <= b.max.y
    }

    private static func isCounterClockwise(_ ring: [GeoPoint]) -> Bool { Planar.signedArea(ring) > 0 }

    /// Every vertex moved a hair. The offset depends only on the point, so two lakes that
    /// touch at a vertex still touch exactly there.
    private static func nudged(_ polygon: GeoPolygon) -> GeoPolygon {
        GeoPolygon(rings: polygon.rings.map { ring in
            ring.map { point in
                var state = point.x.bitPattern ^ (point.y.bitPattern &* 0x9E37_79B9_7F4A_7C15)
                func next() -> Double {
                    // SplitMix64.
                    state &+= 0x9E37_79B9_7F4A_7C15
                    var z = state
                    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
                    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
                    z ^= z >> 31
                    return Double(z >> 11) / Double(1 << 53) * 2 - 1
                }
                return point + GeoPoint(next(), next()) * nudge
            }
        })
    }
}
