import SwiftUI

/// Deep space behind the globe: a slowly drifting nebula and a fixed starfield.
struct SpaceBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // The drift is slow, so 30 fps is plenty and leaves the GPU to the globe.
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
            Nebula(time: timeline.date.timeIntervalSinceReferenceDate)
        }
        .overlay { Starfield() }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

private struct Nebula: View {
    let time: TimeInterval

    var body: some View {
        // Keep the angle small so Float stays precise.
        let t = Float(time.truncatingRemainder(dividingBy: 3600))
        let drift = SIMD2<Float>(0.5 + 0.18 * sin(t * 0.15), 0.42 + 0.12 * cos(t * 0.11))
        let points: [SIMD2<Float>] = [
            [0, 0], [0.5, 0], [1, 0],
            [0, 0.5], drift, [1, 0.5],
            [0, 1], [0.5, 1], [1, 1],
        ]
        MeshGradient(width: 3, height: 3, points: points, colors: Self.colors)
    }

    private static let deep = Color(rgb: 0x07051A)
    private static let colors: [Color] = [
        deep, Palette.night, deep,
        Palette.night, Palette.nebula.opacity(0.9), Color(rgb: 0x1A1458),
        deep, Color(rgb: 0x2A0F45), deep,
    ]
}

private struct Starfield: View {
    var body: some View {
        Canvas { context, size in
            var random = SplitMix64(seed: 7)
            for _ in 0..<150 {
                let x = Double.random(in: 0...1, using: &random) * size.width
                let y = Double.random(in: 0...1, using: &random) * size.height
                let radius = Double.random(in: 0.3...1.2, using: &random)
                let opacity = Double.random(in: 0.2...0.85, using: &random)
                let star = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: star), with: .color(.white.opacity(opacity)))
            }
        }
        .allowsHitTesting(false)
    }
}

/// Seeded generator: the same seed gives the same numbers, so the stars stay in place between
/// launches and a confetti burst can be recomputed every frame instead of stored.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

#Preview {
    SpaceBackground()
}
