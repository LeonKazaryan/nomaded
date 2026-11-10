import SwiftUI

/// A milestone to celebrate, with what the screen needs to say about it.
struct MilestoneEvent: Identifiable, Equatable {
    let id = UUID()
    let milestone: Milestone
    /// The place whose mark reached it: a continent's first stop.
    let place: String
    /// Share of the 195 countries, for count milestones.
    let worldShare: Double
    /// Countries still to visit on the continent; `nil` where there are none (Antarctica).
    let remainingOnContinent: Int?

    var continent: Continent? {
        if case .continent(let continent) = milestone { continent } else { nil }
    }
}

/// The full-screen moment for a milestone. The medal drops in spinning like a tossed coin
/// (a light tick of haptics each half-turn, a heavy one as it lands), confetti goes off in
/// three bursts, rays turn slowly behind it, a highlight sweeps its face, and the words
/// cascade in. Any tap carries on.
struct MilestoneCelebration: View {
    let event: MilestoneEvent
    /// Outlines of the continent, for its medal's face.
    let outlines: [ContinentMaps.Outline]?
    let onDismiss: () -> Void

    @State private var landed = false
    @State private var spin = 0.0
    @State private var wordsShown = false
    @State private var hintShown = false
    @State private var shine = -1.0
    @State private var raysTurn = 0.0
    @State private var bursts: [ConfettiBurst] = []
    @State private var ticks = 0
    @State private var thuds = 0
    @State private var successes = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var sizeClass
    @ScaledMetric(relativeTo: .largeTitle) private var baseMedalSize = 172

    /// A bigger coin on an iPad's bigger stage.
    private var medalSize: Double { baseMedalSize * (sizeClass == .regular ? 1.35 : 1) }

    /// Each half-turn's tick, softer as the coin slows.
    private static let tickTimes = [0.2, 0.37, 0.6, 0.95]
    private static let tickStrength = [0.9, 0.7, 0.5, 0.3]

    var body: some View {
        GeometryReader { proxy in
            let medalCenter = CGPoint(x: proxy.size.width / 2, y: proxy.size.height * 0.36)
            ZStack {
                Color.black.opacity(0.55)

                Rays(color: MilestoneMedal.metal(for: event.milestone).light)
                    .frame(width: medalSize * 3.2, height: medalSize * 3.2)
                    .rotationEffect(.degrees(raysTurn))
                    .opacity(landed ? 1 : 0)
                    .position(medalCenter)

                // The medal's glow, still while the coin spins: a shadow on the spinning coin
                // would be re-rendered every frame.
                Circle()
                    .fill(RadialGradient(
                        colors: [MilestoneMedal.metal(for: event.milestone).base.opacity(0.7), .clear],
                        center: .center, startRadius: medalSize * 0.3, endRadius: medalSize * 0.85
                    ))
                    .frame(width: medalSize * 1.7, height: medalSize * 1.7)
                    .opacity(landed ? 1 : 0)
                    .position(medalCenter)
                    .allowsHitTesting(false)

                medal
                    .position(medalCenter)

                words
                    .frame(maxWidth: min(proxy.size.width - 48, Metrics.panelWidth))
                    .position(x: proxy.size.width / 2, y: medalCenter.y + medalSize * 0.5 + 110)

                Text("Tap to continue")
                    .font(Typography.label)
                    .foregroundStyle(.secondary)
                    .opacity(hintShown ? 1 : 0)
                    .position(x: proxy.size.width / 2, y: proxy.size.height - proxy.safeAreaInsets.bottom - 40)

                ConfettiView(bursts: bursts)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onDismiss)
            .onAppear { play(around: medalCenter) }
        }
        .ignoresSafeArea()
        .sensoryFeedback(trigger: ticks) { _, tick in
            tick > 0 ? Haptics.coinTick(Self.tickStrength[min(tick - 1, Self.tickStrength.count - 1)]) : nil
        }
        .sensoryFeedback(Haptics.medalLanded, trigger: thuds)
        .sensoryFeedback(Haptics.milestone, trigger: successes)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits([.isModal, .isButton])
        .accessibilityHint("Double-tap to continue")
        .accessibilityAction(.default, onDismiss)
    }

