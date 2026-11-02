import SwiftUI

/// One ratio against a whole, e.g. the share of the world explored.
///
/// A meter uses one hue: the fill is the accent, the track a faint step of the same
/// color. No rainbow: several colors would suggest categories that aren't there.
struct ProgressRing<Label: View>: View {
    /// 0…1.
    let progress: Double
    var lineWidth: CGFloat = 14
    @ViewBuilder var label: Label

    @State private var shown = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .stroke(Palette.accent.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: shown)
                .stroke(
                    AngularGradient(
                        colors: [Palette.accentLight, Palette.accent],
                        center: .center,
                        startAngle: .zero,
                        endAngle: .degrees(360 * max(shown, 0.01))
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: Palette.accent.opacity(0.55), radius: 8)
            label
        }
        .padding(lineWidth / 2)
        .accessibilityElement(children: .combine)
        .onAppear { show(progress) }
        .onChange(of: progress) { _, newValue in show(newValue) }
    }

    private func show(_ target: Double) {
        let clamped = min(1, max(0, target))
        if reduceMotion {
            shown = clamped
        } else {
            withAnimation(Motion.smooth.delay(0.1)) { shown = clamped }
        }
    }
}

/// The world-explored ring with its percentage in the middle.
struct WorldProgressRing: View {
    let progress: Double

    var body: some View {
        ProgressRing(progress: progress) {
            VStack(spacing: 0) {
                Text(progress, format: .percent.precision(.fractionLength(0)))
                    .font(.system(.title, design: .rounded, weight: .heavy))
                    .contentTransition(.numericText(value: progress))
                Text("of the world")
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
            }
            .animation(Motion.bouncy, value: progress)
        }
    }
}

#Preview {
    WorldProgressRing(progress: 27.0 / 195)
        .frame(width: 180, height: 180)
        .padding()
        .background(SpaceBackground())
}
