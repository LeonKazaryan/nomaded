import SwiftUI

/// Temporary splash until the globe lands (see docs/04-roadmap.md, M1).
struct ContentView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            TimelineView(.animation(minimumInterval: nil, paused: reduceMotion)) { timeline in
                AuroraBackground(time: timeline.date.timeIntervalSinceReferenceDate)
            }
            .ignoresSafeArea()

            VStack(spacing: 12) {
                Image(systemName: "globe.europe.africa.fill")
                    .font(.system(size: 88))
                    .symbolEffect(.breathe, isActive: !reduceMotion)
                Text("Nomaded")
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                Text("Your world, one country at a time")
                    .font(.system(.headline, design: .rounded))
                    .opacity(0.8)
            }
            .foregroundStyle(.white)
        }
    }
}

/// Slowly drifting mesh gradient — a first taste of the "living" background.
private struct AuroraBackground: View {
    let time: TimeInterval

    var body: some View {
        // Keep the angle small so Float stays precise.
        let t = Float(time.truncatingRemainder(dividingBy: 3600))
        let center = SIMD2<Float>(0.5 + 0.2 * sin(t * 0.6), 0.5 + 0.2 * cos(t * 0.5))
        let points: [SIMD2<Float>] = [
            [0, 0], [0.5, 0], [1, 0],
            [0, 0.5], center, [1, 0.5],
            [0, 1], [0.5, 1], [1, 1],
        ]

        MeshGradient(width: 3, height: 3, points: points, colors: Self.colors)
    }

    private static let night = Color(red: 0.05, green: 0.04, blue: 0.18)
    private static let colors: [Color] = [
        night, Color(red: 0.23, green: 0.12, blue: 0.55), night,
        Color(red: 0.30, green: 0.64, blue: 1.00), Color(red: 1.00, green: 0.37, blue: 0.64), Color(red: 0.55, green: 0.36, blue: 0.96),
        night, Color(red: 0.23, green: 0.12, blue: 0.55), night,
    ]
}

#Preview {
    ContentView()
}
