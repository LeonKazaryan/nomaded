/// Polygon triangulation by ear clipping, ported from mapbox/earcut 2.2.4 (ISC license,
/// https://github.com/mapbox/earcut). The z-order hashing speed-up is left out: this runs
/// offline on simplified rings, so the plain version is fast enough.
///
/// Nodes of the circular linked list live in parallel arrays and are addressed by index.
struct Earcut {
    private var x: [Double] = []
    private var y: [Double] = []
    private var vertex: [Int] = []
    private var prev: [Int] = []
    private var next: [Int] = []
    private var steiner: [Bool] = []
    private var triangles: [Int] = []

    /// - Parameters:
    ///   - coords: Flat `[x0, y0, x1, y1, …]`, outer ring first, then holes.
    ///   - holeIndices: Vertex index where each hole starts.
    /// - Returns: Vertex indices, three per triangle.
    static func triangulate(_ coords: [Double], holeIndices: [Int]) -> [Int] {
        var earcut = Earcut()
        return earcut.run(coords, holeIndices: holeIndices)
    }

    private mutating func run(_ coords: [Double], holeIndices: [Int]) -> [Int] {
        let outerLength = holeIndices.first ?? coords.count / 2
        guard var outer = linkedList(coords, 0, outerLength, clockwise: true), next[outer] != prev[outer] else {
            return []
        }
        if !holeIndices.isEmpty {
            outer = eliminateHoles(coords, holeIndices, outer)
        }
        earcutLinked(outer, pass: 0)
        return triangles
    }

    // MARK: - Linked list

    private mutating func makeNode(_ index: Int, _ px: Double, _ py: Double) -> Int {
        let id = x.count
        x.append(px)
        y.append(py)
        vertex.append(index)
        prev.append(id)
        next.append(id)
        steiner.append(false)
        return id
    }

    private mutating func insertNode(_ index: Int, _ px: Double, _ py: Double, after last: Int?) -> Int {
        let p = makeNode(index, px, py)
        if let last {
            next[p] = next[last]
            prev[p] = last
            prev[next[last]] = p
            next[last] = p
        }
        return p
    }

    private mutating func removeNode(_ p: Int) {
        prev[next[p]] = prev[p]
        next[prev[p]] = next[p]
    }

    private mutating func linkedList(_ coords: [Double], _ start: Int, _ end: Int, clockwise: Bool) -> Int? {
        var last: Int?
        if clockwise == (signedArea(coords, start, end) > 0) {
            for i in start..<end { last = insertNode(i, coords[2 * i], coords[2 * i + 1], after: last) }
        } else {
            for i in stride(from: end - 1, through: start, by: -1) {
                last = insertNode(i, coords[2 * i], coords[2 * i + 1], after: last)
            }
        }
        if let l = last, equals(l, next[l]) {
            removeNode(l)
            last = next[l]
        }
        return last
    }

    private func signedArea(_ coords: [Double], _ start: Int, _ end: Int) -> Double {
        var sum = 0.0
        var j = end - 1
        for i in start..<end {
            sum += (coords[2 * j] - coords[2 * i]) * (coords[2 * i + 1] + coords[2 * j + 1])
            j = i
        }
        return sum
    }

    /// Removes duplicate and collinear points.
    private mutating func filterPoints(_ start: Int, _ endHint: Int? = nil) -> Int {
        var end = endHint ?? start
        var p = start
        var again: Bool
        repeat {
            again = false
            if !steiner[p] && (equals(p, next[p]) || area(prev[p], p, next[p]) == 0) {
                removeNode(p)
                p = prev[p]
                end = p
                if p == next[p] { break }
                again = true
            } else {
                p = next[p]
            }
        } while again || p != end
        return end
    }

    // MARK: - Ear slicing

    private mutating func earcutLinked(_ start: Int, pass: Int) {
        var ear = start
        var stop = ear
        while prev[ear] != next[ear] {
            let p = prev[ear]
            let n = next[ear]
            if isEar(ear) {
                triangles.append(vertex[p])
                triangles.append(vertex[ear])
                triangles.append(vertex[n])
                removeNode(ear)
                // Skipping the next vertex leads to fewer sliver triangles.
                ear = next[n]
                stop = next[n]
                continue
            }
            ear = n
            if ear == stop {
                switch pass {
                case 0:
                    earcutLinked(filterPoints(ear), pass: 1)
                case 1:
                    earcutLinked(cureLocalIntersections(filterPoints(ear)), pass: 2)
                default:
                    splitEarcut(ear)
                }
                break
            }
        }
    }

