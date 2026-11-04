import Foundation
import simd

/// Natural Earth's rivers, ready for the globe: stretches joined into continuous lines,
/// cut where they cross a lake the globe shows as water, split between the countries they
/// flow through (each piece rises with its country), simplified like the coasts.
enum RiverBuilder {
    /// Natural Earth's rank. The app shows the lowest from afar and fades the rest in as
    /// you zoom; past this they would only clutter.
    static let maximumRank = 8
    /// A stretch shorter than this in another country (a river weaving along a border)
    /// stays with the country around it, so the line doesn't hop between heights.
    static let minimumRunKm = 40.0
    /// Longer segments are cut, so the line follows the globe's curve.
    static let maximumSegmentDegrees = 0.5

    struct Built: Equatable {
        /// Index into the countries, in file order.
        let country: Int
        let points: [GeoPoint]
        /// Natural Earth's rank at each point.
        let ranks: [UInt8]
        /// Its drawing weight at each point, in hundredths.
        let weights: [UInt8]
    }

    private struct Line {
        var points: [GeoPoint]
        var ranks: [UInt8]
        var weights: [UInt8]
    }

    /// - Parameters:
    ///   - countries: As drawn, after the lakes are cut and the outlines simplified.
    ///   - shores: The lakes cut out of the land.
    static func build(_ sources: [SourceRiver], countries: [CountryInput], shores: [[GeoPoint]], tolerance: Double) -> [Built] {
        let lines = sources
            .filter { ($0.kind == "River" || $0.kind == "Lake Centerline") && $0.scaleRank <= maximumRank }
            .map { source in
                Line(
                    points: source.points,
                    ranks: Array(repeating: UInt8(source.scaleRank), count: source.points.count),
                    weights: Array(repeating: UInt8(min(255, max(1, (source.strokeWeight * 100).rounded()))), count: source.points.count)
                )
            }
        let grid = CountryGrid(countries)
        return clipped(joined(lines), by: shores)
            .flatMap { split($0, by: grid) }
            .compactMap { country, line in
                let simple = densified(simplified(line, tolerance: tolerance))
                return simple.points.count >= 2 ? Built(country: country, points: simple.points, ranks: simple.ranks, weights: simple.weights) : nil
            }
    }

    // MARK: - Joining

    private struct Key: Hashable {
        let x: UInt64, y: UInt64
        init(_ p: GeoPoint) { x = p.x.bitPattern; y = p.y.bitPattern }
    }

    /// Natural Earth cuts a river wherever its rank or weight changes; the stretches meet
    /// at shared points. Chains them back together where exactly two stretches meet, so the
    /// line bends smoothly through every join and narrows gradually upstream.
    private static func joined(_ lines: [Line]) -> [Line] {
        var ends: [Key: [Int]] = [:]
        for (i, line) in lines.enumerated() {
            ends[Key(line.points[0]), default: []].append(i)
            ends[Key(line.points[line.points.count - 1]), default: []].append(i)
        }
        var used = [Bool](repeating: false, count: lines.count)

        func extend(_ line: inout Line, forward: Bool) {
            while true {
                let end = forward ? line.points[line.points.count - 1] : line.points[0]
                guard let touching = ends[Key(end)], touching.count == 2,
                      let next = touching.first(where: { !used[$0] })
                else { return }
                used[next] = true
                var other = lines[next]
                // Turn it to run on from this end.
                let startsHere = Key(other.points[0]) == Key(end)
                if forward != startsHere {
                    other.points.reverse()
                    other.ranks.reverse()
                    other.weights.reverse()
                }
                if forward {
                    let k = line.points.count - 1
                    line.ranks[k] = min(line.ranks[k], other.ranks[0])
                    line.weights[k] = max(line.weights[k], other.weights[0])
                    line.points += other.points.dropFirst()
                    line.ranks += other.ranks.dropFirst()
                    line.weights += other.weights.dropFirst()
                } else {
                    let k = other.points.count - 1
                    other.ranks[k] = min(other.ranks[k], line.ranks[0])
                    other.weights[k] = max(other.weights[k], line.weights[0])
                    line.points = other.points + line.points.dropFirst()
                    line.ranks = other.ranks + line.ranks.dropFirst()
                    line.weights = other.weights + line.weights.dropFirst()
                }
            }
        }

        var result: [Line] = []
        for i in lines.indices where !used[i] {
            used[i] = true
            var line = lines[i]
            extend(&line, forward: true)
            extend(&line, forward: false)
            result.append(line)
        }
        return result
    }

