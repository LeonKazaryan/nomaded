import RealityKit
import SwiftUI

/// The interactive globe: RealityKit scene, gestures and screen-space shading.
struct GlobeView: View {
    let controller: GlobeController

    var body: some View {
        GeometryReader { proxy in
            RealityView { content in
                content.camera = .virtual
                content.add(await controller.makeScene())
                let subscription = content.subscribe(to: SceneEvents.Update.self) { [weak controller] event in
                    let deltaTime = event.deltaTime
                    // RealityKit delivers scene updates on the main thread.
                    MainActor.assumeIsolated { controller?.tick(deltaTime: deltaTime) }
                }
                controller.retain(subscription)
            }
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
            .onChanged { value in controller.pinchChanged(magnification: value.magnification) }
            .onEnded { _ in controller.pinchEnded() }
    }
}

/// Lighting drawn over the flat, unlit globe: darker edges, a soft key light and the
/// atmosphere glow. It lines up with the 3D sphere because both use `GlobeCamera`.
private struct GlobeShading: View {
    let radius: Double

    var body: some View {
        let glow = radius * 1.45
        ZStack {
            Circle()
                .fill(RadialGradient(
                    stops: [
                        .init(color: .clear, location: 0.5),
                        .init(color: .black.opacity(0.22), location: 0.82),
                        .init(color: .black.opacity(0.5), location: 1),
                    ],
                    center: .center, startRadius: 0, endRadius: radius
                ))
                .frame(width: radius * 2, height: radius * 2)

            Circle()
                .fill(RadialGradient(
                    colors: [.white.opacity(0.16), .clear],
                    center: UnitPoint(x: 0.3, y: 0.25), startRadius: 0, endRadius: radius * 1.1
                ))
                .frame(width: radius * 2, height: radius * 2)

            Circle()
                .fill(RadialGradient(
                    stops: [
                        .init(color: Palette.atmosphere.opacity(0), location: 0.84 / 1.45),
                        .init(color: Palette.atmosphere.opacity(0.5), location: 0.995 / 1.45),
                        .init(color: Palette.atmosphere.opacity(0.3), location: 1.03 / 1.45),
                        .init(color: Palette.atmosphere.opacity(0.08), location: 1.18 / 1.45),
                        .init(color: Palette.atmosphere.opacity(0), location: 1),
                    ],
                    center: .center, startRadius: 0, endRadius: glow
                ))
                .frame(width: glow * 2, height: glow * 2)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
