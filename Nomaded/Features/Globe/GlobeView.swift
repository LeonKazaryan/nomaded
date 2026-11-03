import SwiftUI

/// The interactive globe: Metal surface, gestures and screen-space shading.
struct GlobeView: View {
    let controller: GlobeController

    var body: some View {
        GeometryReader { proxy in
            GlobeSurface(controller: controller)
            .task { await controller.load() }
            // An overlay, not a ZStack sibling: the glow is wider than the screen and must
            // not push the globe off-center.
            .overlay {
                GlobeShading(radius: controller.camera.silhouetteRadius)
                    .opacity(controller.isReady ? 1 : 0)
                    .animation(Motion.smooth, value: controller.isReady)
            }
            .contentShape(Rectangle())
            .gesture(rotateGesture)
            .simultaneousGesture(zoomGesture)
            .onChange(of: proxy.size, initial: true) { _, size in
                controller.setViewportSize(size)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Globe")
        .accessibilityHint("Drag to spin, pinch to zoom, tap a country to select it")
    }

    private var rotateGesture: some Gesture {
        // Zero distance so a touch catches a spinning globe immediately.
        DragGesture(minimumDistance: 0)
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
            .onChanged { value in
                controller.pinchChanged(magnification: value.magnification, anchor: value.startLocation)
            }
            .onEnded { _ in controller.pinchEnded() }
    }
}

/// Hosts the Metal view. Its display link drives the controller: physics, then drawing.
private struct GlobeSurface: UIViewRepresentable {
    let controller: GlobeController

    func makeUIView(context: Context) -> GlobeMetalView {
        let view = GlobeMetalView(device: controller.device)
        view.onFrame = { [weak controller] deltaTime, layer in
            controller?.renderFrame(deltaTime: deltaTime, in: layer)
        }
        return view
    }

    func updateUIView(_ view: GlobeMetalView, context: Context) {}
}

/// Lighting drawn over the flat, unlit globe: darker edges, a soft key light and the
/// atmosphere glow. It lines up with the 3D sphere because both use `GlobeCamera`.
///
/// A screen-sized canvas rather than circle views: zoomed in, the globe is many times
/// bigger than the screen, and full-size shapes would need huge offscreen layers.
private struct GlobeShading: View {
    let radius: Double

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
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
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