    private func isEar(_ ear: Int) -> Bool {
        let a = prev[ear], b = ear, c = next[ear]
        if area(a, b, c) >= 0 { return false }

        let ax = x[a], bx = x[b], cx = x[c], ay = y[a], by = y[b], cy = y[c]
        let x0 = min(ax, bx, cx), y0 = min(ay, by, cy), x1 = max(ax, bx, cx), y1 = max(ay, by, cy)

        var p = next[c]
        while p != a {
            if x[p] >= x0 && x[p] <= x1 && y[p] >= y0 && y[p] <= y1
                && pointInTriangle(ax, ay, bx, by, cx, cy, x[p], y[p])
                && area(prev[p], p, next[p]) >= 0 {
                return false
            }
            p = next[p]
        }
        return true
    }

    private mutating func cureLocalIntersections(_ startNode: Int) -> Int {
        var start = startNode
        var p = start
        repeat {
            let a = prev[p], b = next[next[p]]
            if !equals(a, b) && intersects(a, p, next[p], b) && locallyInside(a, b) && locallyInside(b, a) {
                triangles.append(vertex[a])
                triangles.append(vertex[p])
                triangles.append(vertex[b])
                removeNode(p)
                removeNode(next[p])
                p = b
                start = b
            }
            p = next[p]
        } while p != start
        return filterPoints(p)
    }

    private mutating func splitEarcut(_ start: Int) {
        var a = start
        repeat {
            var b = next[next[a]]
            while b != prev[a] {
                if vertex[a] != vertex[b] && isValidDiagonal(a, b) {
                    let c = splitPolygon(a, b)
                    let first = filterPoints(a, next[a])
                    let second = filterPoints(c, next[c])
                    earcutLinked(first, pass: 0)
                    earcutLinked(second, pass: 0)
                    return
                }
                b = next[b]
            }
            a = next[a]
        } while a != start
    }

    // MARK: - Holes

    private mutating func eliminateHoles(_ coords: [Double], _ holeIndices: [Int], _ outerNode: Int) -> Int {
        var queue: [Int] = []
        let total = coords.count / 2
        for (k, start) in holeIndices.enumerated() {
            let end = k < holeIndices.count - 1 ? holeIndices[k + 1] : total
            guard let list = linkedList(coords, start, end, clockwise: false) else { continue }
            if list == next[list] { steiner[list] = true }
            queue.append(leftmost(list))
        }
        queue.sort { x[$0] < x[$1] }

        var outer = outerNode
        for hole in queue {
            outer = eliminateHole(hole, outer)
        }
        return outer
    }

    private mutating func eliminateHole(_ hole: Int, _ outer: Int) -> Int {
        guard let bridge = findHoleBridge(hole, outer) else { return outer }
        let bridgeReverse = splitPolygon(bridge, hole)
        _ = filterPoints(bridgeReverse, next[bridgeReverse])
        return filterPoints(bridge, next[bridge])
    }

    /// David Eberly's algorithm for finding a bridge between a hole and the outer polygon.
    private func findHoleBridge(_ hole: Int, _ outer: Int) -> Int? {
        let hx = x[hole], hy = y[hole]
        var qx = -Double.infinity
        var candidate: Int?

        var p = outer
        repeat {
            let n = next[p]
            if hy <= y[p] && hy >= y[n] && y[n] != y[p] {
                let ix = x[p] + (hy - y[p]) * (x[n] - x[p]) / (y[n] - y[p])
                if ix <= hx && ix > qx {
                    qx = ix
                    candidate = x[p] < x[n] ? p : n
                    if ix == hx { return candidate }
                }
            }
            p = n
        } while p != outer

        guard var m = candidate else { return nil }

        let stop = m
        let mx = x[m], my = y[m]
        var tanMin = Double.infinity
        p = m
        repeat {
            if hx >= x[p] && x[p] >= mx && hx != x[p]
                && pointInTriangle(hy < my ? hx : qx, hy, mx, my, hy < my ? qx : hx, hy, x[p], y[p]) {
                let tan = abs(hy - y[p]) / (hx - x[p])
                if locallyInside(p, hole)
                    && (tan < tanMin || (tan == tanMin && (x[p] > x[m] || (x[p] == x[m] && sectorContainsSector(m, p))))) {
                    m = p
                    tanMin = tan
                }
            }
            p = next[p]
        } while p != stop
        return m
    }

    private func sectorContainsSector(_ m: Int, _ p: Int) -> Bool {
        area(prev[m], m, prev[p]) < 0 && area(next[p], m, next[m]) < 0
    }

