import Metal
import QuartzCore
import UIKit

/// The globe's drawing surface: a Metal layer plus a display link asking for up to 120 Hz.
/// Every frame it reports the time step, and `onFrame` advances the physics and draws.
final class GlobeMetalView: UIView {
    override class var layerClass: AnyClass { CAMetalLayer.self }

    var metalLayer: CAMetalLayer { layer as! CAMetalLayer }
    var onFrame: ((TimeInterval, CAMetalLayer) -> Void)?

    private var displayLink: CADisplayLink?
    private var lastTargetTimestamp: CFTimeInterval?

    init(device: MTLDevice?) {
        super.init(frame: .zero)
        metalLayer.device = device
        metalLayer.pixelFormat = GlobeRenderer.pixelFormat
        // Palette colors are sRGB; tagging the layer lets the system map them onto the P3 screen.
        metalLayer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        metalLayer.isOpaque = false
        metalLayer.framebufferOnly = true
        backgroundColor = .clear
        isOpaque = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = window?.screen.scale ?? traitCollection.displayScale
        contentScaleFactor = scale
        metalLayer.drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        displayLink?.invalidate()
        displayLink = nil
        lastTargetTimestamp = nil
        // Off screen there's nothing to draw. Dropping the link also lets go of `self`,
        // which the link holds as its target.
        guard window != nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(step))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func step(_ link: CADisplayLink) {
        // No GPU work while the app is in the background.
        guard window?.windowScene?.activationState != .background else {
            lastTargetTimestamp = nil
            return
        }
        // Step to the time this frame will be on screen, so motion stays even when the
        // rate changes between 60 and 120.
        let deltaTime = lastTargetTimestamp.map { link.targetTimestamp - $0 } ?? link.duration
        lastTargetTimestamp = link.targetTimestamp
        onFrame?(deltaTime, metalLayer)
    }
}
