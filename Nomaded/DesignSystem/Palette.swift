import SwiftUI

/// Brand colors. Values mirror docs/02-design.md.
enum Palette {
    static let night = Color(rgb: 0x0D0A2E)
    static let nebula = Color(rgb: 0x3B1F8C)
    static let accent = Color(rgb: 0x7C5CFF)
    static let atmosphere = Color(rgb: 0x7DD3FC)

    /// Raw values for places that can't take a `Color`, like RealityKit materials.
    enum RGB {
        static let ocean: UInt32 = 0x1F45B5
        static let landIdle: UInt32 = 0x4B4778
        static let landUnclaimed: UInt32 = 0x3C3962
        /// Bubblegum, tangerine, lemon, mint, sky, grape.
        static let candy: [UInt32] = [0xFF5FA2, 0xFF9F43, 0xFFD93D, 0x3DDC97, 0x4DA3FF, 0x8B5CF6]
    }

    /// sRGB components in 0…1.
    static func components(_ rgb: UInt32) -> SIMD3<Float> {
        SIMD3(Float((rgb >> 16) & 0xFF), Float((rgb >> 8) & 0xFF), Float(rgb & 0xFF)) / 255
    }

    /// Unvisited land in six close shades, one per color slot. Neighbours never share a
    /// slot, so borders read without drawing lines.
    static let idleLandShades: [SIMD3<Float>] = [0.86, 1.12, 0.95, 1.2, 0.9, 1.04].map {
        components(RGB.landIdle) * Float($0)
    }
}

extension Color {
    init(rgb: UInt32) {
        let c = Palette.components(rgb)
        self.init(red: Double(c.x), green: Double(c.y), blue: Double(c.z))
    }
}
