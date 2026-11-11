import SwiftUI

/// One-handed zoom, as in Zenly: a finger sliding up or down the screen's right edge zooms the
/// globe, up in and down out. A frosted rail grows out of the edge under it and fills as the
/// globe comes closer, then fades a moment after the finger lifts. A touch on the edge that
/// taps or slides sideways still reaches the globe.
struct ZoomRail: View {
    let controller: GlobeController
    /// The stretch of the right edge it may take, in window points: clear of the bar above and
    /// of the card, or an iPhone Duo's fold, below.
    let span: ClosedRange<Double>

    @State private var intent: ZoomRailScale.Intent?
    /// Where the finger was when the touch turned into a zoom: the zoom follows it from there.
    @State private var zoomStart = CGSize.zero
    /// The zoom on the rail's scale, 0…1; past the ends while it's stretched.
    @State private var level = 0.0
    @State private var isShown = false
    /// Bumped as a touch ends: the rail fades unless another one starts first.
    @State private var hides = 0
    @GestureState private var isTouching = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let width = 40.0
    /// Between the rail and the screen's edge.
    private static let margin = 8.0
    /// Shorter than this (a short screen with the card up), there's no room for a rail.
    private static let minimumLength = 160.0

    var body: some View {
        GeometryReader { proxy in
            let frame = proxy.frame(in: .global)
            let top = max(0, span.lowerBound - frame.minY)
            let bottom = min(proxy.size.height - Self.margin, span.upperBound - frame.minY)
            if bottom - top >= Self.minimumLength {
                let middle = (top + bottom) / 2
                rail(length: min(bottom - top, ZoomRailScale.length))
                    .position(x: proxy.size.width - Self.margin - Self.width / 2, y: middle)
                strip
                    .frame(width: GlobeTuning.zoomRailEdgeWidth, height: bottom - top)
                    .position(x: proxy.size.width - GlobeTuning.zoomRailEdgeWidth / 2, y: middle)
            }
        }
        .task(id: hides) { await hideSoon() }
        .sensoryFeedback(Haptics.zoomLimit, trigger: isAtLimit) { _, isAtLimit in isAtLimit }
        .onAppear { level = ZoomRailScale.level(ofZoom: controller.currentZoom) }
        // Taken away mid-touch, the touch never ends here: don't leave the globe pinched.
        .onDisappear { if intent != nil { controller.touchesEnded() } }
        #if DEBUG
        .task { await showDebugZoom() }
        #endif
    }

