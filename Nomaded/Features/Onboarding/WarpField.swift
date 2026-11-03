import SwiftUI

/// The jump out of hyperspace on first launch: stars stream out from the middle as long
/// streaks, slow down and shrink to points, and fade into the still starfield behind.
/// Worked out from the time alone, like the confetti.
struct WarpField: View {
    let start: Date

    static let duration = 1.8
    private static let stars = 170

    var body: some View {
        TimelineView(.animation(paused: start.timeIntervalSinceNow < -Self.duration)) { timeline in
            Canvas { context, size in
                draw(at: timeline.date.timeIntervalSince(start), in: context, size: size)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func draw(at t: Double, in context: GraphicsContext, size: CGSize) {
        guard t >= 0, t < Self.duration else { return }
        let progress = t / Self.duration
        // Full speed at first, easing to a stop.
        let speed = pow(1 - progress, 2)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let reach = hypot(size.width, size.height) / 2
        var random = SplitMix64(seed: 42)

        for _ in 0..<Self.stars {
            let angle = Double.random(in: 0..<(2 * .pi), using: &random)
            let start = Double.random(in: 0.02...0.9, using: &random)
            let pace = Double.random(in: 0.6...1.4, using: &random)
            let brightness = Double.random(in: 0.4...1, using: &random)
            // Out from the middle, fast then slowing; past the edge it's gone.
            let distance = (start + pace * 0.9 * (1 - pow(1 - progress, 3))) * reach
            guard distance < reach * 1.1 else { continue }
            let tail = distance * (1 - 0.45 * speed * pace)
            let direction = CGVector(dx: cos(angle), dy: sin(angle))
            var streak = Path()
            streak.move(to: CGPoint(x: center.x + direction.dx * tail, y: center.y + direction.dy * tail))
            streak.addLine(to: CGPoint(x: center.x + direction.dx * distance, y: center.y + direction.dy * distance))
            context.stroke(
                streak,
                with: .color(.white.opacity(brightness * (1 - progress))),
                style: StrokeStyle(lineWidth: 0.8 + 1.4 * speed, lineCap: .round)
            )
        }
    }
}

#Preview {
    WarpField(start: .now)
        .background(SpaceBackground())
}
