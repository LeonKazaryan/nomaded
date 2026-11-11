import SwiftUI

/// An open iPhone Duo: the fold splits the screen into two pages, like a passport open at a
/// spread. Held like a book the pages lie left and right; turned and stood on a table like a
/// laptop, top and bottom. Everything is in window points, from the top-left corner.
struct Spread: Equatable, Sendable {
    enum Layout: Sendable {
        /// The fold runs top to bottom: pages left and right.
        case sideBySide
        /// The fold runs across: pages above and below.
        case stacked
    }

    /// The window, safe areas included.
    var window: CGSize
    /// The fold: a line while the screen lies flat, a band once it's bent.
    var fold: CGRect
    /// Room the system asks to keep clear either side of the fold.
    var margins: EdgeInsets
    var safeArea: EdgeInsets
    /// Partly closed: the halves face different ways, so nothing should lie across the fold,
    /// the globe included.
    var isBent: Bool

    var layout: Layout {
        fold.height >= fold.width ? .sideBySide : .stacked
    }

    /// The left page, or the top one, up to the fold's margin.
    var firstPage: CGRect {
        switch layout {
        case .sideBySide:
            CGRect(x: 0, y: 0, width: max(0, fold.minX - margins.leading), height: window.height)
        case .stacked:
            CGRect(x: 0, y: 0, width: window.width, height: max(0, fold.minY - margins.top))
        }
    }

    /// The right page, or the bottom one, from the fold's margin on.
    var secondPage: CGRect {
        switch layout {
        case .sideBySide:
            let x = min(window.width, fold.maxX + margins.trailing)
            return CGRect(x: x, y: 0, width: window.width - x, height: window.height)
        case .stacked:
            let y = min(window.height, fold.maxY + margins.bottom)
            return CGRect(x: 0, y: y, width: window.width, height: window.height - y)
        }
    }

    /// For content laid out in the safe area, `padding` in from the window's sides: the width of
    /// a column on each page and of the gap over the fold between them. Pages side by side.
    func columns(padding: CGFloat) -> (first: CGFloat, gap: CGFloat, second: CGFloat) {
        let start = safeArea.leading + padding
        let end = window.width - safeArea.trailing - padding
        return (
            max(0, firstPage.maxX - start),
            max(0, secondPage.minX - firstPage.maxX),
            max(0, end - secondPage.minX)
        )
    }

    /// Padding that keeps a view laid out inside the safe area to `page`.
    func insets(confiningTo page: CGRect) -> EdgeInsets {
        EdgeInsets(
            top: max(0, page.minY - safeArea.top),
            leading: max(0, page.minX - safeArea.leading),
            bottom: max(0, window.height - safeArea.bottom - page.maxY),
            trailing: max(0, window.width - safeArea.trailing - page.maxX)
        )
    }
}

extension EnvironmentValues {
    /// The open iPhone Duo's two pages; `nil` on any other screen, and on Duo while it's closed.
    @Entry var spread: Spread?
}

extension View {
    /// Reads the fold of an open iPhone Duo (iOS 27.1) into `spread`, and keeps it current as
    /// the window changes and the hinge bends. `nil` on every other screen. Put it on a view
    /// that fills the safe area.
    func readsSpread(_ spread: Binding<Spread?>) -> some View {
        modifier(SpreadReader(spread: spread))
    }
}

private struct SpreadReader: ViewModifier {
    @Binding var spread: Spread?
    @State private var measured: Spread?
    /// What the hinge says, which can come before the fold's own `isActive` does.
    @State private var isHingeBent = false

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: Spread?.self) { Self.read($0) } action: { measured = $0 }
            .modifier(HingeReader(isBent: $isHingeBent))
            .onChange(of: measured, initial: true) { publish() }
            .onChange(of: isHingeBent) { publish() }
    }

    private func publish() {
        spread = measured.map { spread in
            var spread = spread
            spread.isBent = spread.isBent || isHingeBent
            return spread
        }
    }

    private nonisolated static func read(_ proxy: GeometryProxy) -> Spread? {
        let frame = proxy.frame(in: .global)
        let safeArea = proxy.safeAreaInsets
        let window = CGSize(width: frame.maxX + safeArea.trailing, height: frame.maxY + safeArea.bottom)
        #if DEBUG
        if let simulated = simulated(window: window, safeArea: safeArea) { return simulated }
        #endif
        guard #available(iOS 27.1, *),
              let fold = proxy.reservedRegions(kind: .division, options: .includeInactive, layoutDirectionBehavior: .fixed).first
        else { return nil }
        return Spread(
            window: window,
            fold: fold.frame.offsetBy(dx: frame.minX, dy: frame.minY),
            margins: fold.margins,
            safeArea: safeArea,
            isBent: fold.isActive
        )
    }

    #if DEBUG
    /// `-NomadedDebugSpread side` (or `stacked`) draws a fold down (or across) the middle of any
    /// screen, `-NomadedDebugBent YES` bends it: the iPhone Duo's spread without one, and its
    /// postures without Device Hub.
    private nonisolated static func simulated(window: CGSize, safeArea: EdgeInsets) -> Spread? {
        let defaults = UserDefaults.standard
        guard let layout = defaults.string(forKey: "NomadedDebugSpread") else { return nil }
        let fold = layout == "stacked"
            ? CGRect(x: 0, y: window.height / 2, width: window.width, height: 0)
            : CGRect(x: window.width / 2, y: 0, width: 0, height: window.height)
        let margin = 12.0
        return Spread(
            window: window,
            fold: fold,
            margins: EdgeInsets(top: margin, leading: margin, bottom: margin, trailing: margin),
            safeArea: safeArea,
            isBent: defaults.bool(forKey: "NomadedDebugBent")
        )
    }
    #endif
}

/// The hinge, where the device has one (iOS 27.1).
private struct HingeReader: ViewModifier {
    @Binding var isBent: Bool

    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content.onHingeChange { _, context in
                isBent = context.hinge?.status == .partiallyOpen
            }
        } else {
            content
        }
    }
}
