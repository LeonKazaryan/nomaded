import SwiftUI

extension View {
    /// Closes when the scroll view is pulled down past its top and let go, like a sheet.
    /// `pull` reports how far it's stretched, for anything that should react while pulling.
    func pullToClose(_ pull: Binding<CGFloat>, distance: CGFloat = 90, onClose: @escaping () -> Void) -> some View {
        modifier(PullToClose(pull: pull, distance: distance, onClose: onClose))
    }

    /// Scrolled cards fade out under the status bar instead of running into the clock.
    func fadingUnderStatusBar() -> some View {
        mask {
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: 64)
                Rectangle()
            }
            .ignoresSafeArea()
        }
    }
}

private struct PullToClose: ViewModifier {
    @Binding var pull: CGFloat
    let distance: CGFloat
    let onClose: () -> Void

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                -(geometry.contentOffset.y + geometry.contentInsets.top)
            } action: { _, overscroll in
                pull = max(0, overscroll)
            }
            .onScrollPhaseChange { old, new in
                // Only when the finger lets go: a fling that bounces past the top doesn't count.
                if old == .interacting, new != .interacting, pull > distance { onClose() }
            }
            .sensoryFeedback(Haptics.tap, trigger: pull > distance) { _, isPastIt in isPastIt }
    }
}
