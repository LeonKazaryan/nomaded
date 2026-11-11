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

/// The part of the screen a step leaves free for the globe, in screen points. A missing edge
/// is the screen's own. Usually a band above the step's content; on an iPad held sideways
/// the content is a column on the left, and the room is everything right of it.
struct GlobeRoom: Equatable {
    var top: Double?
    var bottom: Double?
    var left: Double?
    var right: Double?

    /// How the camera frames the globe to sit centred in the room, as large as fits with a
    /// little air but never past its normal size: the lift of its centre above the screen's
    /// middle, its shift right of it, and the zoom. `nil` until the step has said where its
    /// content starts.
    func framing(in screen: CGSize, defaultTop: Double) -> (offset: Double, shift: Double, zoom: Double)? {
        guard let bottom else { return nil }
        let top = self.top ?? defaultTop
        let left = self.left ?? 0
        let right = self.right ?? screen.width
        let fits = min(bottom - top, right - left) * 0.9 / GlobeTuning.baseDiameter(in: screen)
        return (screen.height / 2 - (top + bottom) / 2, (left + right) / 2 - screen.width / 2, min(fits, 1))
    }
}

/// First launch, over the live globe. Each step says where its content sits, and the globe
/// springs into the room left between, so nothing covers it at any text size. On an iPad
/// held sideways the steps stand in a column on the left and the globe takes the rest.
struct OnboardingFlow: View {
    @Binding var step: OnboardingStep
    let controller: GlobeController
    /// A country picked in the list (or on the globe, which the screen routes here too).
    let onToggle: (String) -> Void
    let onFinish: () -> Void

    /// Each step measures its room in either layout; turning the iPad picks the other one.
    private struct RoomKey: Hashable {
        let step: OnboardingStep
        let sideBySide: Bool
    }

    @State private var rooms: [RoomKey: GlobeRoom] = [:]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        GeometryReader { proxy in
            let sideBySide = sizeClass == .regular && proxy.size.width > proxy.size.height
            let key = RoomKey(step: step, sideBySide: sideBySide)
            ZStack {
                switch step {
                case .welcome:
                    WelcomeStep(
                        isGlobeReady: controller.isReady,
                        sideBySide: sideBySide,
                        globeRoom: room(for: RoomKey(step: .welcome, sideBySide: sideBySide)),
                        onStart: { go(to: .pick) }
                    )
                    .transition(.opacity)
                case .pick:
                    PickCountriesStep(
                        controller: controller,
                        sideBySide: sideBySide,
                        globeRoom: room(for: RoomKey(step: .pick, sideBySide: sideBySide)),
                        onToggle: onToggle,
                        onDone: { go(to: .ready) }
                    )
                    .transition(.opacity)
                case .ready:
                    ReadyStep(
                        controller: controller,
                        sideBySide: sideBySide,
                        globeRoom: room(for: RoomKey(step: .ready, sideBySide: sideBySide)),
                        onFinish: onFinish
                    )
                    .transition(.opacity)
                }
            }
            .onChange(of: key) { fitGlobe(rooms[key], in: proxy) }
            .onChange(of: rooms[key]) { fitGlobe(rooms[key], in: proxy) }
            .onChange(of: proxy.size) { fitGlobe(rooms[key], in: proxy) }
        }
    }

    private func room(for key: RoomKey) -> Binding<GlobeRoom> {
        Binding(get: { rooms[key] ?? GlobeRoom() }, set: { rooms[key] = $0 })
    }

    private func go(to next: OnboardingStep) {
        withAnimation(reduceMotion ? Motion.smooth : Motion.bouncy) { step = next }
    }

    private func fitGlobe(_ room: GlobeRoom?, in proxy: GeometryProxy) {
        let frame = proxy.frame(in: .global)
        let screen = CGSize(width: frame.maxX + proxy.safeAreaInsets.trailing, height: frame.maxY + proxy.safeAreaInsets.bottom)
        // With no title above it, the globe stops just under the status bar.
        guard let framing = room?.framing(in: screen, defaultTop: frame.minY + 8) else { return }
        controller.frame(offset: framing.offset, zoom: framing.zoom, shift: framing.shift)
    }
}

/// A step on an iPad held sideways: its content in a column on the left, as wide as a
/// phone, and the globe's room everything to the right of it. On an open iPhone Duo the
/// column is the left page and the room the right one.
struct SideColumn<Content: View>: View {
    @Binding var globeRoom: GlobeRoom
    @ViewBuilder var content: Content
    @Environment(\.spread) private var spread

    var body: some View {
        let columns = spread?.layout == .sideBySide ? spread?.columns(padding: 24) : nil
        HStack(spacing: columns?.gap ?? 32) {
            content
                .frame(width: columns?.first ?? Metrics.panelWidth)
                .frame(maxHeight: .infinity)
            Color.clear
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                    globeRoom = GlobeRoom(top: frame.minY, bottom: frame.maxY, left: frame.minX, right: frame.maxX)
                }
                .accessibilityHidden(true)
        }
        .padding(.leading, 24)
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
