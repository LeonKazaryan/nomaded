import SwiftUI
import UIKit

extension View {
    /// Keeps the status bar a strip along the top on iPhone Duo's outer screen (iOS 27.1),
    /// instead of a column down its trailing edge (ADR-020).
    func prefersHorizontalBars() -> some View {
        background(HorizontalBarsInstaller().accessibilityHidden(true))
    }
}

/// iPhone Duo's outer screen puts the status bar in a column down the trailing edge, and every
/// app gets a safe-area inset that wide all the way down: 84 of the screen's 466 points. The
/// globe screen doesn't scroll and floats its own bar over the globe, so it takes the plain
/// status bar along the top, as Apple suggests for such layouts: the panels get the whole width
/// and sit centred under the globe. SwiftUI has no say in this yet, so the window's root view
/// controller goes into a container that answers for it and leaves the rest to SwiftUI.
private struct HorizontalBarsInstaller: UIViewRepresentable {
    func makeUIView(context: Context) -> InstallerView { InstallerView() }
    func updateUIView(_ view: InstallerView, context: Context) {}

    final class InstallerView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard #available(iOS 27.1, *), let window else { return }
            // Not while the window is being put together: the next turn of the run loop.
            DispatchQueue.main.async { HorizontalBarsController.install(in: window) }
        }
    }
}

@available(iOS 27.1, *)
private final class HorizontalBarsController: UIViewController {
    private let content: UIViewController

    static func install(in window: UIWindow) {
        guard let root = window.rootViewController, !(root is HorizontalBarsController) else { return }
        window.rootViewController = HorizontalBarsController(content: root)
    }

    private init(content: UIViewController) {
        self.content = content
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(content)
        content.view.frame = view.bounds
        content.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(content.view)
        content.didMove(toParent: self)
    }

    override var preferredVerticalBarBehavior: UIVerticalBarBehavior { .disabled }

    // Everything else is the content's call, as if it were still the root.
    override var childForStatusBarStyle: UIViewController? { content }
    override var childForStatusBarHidden: UIViewController? { content }
    override var childForHomeIndicatorAutoHidden: UIViewController? { content }
    override var childForScreenEdgesDeferringSystemGestures: UIViewController? { content }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { content.supportedInterfaceOrientations }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation { content.preferredInterfaceOrientationForPresentation }
}
