import CoreGraphics
import Foundation

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

/// Which city names fit on screen, and where. Greedy, in priority order:
/// - dots that sit on top of each other share one name ("Rome · Vatican City"): no zoom ever
///   pulls them apart;
/// - each name tries above its dot, then below, right and left, and skips a spot that would
///   cover another name or dot;
/// - one with no room left waits until the user zooms in further.
enum CityLabelLayout {
    /// Dots closer than this, in points, share a name.
    static let mergeDistance: CGFloat = 12
    /// Room around a dot that a name keeps clear of.
    static let dotRadius: CGFloat = 6

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

    /// `candidates` must be in priority order, most important first.
    static func place(_ candidates: [CityLabel], in bounds: CGRect) -> [CityLabel] {
        // Groups of dots on one spot, led by the most important.
        var groups: [[CityLabel]] = []
        for label in candidates {
            if let index = groups.firstIndex(where: { distance($0[0].point, label.point) < mergeDistance }) {
                groups[index].append(label)
            } else {
                groups.append([label])
            }
        }

        let dots = groups.map { $0[0].point }
        var placed: [CityLabel] = []
        var boxes: [CGRect] = []
        for (index, group) in groups.enumerated() {
            var label = group[0]
            label.name = switch group.count {
            case 1: label.name
            case 2: label.name + " · " + group[1].name
            default: label.name + " +\(group.count - 1)"
            }
            label.isHighlighted = group.contains(where: \.isHighlighted)
            for placement in CityLabel.Placement.allCases {
                let box = box(for: label.name, at: label.point, isCapital: label.isCapital, placement: placement)
                guard bounds.contains(box) || (placement == .above && bounds.intersects(box)),
                      !boxes.contains(where: { $0.intersects(box) }),
                      !dots.enumerated().contains(where: { $0.offset != index && box.insetBy(dx: -dotRadius, dy: -dotRadius).contains($0.element) })
                else { continue }
                label.placement = placement
                placed.append(label)
                boxes.append(box)
                break
            }
        }
        return placed
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}
