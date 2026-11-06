import CoreGraphics
import Foundation
import simd

/// A city's name next to its dot, placed by the engine every frame; the view only draws it.
struct CityLabel: Identifiable, Equatable, Sendable {
    /// Which side of the dot the name sits on.
    enum Placement: CaseIterable, Sendable {
        case above, below, right, left
    }

    let id: UUID
    /// The city's name, or several when their dots sit together: "Rome · Vatican City",
    /// "Rome +2".
    var name: String
    /// The dot, in view points.
    let point: CGPoint
    var isHighlighted: Bool
    var isCapital = false
    var placement = Placement.above
    /// 0 → 1 as the name pops up out of its dot, back to 0 as it goes. Springs a little past 1.
    var appearance = 1.0
}

/// One name's life on screen: it pops up out of its dot and sinks back when it goes. A name
/// never changes in place: given new text or another side, it first sinks into its dot,
/// then pops out changed.
struct CityLabelMotion: Sendable {
    /// The text and side as drawn, which may lag behind the layout while the name is sinking.
    private(set) var name: String
    private(set) var placement: CityLabel.Placement
    private(set) var appearance = SpringValue(0)

    init(_ label: CityLabel) {
        name = label.name
        placement = label.placement
    }

    /// Sunk back into its dot for good.
    var isGone: Bool { appearance.target == 0 && appearance.value <= 0.01 }
    var isSettled: Bool { appearance.isSettled }

    /// `placed` is the name as laid out this frame, `nil` when it has no room.
    mutating func step(_ dt: Double, toward placed: CityLabel?, reduceMotion: Bool) {
        // Hidden in its dot, it can change unseen.
        if let placed, placed.name != name || placed.placement != placement,
           reduceMotion || appearance.value < 0.05 {
            name = placed.name
            placement = placed.placement
        }
        appearance.target = placed.map { $0.name == name && $0.placement == placement } == true ? 1 : 0
        if reduceMotion { appearance.snap() } else { appearance.step(dt, GlobeTuning.cityLabelSpring) }
    }

    /// `label` (its dot, colors) drawn with this name, side and appearance.
    func applied(to label: CityLabel) -> CityLabel {
        var label = label
        label.name = name
        label.placement = placement
        label.appearance = appearance.value
        return label
    }
}

/// Which city names fit on screen, and where. Greedy, in priority order:
/// - dots that sit together on the globe share one name ("Rome · Vatican City"). How close
///   they are is measured on the globe, not on screen, so turning it never merges or splits
///   names; only the zoom does;
/// - each name tries the side it's already on, then above its dot, below, right and left,
///   and skips a spot that would cover another name or dot;
/// - names already showing keep their spots before new ones get any, and get a little slack
///   there, while a new one needs room to spare, so none blinks on and off at the edge of
///   fitting;
/// - near the horizon, where the globe squeezes everything together, names sink back in;
/// - one with no room left waits until the user zooms in further.
enum CityLabelLayout {
    /// A city the layout may name.
    struct Candidate: Sendable {
        var label: CityLabel
        /// The city on the unit globe: dots are grouped by this, not by where they are on screen.
        var location: SIMD3<Double>
        /// How squarely the dot faces the camera: 1 head-on, 0 at the horizon.
        var facing = 1.0
        /// Placed before the names already showing: the highlighted city and the selected
        /// country's.
        var isFeatured = false
    }

    /// Dots closer than this share a name, in points, as if they faced the camera head-on.
    static let mergeDistance: CGFloat = 12
    /// Room around a dot that a name keeps clear of.
    static let dotRadius: CGFloat = 6
    /// A name staying where it is may come this close to others, in points, overlapping…
    static let slack: CGFloat = 2
    /// …while a new one, or one moving to another side, needs this much room to spare.
    static let clearance: CGFloat = 3

    /// Room a label takes, from a rough per-character width. Close enough to keep names
    /// apart without measuring text every frame.
    static func box(for name: String, at point: CGPoint, isCapital: Bool = false, placement: CityLabel.Placement = .above) -> CGRect {
        let width = CGFloat(name.count) * 7.5 + 22 + (isCapital ? 12 : 0)
        let height: CGFloat = 26
        switch placement {
        case .above: return CGRect(x: point.x - width / 2, y: point.y - height - 8, width: width, height: height)
        case .below: return CGRect(x: point.x - width / 2, y: point.y + 8, width: width, height: height)
        case .right: return CGRect(x: point.x + 10, y: point.y - height / 2, width: width, height: height)
        case .left: return CGRect(x: point.x - 10 - width, y: point.y - height / 2, width: width, height: height)
        }
    }

    /// `candidates` must be in priority order, most important first. `previous` holds the
    /// side each name was given last frame.
    static func place(_ candidates: [Candidate], in bounds: CGRect, pointsPerRadian: Double, previous: [UUID: CityLabel.Placement] = [:]) -> [CityLabel] {
        // Groups of dots on one spot, led by the most important. In priority order only, not
        // by what's showing, so a name hiding behind another can't regroup its spot.
        let mergeChord = Double(mergeDistance) / pointsPerRadian
        var groups: [[Candidate]] = []
        for candidate in candidates {
            if let index = groups.firstIndex(where: { simd_distance($0[0].location, candidate.location) < mergeChord }) {
                groups[index].append(candidate)
            } else {
                groups.append([candidate])
            }
        }

        let dots = groups.map { $0[0].label.point }
        // Featured names first, then the ones already showing, so they keep their spots.
        let tier = { (index: Int) in
            groups[index][0].isFeatured ? 0 : previous[groups[index][0].label.id] != nil ? 1 : 2
        }
        let order = groups.indices.sorted { (tier($0), $0) < (tier($1), $1) }

        var placed: [CityLabel] = []
        var boxes: [CGRect] = []
        for index in order {
            let group = groups[index]
            var label = group[0].label
            let current = previous[label.id]
            let horizon = current == nil ? GlobeTuning.cityLabelHorizon.upperBound : GlobeTuning.cityLabelHorizon.lowerBound
            guard group[0].facing > horizon else { continue }
            label.name = switch group.count {
            case 1: label.name
            case 2: label.name + " · " + group[1].label.name
            default: label.name + " +\(group.count - 1)"
            }
            label.isHighlighted = group.contains(where: \.label.isHighlighted)
            let sides = current.map { side in [side] + CityLabel.Placement.allCases.filter { $0 != side } }
                ?? CityLabel.Placement.allCases
            let fits = { (placement: CityLabel.Placement) in
                let stays = placement == current
                let box = box(for: label.name, at: label.point, isCapital: label.isCapital, placement: placement)
                let probe = stays ? box.insetBy(dx: slack, dy: slack) : box.insetBy(dx: -clearance, dy: -clearance)
                // A name staying put may slide off the edge with its dot.
                return (bounds.contains(box) || ((stays || placement == .above) && bounds.intersects(box)))
                    && !boxes.contains(where: { $0.intersects(probe) })
                    && !dots.enumerated().contains(where: { $0.offset != index && probe.insetBy(dx: -dotRadius, dy: -dotRadius).contains($0.element) })
            }
            // The highlighted city always gets its name, over a neighbor's dot if it must.
            guard let placement = sides.first(where: fits) ?? (label.isHighlighted ? sides[0] : nil) else { continue }
            label.placement = placement
            placed.append(label)
            boxes.append(box(for: label.name, at: label.point, isCapital: label.isCapital, placement: placement))
        }
        return placed
    }
}
