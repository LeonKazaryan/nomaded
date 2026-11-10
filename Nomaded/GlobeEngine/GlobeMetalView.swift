import Metal
import QuartzCore
import UIKit

/// How often the globe needs drawing, judged after every frame.
enum FrameDemand {
    /// Something moves: as fast as the screen goes, up to 120 Hz.
    case full
    /// Only the slow idle spin: `GlobeTuning.idleSpinFrameRate` looks the same and costs less.
    case slow
    /// At rest: no frames at all, the last one stays on screen until `wake()`.
    case none
}

/// The globe's drawing surface: a Metal layer plus a display link asking for up to 120 Hz.
/// Every frame it reports the time step, and `onFrame` advances the physics, draws and
/// says how soon the next frame is needed. A globe at rest costs no power.
final class GlobeMetalView: UIView {
    override class var layerClass: AnyClass { CAMetalLayer.self }

    var metalLayer: CAMetalLayer { layer as! CAMetalLayer }
    var onFrame: ((TimeInterval, CAMetalLayer) -> FrameDemand)?
    /// Stops drawing and the physics; the last frame stays on screen.
    var isPaused = false {
        didSet {
            guard isPaused != oldValue else { return }
            // Coming back, draw at least once: things may have changed underneath.
            if !isPaused { demand = .full }
            applyDemand()
        }
    }

    private var displayLink: CADisplayLink?
    private var lastTargetTimestamp: CFTimeInterval?
    private var demand = FrameDemand.full

    init(device: MTLDevice?) {
        super.init(frame: .zero)
        metalLayer.device = device
        metalLayer.pixelFormat = GlobeRenderer.pixelFormat
        // Palette colors are sRGB; tagging the layer lets the system map them onto the P3 screen.
        metalLayer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        metalLayer.isOpaque = false
        metalLayer.framebufferOnly = true
        // Frames show in step with SwiftUI's overlays (see `GlobeRenderer.draw`).
        metalLayer.presentsWithTransaction = true
        backgroundColor = .clear
        isOpaque = false
        // The system may drop a background app's layer contents; redraw on the way back.
        NotificationCenter.default.addObserver(self, selector: #selector(wake), name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    /// Draws again after the globe came to rest, or at full rate after the idle spin. Cheap:
    /// call it on any change.
    @objc func wake() {
        guard demand != .full else { return }
        demand = .full
        applyDemand()
    }

    private func applyDemand() {
        guard let displayLink else { return }
        let stops = isPaused || demand == .none
        // Don't count the time without frames as one huge step.
        if stops || displayLink.isPaused { lastTargetTimestamp = nil }
        displayLink.isPaused = stops
        displayLink.preferredFrameRateRange = Self.frameRates(for: demand)
    }

    private static func frameRates(for demand: FrameDemand) -> CAFrameRateRange {
        let rate = GlobeTuning.idleSpinFrameRate
        return switch demand {
        case .full, .none: CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        case .slow: CAFrameRateRange(minimum: rate / 2, maximum: rate, preferred: rate)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = window?.screen.scale ?? traitCollection.displayScale
        contentScaleFactor = scale
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        guard size != metalLayer.drawableSize else { return }
        metalLayer.drawableSize = size
        wake()
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
        link.add(to: .main, forMode: .common)
        displayLink = link
        demand = .full
        applyDemand()
    }

    @objc private func step(_ link: CADisplayLink) {
        // No GPU work while the app is in the background.
        guard window?.windowScene?.activationState != .background else {
            lastTargetTimestamp = nil
            return
        }
        // Step to the time this frame will be on screen, so motion stays even when the
        // rate changes between 60 and 120. Changing rates (typing on the keyboard does it)
        // can put the target a frame before the last one: that's no time passing, never
        // time running backwards.
        let target = link.targetTimestamp
        let deltaTime = lastTargetTimestamp.map { max(0, target - $0) } ?? link.duration
        lastTargetTimestamp = max(target, lastTargetTimestamp ?? target)
        let next = onFrame?(deltaTime, metalLayer) ?? .none
        guard next != demand else { return }
        demand = next
        applyDemand()
    }
}
