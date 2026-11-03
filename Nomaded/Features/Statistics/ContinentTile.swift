import SwiftUI

/// One continent on the statistics screen: a mini-map where visited countries pop up one by
/// one, west to east, then its count and a meter.
struct ContinentTile: View {
    let progress: WorldStats.ContinentProgress
    /// `nil` while the maps are still being built.
    let outlines: [ContinentMaps.Outline]?
    let visited: Set<String>
    /// When this tile's animation starts, counted from the screen opening.
    let delay: Double

    @ScaledMetric(relativeTo: .body) private var mapHeight = 104

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ContinentMap(outlines: outlines ?? [], visited: visited, delay: delay)
                .frame(height: mapHeight)
                .frame(maxWidth: .infinity)

            HStack(alignment: .firstTextBaseline) {
                Text(progress.continent.name)
                    .font(Typography.label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 4)
                if progress.countries.total == 0, progress.isVisited {
                    // Antarctica has no countries to count, only "been there".
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Palette.accentLight)
                        .accessibilityLabel("Visited")
                }
            }

            if progress.countries.total > 0 {
                HStack(spacing: 8) {
                    CountUp(value: progress.countries.visited, total: progress.countries.total, delay: delay)
                    Meter(share: progress.countries.share, delay: delay)
                }
            }
        }
        .padding(14)
        .glassCard(cornerRadius: 22)
        .accessibilityElement(children: .combine)
    }
}

/// The map itself. Unvisited countries sit in the globe's land shades, visited ones pop
/// up in their candy color on a spring, staggered from west to east.
private struct ContinentMap: View {
    let outlines: [ContinentMaps.Outline]
    let visited: Set<String>
    let delay: Double

    @State private var start: Date?
    /// Every country has landed: the timeline stops and the map stays still.
    @State private var isDone = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Visited countries of this continent in pop order, with each one's start time.
    private var pops: [(code: String, start: Double)] {
        let codes = outlines.filter { $0.isHome && visited.contains($0.code) }
            .sorted { $0.center.x < $1.center.x }
            .map(\.code)
        // Keep the whole wave under a second, however many countries there are.
        let step = min(Motion.stagger * 1.4, 0.9 / Double(max(codes.count, 1)))
        return codes.enumerated().map { ($1, delay + Double($0) * step) }
    }

    var body: some View {
        let pops = Dictionary(uniqueKeysWithValues: self.pops.map { ($0.code, $0.start) })
        let end = (pops.values.max() ?? delay) + Motion.pop.settlingDuration
        TimelineView(.animation(paused: start == nil || isDone || reduceMotion)) { timeline in
            let elapsed = isDone || reduceMotion ? .infinity : start.map { timeline.date.timeIntervalSince($0) } ?? 0
            Canvas { context, size in
                draw(in: &context, size: size, pops: pops, elapsed: elapsed)
            }
        }
        .onChange(of: outlines.isEmpty, initial: true) { _, isEmpty in
            // The countdown starts once there's something to draw.
            if !isEmpty, start == nil { start = .now }
        }
        .task(id: start) {
            guard start != nil else { return }
            try? await Task.sleep(for: .seconds(end))
            isDone = true
        }
        .accessibilityHidden(true)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, pops: [String: Double], elapsed: Double) {
        // The frame's radius fits the shorter side; the longer side shows a bit more around it.
        let scale = min(size.width, size.height) / 2
        let toTile = CGAffineTransform(translationX: size.width / 2, y: size.height / 2).scaledBy(x: scale, y: scale)
        let dot = max(2.5, scale * 0.035)

        for outline in outlines {
            let idle = Color(components: Palette.idleLandShades[outline.colorSlot % Palette.idleLandShades.count])
            guard outline.isHome else {
                context.fill(outline.path.applying(toTile), with: .color(idle.opacity(0.35)), style: FillStyle(eoFill: true))
                continue
            }
            guard let popStart = pops[outline.code] else {
                if !outline.isTiny {
                    context.fill(outline.path.applying(toTile), with: .color(idle), style: FillStyle(eoFill: true))
                }
                continue
            }

            // 0 → 1 with an overshoot, like a tossed sticker landing.
            let t = max(0, elapsed - popStart)
            let value = elapsed.isInfinite ? 1 : Motion.pop.value(target: 1.0, time: t)
            let candy = Palette.candy[outline.colorSlot % Palette.candy.count]
            let center = outline.center.applying(toTile)

            if outline.isTiny {
                let radius = dot * max(0, value)
                context.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                             with: .color(candy.opacity(min(1, value * 2))))
                continue
            }

            let shape = outline.path.applying(toTile)
            context.fill(shape, with: .color(idle), style: FillStyle(eoFill: true))
            guard value > 0.001 else { continue }
            let grow = 0.35 + 0.65 * value
            let popped = shape.applying(
                CGAffineTransform(translationX: center.x, y: center.y)
                    .scaledBy(x: grow, y: grow)
                    .translatedBy(x: -center.x, y: -center.y)
            )
            context.fill(popped, with: .color(candy.opacity(min(1, value * 1.6))), style: FillStyle(eoFill: true))
        }
    }
}

/// "12 of 44", counting up from zero when the tile appears.
private struct CountUp: View {
    let value: Int
    let total: Int
    let delay: Double

    @State private var shown = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text("\(shown) of \(total)")
            .font(Typography.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .contentTransition(.numericText(value: Double(shown)))
            .onAppear {
                if reduceMotion {
                    shown = value
                } else {
                    withAnimation(Motion.bouncy.delay(delay)) { shown = value }
                }
            }
    }
}

/// A thin single-hue bar: one ratio against a whole.
struct Meter: View {
    /// 0…1.
    let share: Double
    let delay: Double

    @State private var shown = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Capsule()
            .fill(Palette.accent.opacity(0.2))
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(LinearGradient(colors: [Palette.accent, Palette.accentLight], startPoint: .leading, endPoint: .trailing))
                        // A sliver even at 1%, so a start reads as a start.
                        .frame(width: shown > 0 ? max(proxy.size.height, proxy.size.width * shown) : 0)
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)
            .onAppear {
                if reduceMotion {
                    shown = share
                } else {
                    withAnimation(Motion.bouncy.delay(delay + 0.1)) { shown = share }
                }
            }
    }
}

extension Color {
    /// sRGB components in 0…1, as the globe's palette stores them.
    init(components: SIMD3<Float>) {
        self.init(red: Double(components.x), green: Double(components.y), blue: Double(components.z))
    }
}
