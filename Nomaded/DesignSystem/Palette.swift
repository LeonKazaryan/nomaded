import SwiftUI

/// Brand colors. Values mirror docs/02-design.md.
enum Palette {
    static let night = Color(rgb: 0x0D0A2E)
    static let nebula = Color(rgb: 0x3B1F8C)
    static let accent = Color(rgb: 0x7C5CFF)
    static let accentLight = Color(rgb: 0xA88BFF)
    static let atmosphere = Color(rgb: 0x7DD3FC)
    /// The capital star, in search and on city names. The candy palette's Lemon.
    static let capital = Color(rgb: RGB.candy[2])

    /// Visited-country colors, in slot order. Validated for colorblind separation and
    /// 3:1 contrast against the ocean and land (docs/02-design.md); re-validate before
    /// changing any of them.
    static let candy: [Color] = RGB.candy.map(Color.init(rgb:))
    static let candyNames = ["Bubblegum", "Tangerine", "Lemon", "Mint", "Sky", "Grape"]

    /// Raw values for places that can't take a `Color`, like the Metal globe.
    enum RGB {
        static let ocean: UInt32 = 0x1F45B5
        /// A touch lighter than the ocean: a line a couple of points wide has to read on
        /// dark land, where a lake can be the ocean's own color.
        static let river: UInt32 = 0x3263DA
        static let landIdle: UInt32 = 0x4B4778
        static let landUnclaimed: UInt32 = 0x3C3962
        static let candy: [UInt32] = [0xFF6AAE, 0xFF8A3D, 0xFFE04A, 0x4BE8A5, 0x84CEFF, 0xB68AFF]
    }

    /// sRGB components in 0…1.
    static func components(_ rgb: UInt32) -> SIMD3<Float> {
        SIMD3(Float((rgb >> 16) & 0xFF), Float((rgb >> 8) & 0xFF), Float(rgb & 0xFF)) / 255
    }

    /// Milestone medals: a light and a dark tone each, lit like metal. Decoration, not data.
    enum Medal {
        static let bronze: (light: UInt32, dark: UInt32) = (0xF2B48A, 0xA35A2C)
        static let silver: (light: UInt32, dark: UInt32) = (0xF1F4FA, 0x8792AA)
        static let gold: (light: UInt32, dark: UInt32) = (0xFFE88A, 0xD18E12)
        static let violet: (light: UInt32, dark: UInt32) = (0xD8CCFF, 0x5B3FD9)
        static let sky: (light: UInt32, dark: UInt32) = (0xD4F0FF, 0x2F86D1)
        static let ice: (light: UInt32, dark: UInt32) = (0xFFFFFF, 0x9FC3DD)
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