    // MARK: - Lakes

    /// Drops the parts of rivers that cross a lake shown as water: the river ends at the shore.
    private static func clipped(_ lines: [Line], by shores: [[GeoPoint]]) -> [Line] {
        // Lakes by the 1° cells their bounds cover.
        var cells: [SIMD2<Int>: [Int]] = [:]
        let boxes = shores.map(PolygonClipper.bounds)
        for (k, box) in boxes.enumerated() {
            for x in Int(floor(box.min.x))...Int(floor(box.max.x)) {
                for y in Int(floor(box.min.y))...Int(floor(box.max.y)) { cells[SIMD2(x, y), default: []].append(k) }
            }
        }

        var result: [Line] = []
        for line in lines {
            var current = Line(points: [], ranks: [], weights: [])
            func close() {
                if current.points.count >= 2 { result.append(current) }
                current = Line(points: [], ranks: [], weights: [])
            }
            func add(_ point: GeoPoint, _ i: Int) {
                if current.points.last == point { return }
                current.points.append(point)
                current.ranks.append(line.ranks[i])
                current.weights.append(line.weights[i])
            }

            for i in 0..<(line.points.count - 1) {
                let a = line.points[i], b = line.points[i + 1]
                let low = simd_min(a, b), high = simd_max(a, b)
                var nearby = Set<Int>()
                for x in Int(floor(low.x))...Int(floor(high.x)) {
                    for y in Int(floor(low.y))...Int(floor(high.y)) { nearby.formUnion(cells[SIMD2(x, y)] ?? []) }
                }
                nearby = nearby.filter { k in
                    high.x >= boxes[k].min.x && low.x <= boxes[k].max.x && high.y >= boxes[k].min.y && low.y <= boxes[k].max.y
                }
                guard !nearby.isEmpty else {
                    add(a, i)
                    add(b, i + 1)
                    continue
                }
                // Cut the segment where it crosses a shore; keep the dry pieces.
                var cuts: [(Double, GeoPoint)] = [(0, a), (1, b)]
                for k in nearby {
                    let shore = shores[k]
                    for j in shore.indices {
                        if let hit = PolygonClipper.crossing(a, b, shore[j], shore[(j + 1) % shore.count]) {
                            cuts.append((hit.alongAB, hit.point))
                        }
                    }
                }
                cuts.sort { $0.0 < $1.0 }
                for c in 0..<(cuts.count - 1) {
                    let p = cuts[c].1, q = cuts[c + 1].1
                    let middle = (p + q) / 2
                    if nearby.contains(where: { PolygonClipper.contains(shores[$0], middle) }) {
                        close()
                    } else {
                        add(p, i)
                        add(q, c + 1 == cuts.count - 1 ? i + 1 : i)
                    }
                }
            }
            close()
        }
        return result
    }

    // MARK: - Countries

    /// Which country every spot of land belongs to, on a 0.05° raster (about 5 km): fast
    /// enough to ask for every river point. Near a border it can be off by a cell, which
    /// the run smoothing in `split` absorbs anyway.
    private struct CountryGrid {
        static let step = 0.05
        static let none = UInt8.max
        let columns = Int(360 / step)
        let rows = Int(180 / step)
        private var cells: [UInt8]

        init(_ countries: [CountryInput]) {
            precondition(countries.count < Int(Self.none), "country indices must fit a byte")
            cells = [UInt8](repeating: Self.none, count: columns * rows)
            for (k, country) in countries.enumerated() {
                // Every ring at once with the even-odd rule: holes (lakes, enclaves) stay empty.
                var crossings: [Int: [Double]] = [:]
                for ring in country.polygons.flatMap(\.rings) {
                    for i in ring.indices {
                        let p = ring[i], q = ring[(i + 1) % ring.count]
                        guard p.y != q.y else { continue }
                        let low = min(p.y, q.y), high = max(p.y, q.y)
                        let first = Int(((low + 90) / Self.step - 0.5).rounded(.up))
                        let last = Int(((high + 90) / Self.step - 0.5).rounded(.down))
                        guard first <= last else { continue }
                        for row in max(0, first)...min(rows - 1, last) {
                            let y = -90 + (Double(row) + 0.5) * Self.step
                            // Half-open, so a vertex right on the row counts once.
                            guard y >= low, y < high else { continue }
                            crossings[row, default: []].append(p.x + (y - p.y) * (q.x - p.x) / (q.y - p.y))
                        }
                    }
                }
                for (row, xs) in crossings {
                    let sorted = xs.sorted()
                    for pair in stride(from: 0, to: sorted.count - 1, by: 2) {
                        let first = max(0, Int(((sorted[pair] + 180) / Self.step - 0.5).rounded(.up)))
                        let last = min(columns - 1, Int(((sorted[pair + 1] + 180) / Self.step - 0.5).rounded(.down)))
                        guard first <= last else { continue }
                        for column in first...last { cells[row * columns + column] = UInt8(k) }
                    }
                }
            }
        }

