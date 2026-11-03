import simd

/// Boolean operations on two simple rings in lon/lat space (Greiner–Hormann). Enough for
/// cutting lakes out of countries: neither ring may touch the other exactly, which
/// `LakeCutter` guarantees by nudging lake vertices a hair off any border.
enum PolygonClipper {
    enum Operation {
        /// The subject with the clip ring taken out.
        case difference
        /// Where the two overlap.
        case intersection
    }

    enum Result {
        /// The rings don't overlap.
        case disjoint
        /// The subject lies entirely inside the clip ring.
        case subjectInside
        /// The clip ring lies entirely inside the subject.
        case clipInside
        /// The boundaries cross; these are the resulting outer rings, wound like the subject.
        case rings([[GeoPoint]])
        /// The walk didn't close up: numerically degenerate input.
        case failed
    }

    static func clip(_ subject: [GeoPoint], by clip: [GeoPoint], _ operation: Operation) -> Result {
        var graph = Graph(subject: subject, clip: clip)
        guard graph.hasCrossings else {
            if contains(clip, subject[0]) { return .subjectInside }
            if contains(subject, clip[0]) { return .clipInside }
            return .disjoint
        }
        graph.markEntries(invertSubject: operation == .difference)
        guard let rings = graph.walk() else { return .failed }
        let subjectSign = Planar.signedArea(subject) >= 0
        return .rings(rings.map { (Planar.signedArea($0) >= 0) == subjectSign ? $0 : $0.reversed() })
    }