    private var medal: some View {
        MilestoneMedal(milestone: event.milestone, outlines: outlines, size: medalSize)
            .overlay {
                // A highlight sweeping across the metal.
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.35),
                        .init(color: .white.opacity(0.55), location: 0.5),
                        .init(color: .clear, location: 0.65),
                    ],
                    startPoint: UnitPoint(x: shine, y: shine),
                    endPoint: UnitPoint(x: shine + 1, y: shine + 1)
                )
                .clipShape(Circle())
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
            }
            .modifier(CoinSpin(angle: spin))
            .offset(y: landed || reduceMotion ? 0 : -700)
            .scaleEffect(reduceMotion && !landed ? 0.9 : 1)
            .opacity(reduceMotion && !landed ? 0 : 1)
            .accessibilityHidden(true)
    }

    private var words: some View {
        VStack(spacing: 10) {
            Text(verbatim: title)
                .font(Typography.largeTitle)
                .multilineTextAlignment(.center)
                .scaleEffect(wordsShown || reduceMotion ? 1 : 0.6)
                .opacity(wordsShown ? 1 : 0)
            Group {
                Text(verbatim: subtitle)
                    .font(Typography.headline)
                if let next {
                    Text(verbatim: next)
                        .font(Typography.body)
                        .foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.center)
            .offset(y: wordsShown || reduceMotion ? 0 : 16)
            .opacity(wordsShown ? 1 : 0)
            .animation((reduceMotion ? Motion.smooth : Motion.bouncy).delay(0.08), value: wordsShown)
        }
    }

    // Plain strings, so the screen and VoiceOver's announcement say the same thing.

    private var title: String {
        switch event.milestone {
        case .countries(let count):
            count >= 195 ? String(localized: "Every country in the world!") : String(localized: "\(count) countries!")
        case .continent(let continent):
            String(localized: "Hello, \(String(localized: continent.name))!")
        }
    }

    private var subtitle: String {
        switch event.milestone {
        case .countries:
            String(localized: "That's \(event.worldShare.formatted(.percent.precision(.fractionLength(0)))) of the world.")
        case .continent:
            String(localized: "First stop: \(RegionDisplay.name(for: event.place))")
        }
    }

    private var next: String? {
        switch event.milestone {
        case .countries:
            event.milestone.nextCountryThreshold.map { String(localized: "Next goal: \($0)") }
        case .continent:
            event.remainingOnContinent.flatMap { $0 > 0 ? String(localized: "\($0) more countries here") : nil }
        }
    }

    private func play(around center: CGPoint) {
        AccessibilityNotification.Announcement(title + " " + subtitle).post()
        guard !reduceMotion else {
            withAnimation(Motion.smooth) {
                landed = true
                wordsShown = true
                hintShown = true
            }
            successes += 1
            return
        }

        withAnimation(Motion.celebrate) { landed = true }
        withAnimation(Motion.coinSpin) { spin = 720 }
        withAnimation(.linear(duration: 28).repeatForever(autoreverses: false)) { raysTurn = 360 }

        Task {
            var elapsed = 0.0
            for time in Self.tickTimes {
                try? await Task.sleep(for: .seconds(time - elapsed))
                elapsed = time
                ticks += 1
                if ticks == 1 {
                    // About when it first touches down.
                    try? await Task.sleep(for: .seconds(0.05))
                    elapsed += 0.05
                    thuds += 1
                    let colors = [MilestoneMedal.metal(for: event.milestone).light, .white, Palette.capital] + Palette.candy
                    bursts = [-0.75, 0, 0.75].map { $0 * medalSize }.map { dx in
                        ConfettiBurst(origin: CGPoint(x: center.x + dx, y: center.y), colors: colors)
                    }
                    withAnimation(Motion.bouncy) { wordsShown = true }
                    successes += 1
                }
            }
            try? await Task.sleep(for: .seconds(0.3))
            withAnimation(Motion.smooth) { hintShown = true }
            // The highlight sweeps by every few seconds while the medal is up.
            withAnimation(.easeInOut(duration: 1.1).delay(0.2).repeatForever(autoreverses: false)) { shine = 1 }
        }
    }
}

/// Turns the coin about its vertical axis. Past edge-on it shows its face again rather than
/// the mirror image, as if both sides were struck the same.
private struct CoinSpin: ViewModifier, Animatable {
    /// Degrees.
    var angle: Double

    nonisolated var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        content
            .scaleEffect(x: cos(angle * .pi / 180) < 0 ? -1 : 1)
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
    }
}

/// Soft light rays fanning out behind the medal.
private struct Rays: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2
            let count = 14
            for index in 0..<count {
                let angle = Double(index) / Double(count) * 2 * .pi
                let half = 0.09
                var ray = Path()
                ray.move(to: center)
                ray.addLine(to: CGPoint(x: center.x + cos(angle - half) * radius, y: center.y + sin(angle - half) * radius))
                ray.addLine(to: CGPoint(x: center.x + cos(angle + half) * radius, y: center.y + sin(angle + half) * radius))
                ray.closeSubpath()
                context.fill(ray, with: .radialGradient(
                    Gradient(colors: [color.opacity(0.4), color.opacity(0)]),
                    center: center, startRadius: radius * 0.15, endRadius: radius
                ))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview {
    ZStack {
        SpaceBackground()
        MilestoneCelebration(
            event: MilestoneEvent(milestone: .countries(25), place: "IT", worldShare: 25.0 / 195, remainingOnContinent: nil),
            outlines: nil,
            onDismiss: {}
        )
    }
    .preferredColorScheme(.dark)
}
