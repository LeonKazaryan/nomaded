import SwiftUI

/// One burst of confetti: where, in which colors, and when it went off.
struct ConfettiBurst: Identifiable {
    let id = UUID()
    /// In the screen's coordinates.
    let origin: CGPoint
    let colors: [Color]
    let start = Date.now
    /// Picks every piece's size, speed and spin; the same each frame.
    var seed = UInt64.random(in: 0...UInt64.max)

    static let lifetime = 1.9
}

/// Paper confetti thrown out of a marked country: fast at first, slowed by the air, pulled
/// down, tumbling and fluttering as it falls. Every piece's position is worked out from the
/// physics at the frame's time, so nothing is stepped or stored.
struct ConfettiView: View {
    let bursts: [ConfettiBurst]

    private static let pieces = 90
    /// Points per second squared, down.
    private static let gravity = 900.0

    var body: some View {
        TimelineView(.animation(paused: bursts.isEmpty)) { timeline in
            Canvas { context, _ in
                for burst in bursts {
                    draw(burst, at: timeline.date.timeIntervalSince(burst.start), in: context)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The burst `t` seconds after it went off. Also draws a still of it (the App Store's
    /// creative assets).
    func draw(_ burst: ConfettiBurst, at t: Double, in context: GraphicsContext) {
        guard t >= 0, t < ConfettiBurst.lifetime else { return }
        var random = SplitMix64(seed: burst.seed)
        let fade = 1 - max(0, (t - (ConfettiBurst.lifetime - 0.6)) / 0.6)
        for _ in 0..<Self.pieces {
            let angle = Double.random(in: 0..<(2 * .pi), using: &random)
            let speed = Double.random(in: 240...720, using: &random)
            // Thrown a little upward, the way a popper fires.
            let velocity = CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed - 240)
            // Paper catches the air: high drag, low terminal speed.
            let drag = Double.random(in: 2.0...3.4, using: &random)
            let spin = Double.random(in: -9...9, using: &random)
            let flutter = Double.random(in: 7...15, using: &random)
            let phase = Double.random(in: 0..<(2 * .pi), using: &random)
            let isDot = Double.random(in: 0..<1, using: &random) < 0.25
            let size = CGSize(width: Double.random(in: 7...11, using: &random), height: Double.random(in: 3.5...6, using: &random))
            let color = burst.colors[Int.random(in: 0..<burst.colors.count, using: &random)]

            // dv/dt = g − k·v, solved: the throw dies away and the fall settles at g/k.
            let slowing = (1 - exp(-drag * t)) / drag
            let x = burst.origin.x + velocity.dx * slowing
            let y = burst.origin.y + Self.gravity / drag * t + (velocity.dy - Self.gravity / drag) * slowing

            var piece = context
            piece.opacity = fade
            piece.translateBy(x: x, y: y)
            piece.rotate(by: .radians(phase + spin * t))
            if isDot {
                piece.fill(Path(ellipseIn: CGRect(x: -2.5, y: -2.5, width: 5, height: 5)), with: .color(color))
            } else {
                // Turning over in the air: its width swings through zero and back.
                piece.scaleBy(x: cos(phase + flutter * t), y: 1)
                piece.fill(Path(CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)), with: .color(color))
            }
        }
    }
}

#Preview {
    ConfettiView(bursts: [ConfettiBurst(origin: CGPoint(x: 200, y: 400), colors: [Palette.candy[0], .white, Palette.capital])])
        .background(SpaceBackground())
}
