import CoreGraphics
import Foundation

/// A city's name over its dot, placed by the engine every frame; the view only draws it.
struct CityLabel: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    /// The dot, in view points. The label sits just above it.
    let point: CGPoint
    let isHighlighted: Bool
    var isCapital = false
    /// 0 → 1 as the name pops up out of its dot, back to 0 as it goes. Springs a little past 1.
    var appearance = 1.0
}

/// Which city names fit on screen without overlapping. Greedy, in priority order: a name
/// that would cover one already placed is left out until the user zooms in further.
enum CityLabelLayout {
    /// Room a label takes, from a rough per-character width. Close enough to keep names
    /// apart without measuring text every frame.
    static func box(for name: String, at point: CGPoint, isCapital: Bool = false) -> CGRect {
        let width = CGFloat(name.count) * 7.5 + 22 + (isCapital ? 12 : 0)
        let height: CGFloat = 26
        return CGRect(x: point.x - width / 2, y: point.y - height - 8, width: width, height: height)
    }

    /// `candidates` must be in priority order, most important first.
    static func place(_ candidates: [CityLabel], in bounds: CGRect) -> [CityLabel] {
        var placed: [CityLabel] = []
        var boxes: [CGRect] = []
        for label in candidates {
            let box = box(for: label.name, at: label.point, isCapital: label.isCapital)
            guard bounds.intersects(box), !boxes.contains(where: { $0.intersects(box) }) else { continue }
            placed.append(label)
            boxes.append(box)
        }
        return placed
    }
}