    private func rail(length: Double) -> some View {
        // Pulled past an end, the rail gives a little, like the volume slider.
        let overshoot = max(level - 1, -level, 0)
        return Color.clear
            .frame(width: Self.width, height: length)
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [Palette.accent, Palette.accentLight], startPoint: .bottom, endPoint: .top)
                    .frame(height: length * min(1, max(0, level)))
            }
            .clipShape(Capsule())
            .glass(Capsule())
            .overlay {
                VStack {
                    Image(systemName: "plus")
                    Spacer(minLength: 0)
                    Image(systemName: "minus")
                }
                .font(Typography.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.vertical, 14)
            }
            .scaleEffect(x: 1, y: 1 + min(0.06, overshoot * 0.4), anchor: level > 1 ? .bottom : .top)
            .opacity(isShown ? 1 : 0)
            // Slides out of the edge.
            .offset(x: isShown || reduceMotion ? 0 : Self.width + Self.margin)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var strip: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(drag)
            .onChange(of: isTouching) { _, isTouching in
                // Also when the system cancels the touch, which never reaches `onEnded`.
                if !isTouching { finish() }
            }
            .accessibilityElement()
            .accessibilityLabel("Zoom")
            .accessibilityValue(Text(min(1, max(0, level)), format: .percent.precision(.fractionLength(0))))
            .accessibilityAdjustableAction { direction in
                controller.zoom(by: direction == .increment ? 2 : 0.5)
                level = ZoomRailScale.level(ofZoom: controller.currentZoom)
            }
    }

    private var drag: some Gesture {
        // Global points are the globe's own: it fills the window.
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .updating($isTouching) { _, isTouching, _ in isTouching = true }
            .onChanged { value in
                let moved = value.translation
                switch intent {
                case nil:
                    intent = ZoomRailScale.intent(of: moved)
                    if intent == .zoom {
                        zoomStart = moved
                        show()
                    } else if intent == .spin {
                        controller.dragChanged(translation: moved)
                    }
                case .zoom:
                    controller.pinchChanged(
                        magnification: ZoomRailScale.magnification(travel: zoomStart.height - moved.height),
                        anchor: controller.camera.center
                    )
                    level = ZoomRailScale.level(ofZoom: controller.currentZoom)
                case .spin:
                    controller.dragChanged(translation: moved)
                }
            }
            .onEnded { value in
                switch intent {
                case .zoom: controller.pinchEnded()
                case .spin: controller.dragEnded(velocity: value.velocity)
                case nil: controller.tap(at: value.location)
                }
                finish()
            }
    }

    private var isAtLimit: Bool {
        intent == .zoom && (level >= 1 || level <= 0)
    }

    private func show() {
        level = ZoomRailScale.level(ofZoom: controller.currentZoom)
        withAnimation(reduceMotion ? Motion.smooth : Motion.snappy) { isShown = true }
    }

    private func finish() {
        // The zoom springs back inside its range, and the fill with it.
        if intent == .zoom { level = min(1, max(0, level)) }
        intent = nil
        controller.touchesEnded()
        hides += 1
    }

    private func hideSoon() async {
        guard hides > 0 else { return }
        try? await Task.sleep(for: .seconds(0.9))
        guard !Task.isCancelled, intent == nil else { return }
        withAnimation(Motion.smooth) { isShown = false }
    }

    #if DEBUG
    /// `-NomadedDebugZoomRail 0.6`: once the globe has flown in, the rail slides the zoom to
    /// that level and stays out, as if a finger held it there.
    private func showDebugZoom() async {
        guard let target = UserDefaults.standard.string(forKey: "NomadedDebugZoomRail").flatMap(Double.init) else { return }
        // After the intro, and after the flight to a country picked by another argument.
        try? await Task.sleep(for: .seconds(4.5))
        intent = .zoom
        show()
        let start = level
        for step in 1...40 {
            try? await Task.sleep(for: .milliseconds(16))
            let travel = (target - start) * Double(step) / 40 * ZoomRailScale.length
            controller.pinchChanged(magnification: ZoomRailScale.magnification(travel: travel), anchor: controller.camera.center)
            level = ZoomRailScale.level(ofZoom: controller.currentZoom)
        }
    }
    #endif
}

/// The zoom rail's arithmetic: the zoom on its scale, and what a touch on it means.
enum ZoomRailScale {
    enum Intent {
        case zoom, spin
    }

    /// How many times the zoom doubles from the farthest to the closest.
    private static var doublings: Double {
        let range = GlobeTuning.zoomRange
        return log2(range.upperBound / range.lowerBound)
    }

    /// As far as a finger travels across the whole zoom range, in points: the rail's length.
    static var length: Double {
        doublings * GlobeTuning.zoomRailPointsPerDoubling
    }

    /// `zoom` on the rail, on a log scale like the finger's travel: 0 the farthest, 1 the closest.
    static func level(ofZoom zoom: Double) -> Double {
        log2(max(zoom, 1e-6) / GlobeTuning.zoomRange.lowerBound) / doublings
    }

    /// What the zoom is multiplied by as the finger travels `points` up the rail (down is negative).
    static func magnification(travel points: Double) -> Double {
        pow(2, points / GlobeTuning.zoomRailPointsPerDoubling)
    }

    /// What a touch on the edge is once it has moved `translation`: nothing yet inside the tap
    /// slop (lifted there, it's a tap), then up or down zooms and sideways spins the globe.
    static func intent(of translation: CGSize) -> Intent? {
        guard hypot(translation.width, translation.height) >= GlobeTuning.tapSlop else { return nil }
        return abs(translation.height) > abs(translation.width) ? .zoom : .spin
    }
}
