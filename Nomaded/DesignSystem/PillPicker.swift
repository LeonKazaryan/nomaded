import SwiftUI

/// A few options in a glass capsule, each with an optional count. The accent highlight
/// slides over to the chosen one, like `FloatingTabBar`'s.
struct PillPicker<ID: Hashable>: View {
    struct Option: Identifiable {
        let id: ID
        let title: LocalizedStringKey
        var count: Int?
    }

    let options: [Option]
    @Binding var selection: ID

    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options) { option in
                button(for: option, isSelected: option.id == selection)
            }
        }
        .padding(4)
        .glass(Capsule())
        .sensoryFeedback(Haptics.select, trigger: selection)
    }

    private func button(for option: Option, isSelected: Bool) -> some View {
        Button {
            withAnimation(Motion.bouncy) { selection = option.id }
        } label: {
            label(for: option)
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(Palette.accent)
                            .matchedGeometryEffect(id: "highlight", in: highlight)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func label(for option: Option) -> some View {
        HStack(spacing: 6) {
            Text(option.title)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let count = option.count {
                Text(count, format: .number)
                    .monospacedDigit()
                    .opacity(0.7)
                    .contentTransition(.numericText(value: Double(count)))
            }
        }
        .font(Typography.label)
    }
}

#Preview {
    @Previewable @State var selection = 0
    PillPicker(
        options: [
            .init(id: 0, title: "Nomaded", count: 12),
            .init(id: 1, title: "Undiscovered", count: 32),
        ],
        selection: $selection
    )
    .padding()
    .background(SpaceBackground())
}
