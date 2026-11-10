import SwiftUI

/// Everything tappable squishes a little under the finger, and lights up under an iPad's
/// pointer (in the label's `.hoverEffect` content shape, if it sets one).
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .hoverEffect()
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

/// Full-width capsule for the main action on a card.
struct CapsuleButtonStyle: ButtonStyle {
    enum Kind {
        /// The primary action.
        case accent
        /// A done / selected state, e.g. "Visited".
        case inverted
        /// A secondary action.
        case subtle
    }

    var kind: Kind = .accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.headline)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(background, in: Capsule())
            .contentShape(Capsule())
            .contentShape(.hoverEffect, Capsule())
            .hoverEffect()
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }

    private var foreground: AnyShapeStyle {
        switch kind {
        case .accent: AnyShapeStyle(.white)
        case .inverted: AnyShapeStyle(Palette.accent)
        case .subtle: AnyShapeStyle(.primary)
        }
    }

    private var background: AnyShapeStyle {
        switch kind {
        case .accent: AnyShapeStyle(Palette.accent)
        case .inverted: AnyShapeStyle(.white)
        case .subtle: AnyShapeStyle(.white.opacity(0.12))
        }
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}

extension ButtonStyle where Self == CapsuleButtonStyle {
    static func capsule(_ kind: CapsuleButtonStyle.Kind = .accent) -> CapsuleButtonStyle {
        CapsuleButtonStyle(kind: kind)
    }
}
