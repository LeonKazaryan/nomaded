import SwiftUI

/// The first-launch steps, in order.
enum OnboardingStep: Hashable {
    /// The globe arrives out of hyperspace; the app introduces itself.
    case welcome
    /// "Where have you been?": pick countries in a list or on the globe.
    case pick
    /// The picks light up across the globe; the numbers and a few tips.
    case ready
}

/// The band of the screen a step leaves free for the globe, in screen points. A missing edge
/// is the screen's own.
struct GlobeRoom: Equatable {
    var top: Double?
    var bottom: Double?

    /// How the camera frames the globe to sit centred in the room, as large as fits with a
    /// little air but never past its normal size: the lift of its centre above the screen's
    /// middle, and the zoom. `nil` until the step has said where its content starts.
    func framing(in screen: CGSize, defaultTop: Double) -> (offset: Double, zoom: Double)? {
        guard let bottom else { return nil }
        let top = self.top ?? defaultTop
        let fits = (bottom - top) * 0.9 / (screen.width * GlobeTuning.baseDiameterRatio)
        return (screen.height / 2 - (top + bottom) / 2, min(fits, 1))
    }
}

/// First launch, over the live globe. Each step says where its content sits, and the globe
/// springs into the room left between, so nothing covers it at any text size.
struct OnboardingFlow: View {
    @Binding var step: OnboardingStep
    let controller: GlobeController
    /// A country picked in the list (or on the globe, which the screen routes here too).
    let onToggle: (String) -> Void
    let onFinish: () -> Void

    @State private var rooms: [OnboardingStep: GlobeRoom] = [:]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                switch step {
                case .welcome:
                    WelcomeStep(
                        isGlobeReady: controller.isReady,
                        globeRoom: room(for: .welcome),
                        onStart: { go(to: .pick) }
                    )
                    .transition(.opacity)
                case .pick:
                    PickCountriesStep(
                        controller: controller,
                        globeRoom: room(for: .pick),
                        onToggle: onToggle,
                        onDone: { go(to: .ready) }
                    )
                    .transition(.opacity)
                case .ready:
                    ReadyStep(controller: controller, globeRoom: room(for: .ready), onFinish: onFinish)
                        .transition(.opacity)
                }
            }
            .onChange(of: step) { fitGlobe(in: proxy) }
            .onChange(of: rooms[step]) { fitGlobe(in: proxy) }
        }
    }

    private func room(for step: OnboardingStep) -> Binding<GlobeRoom> {
        Binding(get: { rooms[step] ?? GlobeRoom() }, set: { rooms[step] = $0 })
    }

    private func go(to next: OnboardingStep) {
        withAnimation(reduceMotion ? Motion.smooth : Motion.bouncy) { step = next }
    }

    private func fitGlobe(in proxy: GeometryProxy) {
        let frame = proxy.frame(in: .global)
        let screen = CGSize(width: frame.width, height: frame.maxY + proxy.safeAreaInsets.bottom)
        // With no title above it, the globe stops just under the status bar.
        guard let framing = rooms[step]?.framing(in: screen, defaultTop: frame.minY + 8) else { return }
        controller.frame(offset: framing.offset, zoom: framing.zoom)
    }
}

extension View {
    /// Reports where this view starts (`.top`) or ends (`.bottom`) on screen, as its layout
    /// settles, not while it's animating.
    func onScreenEdge(_ edge: VerticalEdge, perform action: @escaping (Double) -> Void) -> some View {
        onGeometryChange(for: Double.self) { proxy in
            let frame = proxy.frame(in: .global)
            return edge == .top ? frame.minY : frame.maxY
        } action: { action($0) }
    }
}