        func country(at p: GeoPoint) -> Int? {
            let row = min(rows - 1, max(0, Int((p.y + 90) / Self.step)))
            let column = min(columns - 1, max(0, Int((p.x + 180) / Self.step)))
            let value = cells[row * columns + column]
            return value == Self.none ? nil : Int(value)
        }
    }

    /// Cuts a river where it passes from one country into the next. Points off the land
    /// (a mouth past the coastline) go with their neighbours; short stretches across a
    /// border go with the country around them.
    private static func split(_ line: Line, by grid: CountryGrid) -> [(Int, Line)] {
        var owners = line.points.map(grid.country)
        // Fill the gaps from either side.
        var last: Int?
        for i in owners.indices {
            if let owner = owners[i] { last = owner } else { owners[i] = last }
        }
        last = nil
        for i in owners.indices.reversed() {
            if let owner = owners[i] { last = owner } else { owners[i] = last }
        }
        guard owners[0] != nil else { return [] }

        // Runs of one country: (country, first point, first point of the next run).
        var runs: [(country: Int, start: Int, end: Int)] = []
        for i in owners.indices {
            if let run = runs.last, run.country == owners[i]! {
                runs[runs.count - 1].end = i
            } else {
                if !runs.isEmpty { runs[runs.count - 1].end = i }
                runs.append((owners[i]!, i, i))
            }
        }
        func length(_ run: (country: Int, start: Int, end: Int)) -> Double {
            guard run.end > run.start else { return 0 }
            return (run.start..<run.end).reduce(0) { $0 + kilometres(line.points[$1], line.points[$1 + 1]) }
        }
        while runs.count > 1,
              let shortest = runs.indices.min(by: { length(runs[$0]) < length(runs[$1]) }),
              length(runs[shortest]) < minimumRunKm {
            let before = shortest > 0 ? shortest - 1 : nil
            let after = shortest < runs.count - 1 ? shortest + 1 : nil
            if let before, let after, runs[before].country == runs[after].country {
                runs[before].end = runs[after].end
                runs.removeSubrange(shortest...after)
            } else if let before, after == nil || length(runs[before]) >= length(runs[after!]) {
                runs[before].end = runs[shortest].end
                runs.remove(at: shortest)
            } else if let after {
                runs[after].start = runs[shortest].start
                runs.remove(at: shortest)
            }
        }

        return runs.map { run in
            let range = run.start...run.end
            return (run.country, Line(points: Array(line.points[range]), ranks: Array(line.ranks[range]), weights: Array(line.weights[range])))
        }
    }

    private static func kilometres(_ a: GeoPoint, _ b: GeoPoint) -> Double {
        let east = (b.x - a.x) * cos((a.y + b.y) / 2 * .pi / 180)
        return (east * east + (b.y - a.y) * (b.y - a.y)).squareRoot() * 111.32
    }

    // MARK: - Shape

    private static func simplified(_ line: Line, tolerance: Double) -> Line {
        let kept = TopologySimplifier.keptIndices(line.points, tolerance: tolerance)
        return Line(points: kept.map { line.points[$0] }, ranks: kept.map { line.ranks[$0] }, weights: kept.map { line.weights[$0] })
    }

    private static func densified(_ line: Line) -> Line {
        var result = Line(points: [], ranks: [], weights: [])
        for i in line.points.indices {
            result.points.append(line.points[i])
            result.ranks.append(line.ranks[i])
            result.weights.append(line.weights[i])
            guard i + 1 < line.points.count else { continue }
            let a = line.points[i], b = line.points[i + 1]
            let steps = Int((simd_distance(a, b) / maximumSegmentDegrees).rounded(.up))
            guard steps > 1 else { continue }
            for s in 1..<steps {
                result.points.append(a + (b - a) * (Double(s) / Double(steps)))
                result.ranks.append(line.ranks[i])
                result.weights.append(line.weights[i])
            }
        }
        return result
    }
}
