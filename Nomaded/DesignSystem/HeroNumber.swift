import SwiftUI

/// The single big number a screen leads with ("27 countries visited"). One per screen.
/// Digits roll when the value changes, and count up from zero when it first appears.
struct HeroNumber: View {
    let value: Int
    let caption: LocalizedStringKey

    /// Proportional digits at display size; `.monospacedDigit()` would make "121" look loose.
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 72
    @State private var shown = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            Text(shown, format: .number)
                .font(.system(size: size, weight: .heavy, design: .rounded))
                .contentTransition(.numericText(value: Double(shown)))
            Text(caption)
                .font(Typography.label)
                .foregroundStyle(.secondary)
        }
        // Huge accessibility sizes would push the number off screen.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(caption))
        .accessibilityValue(Text(value, format: .number))
        .onAppear { show(value) }
        .onChange(of: value) { _, newValue in show(newValue) }
    }

    private func show(_ target: Int) {
        if reduceMotion {
            shown = target
        } else {
            withAnimation(Motion.bouncy) { shown = target }
        }
    }
}

#Preview {
    HeroNumber(value: 27, caption: "countries visited")
        .padding()
        .background(SpaceBackground())
}