    private func leftmost(_ start: Int) -> Int {
        var p = start
        var result = start
        repeat {
            if x[p] < x[result] || (x[p] == x[result] && y[p] < y[result]) { result = p }
            p = next[p]
        } while p != start
        return result
    }

    // MARK: - Geometry predicates

    private func pointInTriangle(
        _ ax: Double, _ ay: Double, _ bx: Double, _ by: Double,
        _ cx: Double, _ cy: Double, _ px: Double, _ py: Double
    ) -> Bool {
        (cx - px) * (ay - py) >= (ax - px) * (cy - py)
            && (ax - px) * (by - py) >= (bx - px) * (ay - py)
            && (bx - px) * (cy - py) >= (cx - px) * (by - py)
    }

    private func isValidDiagonal(_ a: Int, _ b: Int) -> Bool {
        let visible = locallyInside(a, b) && locallyInside(b, a) && middleInside(a, b)
            && (area(prev[a], a, prev[b]) != 0 || area(a, prev[b], b) != 0)
        let zeroLength = equals(a, b) && area(prev[a], a, next[a]) > 0 && area(prev[b], b, next[b]) > 0
        return vertex[next[a]] != vertex[b] && vertex[prev[a]] != vertex[b] && !intersectsPolygon(a, b)
            && (visible || zeroLength)
    }

    private func area(_ p: Int, _ q: Int, _ r: Int) -> Double {
        (y[q] - y[p]) * (x[r] - x[q]) - (x[q] - x[p]) * (y[r] - y[q])
    }

    private func equals(_ a: Int, _ b: Int) -> Bool {
        x[a] == x[b] && y[a] == y[b]
    }

    private func intersects(_ p1: Int, _ q1: Int, _ p2: Int, _ q2: Int) -> Bool {
        let o1 = sign(area(p1, q1, p2))
        let o2 = sign(area(p1, q1, q2))
        let o3 = sign(area(p2, q2, p1))
        let o4 = sign(area(p2, q2, q1))
        if o1 != o2 && o3 != o4 { return true }
        if o1 == 0 && onSegment(p1, p2, q1) { return true }
        if o2 == 0 && onSegment(p1, q2, q1) { return true }
        if o3 == 0 && onSegment(p2, p1, q2) { return true }
        if o4 == 0 && onSegment(p2, q1, q2) { return true }
        return false
    }

    private func onSegment(_ p: Int, _ q: Int, _ r: Int) -> Bool {
        x[q] <= max(x[p], x[r]) && x[q] >= min(x[p], x[r]) && y[q] <= max(y[p], y[r]) && y[q] >= min(y[p], y[r])
    }

    private func sign(_ value: Double) -> Int {
        value > 0 ? 1 : (value < 0 ? -1 : 0)
    }

    private func intersectsPolygon(_ a: Int, _ b: Int) -> Bool {
        var p = a
        repeat {
            if vertex[p] != vertex[a] && vertex[next[p]] != vertex[a] && vertex[p] != vertex[b] && vertex[next[p]] != vertex[b]
                && intersects(p, next[p], a, b) {
                return true
            }
            p = next[p]
        } while p != a
        return false
    }

    private func locallyInside(_ a: Int, _ b: Int) -> Bool {
        area(prev[a], a, next[a]) < 0
            ? area(a, b, next[a]) >= 0 && area(a, prev[a], b) >= 0
            : area(a, b, prev[a]) < 0 || area(a, next[a], b) < 0
    }

    private func middleInside(_ a: Int, _ b: Int) -> Bool {
        var p = a
        var inside = false
        let mx = (x[a] + x[b]) / 2
        let my = (y[a] + y[b]) / 2
        repeat {
            let n = next[p]
            if (y[p] > my) != (y[n] > my) && y[n] != y[p]
                && mx < (x[n] - x[p]) * (my - y[p]) / (y[n] - y[p]) + x[p] {
                inside.toggle()
            }
            p = n
        } while p != a
        return inside
    }

    /// Links two vertices with a bridge: splits a ring in two, or merges a hole into the outer ring.
    private mutating func splitPolygon(_ a: Int, _ b: Int) -> Int {
        let a2 = makeNode(vertex[a], x[a], y[a])
        let b2 = makeNode(vertex[b], x[b], y[b])
        let an = next[a]
        let bp = prev[b]

        next[a] = b
        prev[b] = a

        next[a2] = an
        prev[an] = a2

        next[b2] = a2
        prev[a2] = b2

        next[bp] = b2
        prev[b2] = bp

        return b2
    }
}
