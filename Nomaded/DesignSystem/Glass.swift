import SwiftUI

extension View {
    /// Frosted floating surface: material, a hairline highlight along the top edge and a
    /// soft shadow so it lifts off the globe.
    ///
    /// When we move to the iOS 26 SDK, this is the one place to adopt Liquid Glass
    /// (`glassEffect`) behind `if #available(iOS 26, *)`.
    func glass<S: InsettableShape>(_ shape: S) -> some View {
        background {
            // The shadow goes on the surface only. On the whole view SwiftUI would blur a
            // separate shadow for every glyph, flag and icon inside it.
            shape
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.3), radius: 18, y: 8)
        }
        .overlay {
            shape.strokeBorder(
                LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.04)], startPoint: .top, endPoint: .bottom),
                lineWidth: 1
            )
        }
    }

    func glassCard(cornerRadius: CGFloat = 28) -> some View {
        glass(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
