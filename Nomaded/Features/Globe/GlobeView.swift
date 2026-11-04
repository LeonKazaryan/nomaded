import SwiftUI

/// The interactive globe: Metal surface, gestures and screen-space shading.
struct GlobeView: View {
    let controller: GlobeController

    /// SwiftUI resets these when a gesture ends *or* is cancelled; `onEnded` only runs for
    /// the first. Watching them catches the cancelled ones.
    @GestureState private var isDragging = false
    @GestureState private var isPinching = false

    var body: some View {
        GeometryReader { proxy in
            GlobeSurface(controller: controller, isPaused: controller.isPaused)
            .task { await controller.load() }
            // An overlay, not a ZStack sibling: the glow is wider than the screen and must
            // not push the globe off-center.
            .overlay {
                GlobeShading(radius: controller.camera.silhouetteRadius, center: controller.camera.center)
                    .opacity(controller.isReady ? 1 : 0)
                    .animation(Motion.smooth, value: controller.isReady)
            }
            .overlay {
                CityNames(controller: controller)
            }
            .contentShape(Rectangle())
            .gesture(rotateGesture)
            .simultaneousGesture(zoomGesture)
            .onChange(of: proxy.size, initial: true) { _, size in
                controller.setViewportSize(size)
            }
            .onChange(of: isDragging || isPinching) { _, isTouching in
                if !isTouching { controller.touchesEnded() }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Globe")
        .accessibilityHint("Drag to spin, pinch to zoom, tap a country to select it")
    }

    private var rotateGesture: some Gesture {
        // Zero distance so a touch catches a spinning globe immediately.
        DragGesture(minimumDistance: 0)
            .updating($isDragging) { _, isDragging, _ in isDragging = true }
            .onChanged { value in
                controller.dragChanged(translation: value.translation)
            }
            .onEnded { value in
                let moved = hypot(value.translation.width, value.translation.height)
                if moved < GlobeTuning.tapSlop {
                    controller.tap(at: value.location)
                } else {
                    controller.dragEnded(velocity: value.velocity)
                }
            }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .updating($isPinching) { _, isPinching, _ in isPinching = true }
            .onChanged { value in
                controller.pinchChanged(magnification: value.magnification, anchor: value.startLocation)
            }
            .onEnded { _ in controller.pinchEnded() }
    }
}

/// Hosts the Metal view. Its display link drives the controller: physics, then drawing.
private struct GlobeSurface: UIViewRepresentable {
    let controller: GlobeController
    let isPaused: Bool

    func makeUIView(context: Context) -> GlobeMetalView {
        let view = GlobeMetalView(device: controller.device)
        view.onFrame = { [weak controller] deltaTime, layer in
            controller?.renderFrame(deltaTime: deltaTime, in: layer) ?? .none
        }
        controller.onWake = { [weak view] in view?.wake() }
        return view
    }

    func updateUIView(_ view: GlobeMetalView, context: Context) {
        view.isPaused = isPaused
    }
}

/// City names over their dots. The engine places them every frame and springs each one in
/// and out (`CityLabel.appearance`); this only draws, with no animation of its own, so a
/// name never slides from anywhere but its dot. Its own view, so a moving name redraws
/// just these labels.
private struct CityNames: View {
    let controller: GlobeController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            ForEach(controller.cityLabels) { label in
                CityName(name: label.name, isHighlighted: label.isHighlighted, isCapital: label.isCapital)
                    // Grows out of the dot just below it.
                    .scaleEffect(reduceMotion ? 1 : 0.5 + 0.5 * label.appearance, anchor: .bottom)
                    .opacity(min(1, max(0, label.appearance)))
                    .position(x: label.point.x, y: label.point.y - 21)
            }
        }
        .transaction { $0.animation = nil }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A plain dark pill rather than glass: a blurred backdrop under every name would be
/// redrawn every frame the globe moves. Capitals get a star.
private struct CityName: View {
    let name: String
    let isHighlighted: Bool
    let isCapital: Bool

    var body: some View {
        HStack(spacing: 4) {
            if isCapital {
                Image(systemName: "star.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(isHighlighted ? .white : Palette.capital)
            }
            Text(verbatim: name)
                .font(Typography.caption.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(isHighlighted ? AnyShapeStyle(Palette.accent) : AnyShapeStyle(.black.opacity(0.55)), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(isHighlighted ? 0.35 : 0.12), lineWidth: 1))
        .fixedSize()
    }
}

/// Lighting drawn over the flat, unlit globe: darker edges, a soft key light and the
/// atmosphere glow. It lines up with the 3D sphere because both use `GlobeCamera`.
///
/// A screen-sized canvas rather than circle views: zoomed in, the globe is many times
/// bigger than the screen, and full-size shapes would need huge offscreen layers.
private struct GlobeShading: View {
    let radius: Double
    /// Where the globe sits in the view: not the middle while a panel is below it.
    let center: CGPoint

    private static let edges = Gradient(stops: [
        .init(color: .clear, location: 0.5),
        .init(color: .black.opacity(0.22), location: 0.82),
        .init(color: .black.opacity(0.5), location: 1),
    ])
    private static let keyLight = Gradient(colors: [.white.opacity(0.16), .clear])
    private static let glowScale = 1.45
    private static let glow = Gradient(stops: [
        .init(color: Palette.atmosphere.opacity(0), location: 0.84 / glowScale),
        .init(color: Palette.atmosphere.opacity(0.5), location: 0.995 / glowScale),
        .init(color: Palette.atmosphere.opacity(0.3), location: 1.03 / glowScale),
        .init(color: Palette.atmosphere.opacity(0.08), location: 1.18 / glowScale),
        .init(color: Palette.atmosphere.opacity(0), location: 1),
    ])

    var body: some View {
        Canvas { context, size in
            let center = self.center
            let screen = Path(CGRect(origin: .zero, size: size))
            let globe = Path(ellipseIn: CGRect(
                x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2
            ))

            var surface = context
            surface.clip(to: globe)
            surface.fill(screen, with: .radialGradient(
                Self.edges, center: center, startRadius: 0, endRadius: radius
            ))
            surface.fill(screen, with: .radialGradient(
                Self.keyLight,
                center: CGPoint(x: center.x - 0.4 * radius, y: center.y - 0.5 * radius),
                startRadius: 0, endRadius: radius * 1.1
            ))

            context.fill(screen, with: .radialGradient(
                Self.glow, center: center, startRadius: 0, endRadius: radius * Self.glowScale
            ))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