    /// Even-odd point in ring.
    static func contains(_ ring: [GeoPoint], _ p: GeoPoint) -> Bool {
        var inside = false
        var j = ring.count - 1
        for i in ring.indices {
            let a = ring[i], b = ring[j]
            if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    static func bounds(_ ring: [GeoPoint]) -> (min: GeoPoint, max: GeoPoint) {
        var low = ring[0], high = ring[0]
        for p in ring {
            low = simd_min(low, p)
            high = simd_max(high, p)
        }
        return (low, high)
    }

    /// Where segments a–b and c–d cross, strictly inside both. The subject's segment is
    /// taken in a fixed order, so neighbours sharing a border edge get the very same point.
    /// - Returns: The point and how far along each segment (0…1, in the order given).
    static func crossing(_ a: GeoPoint, _ b: GeoPoint, _ c: GeoPoint, _ d: GeoPoint) -> (point: GeoPoint, alongAB: Double, alongCD: Double)? {
        let swapped = (a.x, a.y) > (b.x, b.y)
        let p = swapped ? b : a, q = swapped ? a : b
        let r = q - p, s = d - c
        let denominator = cross(r, s)
        guard denominator != 0 else { return nil }
        let t = cross(c - p, s) / denominator
        let u = cross(c - p, r) / denominator
        guard t > 0, t < 1, u > 0, u < 1 else { return nil }
        return (c + s * u, swapped ? 1 - t : t, u)
    }

    private static func cross(_ a: GeoPoint, _ b: GeoPoint) -> Double { a.x * b.y - a.y * b.x }

    /// Both rings as circular lists with the crossings threaded into each and linked
    /// to their twins in the other.
    private struct Graph {
        struct Node {
            var point: GeoPoint
            var next = 0
            var previous = 0
            /// The same crossing in the other ring; -1 for the rings' own vertices.
            var twin = -1
            var entry = false
            var visited = false
            var isCrossing: Bool { twin >= 0 }
        }

        private(set) var subject: [Node] = []
        private(set) var clip: [Node] = []
        private let subjectRing: [GeoPoint]
        private let clipRing: [GeoPoint]

        var hasCrossings: Bool { subject.contains(where: \.isCrossing) }

        init(subject subjectRing: [GeoPoint], clip clipRing: [GeoPoint]) {
            self.subjectRing = subjectRing
            self.clipRing = clipRing
            let clipBounds = PolygonClipper.bounds(clipRing)

            // Crossings found along each edge: (how far along, crossing id).
            var onSubject: [Int: [(Double, Int)]] = [:]
            var onClip: [Int: [(Double, Int)]] = [:]
            var points: [GeoPoint] = []

            let clipEdges = clipRing.indices.map { j in
                let c = clipRing[j], d = clipRing[(j + 1) % clipRing.count]
                return (min: simd_min(c, d), max: simd_max(c, d))
            }
            for i in subjectRing.indices {
                let a = subjectRing[i], b = subjectRing[(i + 1) % subjectRing.count]
                let low = simd_min(a, b), high = simd_max(a, b)
                guard high.x >= clipBounds.min.x, low.x <= clipBounds.max.x,
                      high.y >= clipBounds.min.y, low.y <= clipBounds.max.y
                else { continue }
                for j in clipRing.indices {
                    let edge = clipEdges[j]
                    guard high.x >= edge.min.x, low.x <= edge.max.x, high.y >= edge.min.y, low.y <= edge.max.y else { continue }
                    let c = clipRing[j], d = clipRing[(j + 1) % clipRing.count]
                    guard let hit = PolygonClipper.crossing(a, b, c, d) else { continue }
                    let id = points.count
                    points.append(hit.point)
                    onSubject[i, default: []].append((hit.alongAB, id))
                    onClip[j, default: []].append((hit.alongCD, id))
                }
            }

            var subjectSlot = [Int](repeating: -1, count: points.count)
            var clipSlot = [Int](repeating: -1, count: points.count)
            subject = Self.thread(subjectRing, crossings: onSubject, points: points, slots: &subjectSlot)
            clip = Self.thread(clipRing, crossings: onClip, points: points, slots: &clipSlot)
            for id in points.indices {
                subject[subjectSlot[id]].twin = clipSlot[id]
                clip[clipSlot[id]].twin = subjectSlot[id]
            }
        }

        private static func thread(_ ring: [GeoPoint], crossings: [Int: [(Double, Int)]], points: [GeoPoint], slots: inout [Int]) -> [Node] {
            var nodes: [Node] = []
            for (i, point) in ring.enumerated() {
                nodes.append(Node(point: point))
                for (_, id) in (crossings[i] ?? []).sorted(by: { $0.0 < $1.0 }) {
                    slots[id] = nodes.count
                    // Marked as a crossing once its twin is linked.
                    nodes.append(Node(point: points[id], twin: Int.max))
                }
            }
            for k in nodes.indices {
                nodes[k].next = (k + 1) % nodes.count
                nodes[k].previous = (k + nodes.count - 1) % nodes.count
            }
            return nodes
        }

        /// Each crossing either enters the other ring or leaves it. For a difference the
        /// subject's flags flip, so the walk follows the subject outside the clip ring.
        mutating func markEntries(invertSubject: Bool) {
            Self.mark(&subject, against: clipRing, invert: invertSubject)
            Self.mark(&clip, against: subjectRing, invert: false)
        }

        private static func mark(_ nodes: inout [Node], against ring: [GeoPoint], invert: Bool) {
            var inside = PolygonClipper.contains(ring, nodes[0].point)
            for k in nodes.indices where nodes[k].isCrossing {
                nodes[k].entry = !inside != invert
                inside.toggle()
            }
        }

        /// Follows the flags from crossing to crossing, switching rings at each, until every
        /// crossing is used. `nil` if a walk doesn't close (odd crossings from round-off).
        mutating func walk() -> [[GeoPoint]]? {
            var rings: [[GeoPoint]] = []
            let limit = (subject.count + clip.count) * 2
            for start in subject.indices where subject[start].isCrossing && !subject[start].visited {
                var ring: [GeoPoint] = []
                var onSubject = true
                var current = start
                var steps = 0
                repeat {
                    // Every crossing starts exactly one stretch; mark it from either side.
                    if onSubject {
                        subject[current].visited = true
                        clip[subject[current].twin].visited = true
                    } else {
                        clip[current].visited = true
                        subject[clip[current].twin].visited = true
                    }
                    let forward = onSubject ? subject[current].entry : clip[current].entry
                    repeat {
                        ring.append(onSubject ? subject[current].point : clip[current].point)
                        let node = onSubject ? subject[current] : clip[current]
                        current = forward ? node.next : node.previous
                        steps += 1
                        if steps > limit { return nil }
                    } while !(onSubject ? subject[current].isCrossing : clip[current].isCrossing)
                    current = onSubject ? subject[current].twin : clip[current].twin
                    onSubject.toggle()
                } while !(onSubject && current == start)
                if ring.count >= 3 { rings.append(ring) }
            }
            return rings
        }
    }
}
