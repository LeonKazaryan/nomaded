import SwiftUI

/// Countries as tappable rows in a glass card. Short lists hug their rows; long ones scroll
/// inside whatever height the card gets. Used by search and by the visited list.
struct CountryList: View {
    let codes: [String]
    /// Gets a ✓. Search marks the ones you've been to; the visited list leaves this empty.
    var marked: Set<String> = []
    let onPick: (String) -> Void

    @ScaledMetric(relativeTo: .body) private var rowHeight = 56

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(codes, id: \.self) { code in
                    Button {
                        onPick(code)
                    } label: {
                        CountryRow(code: code, isMarked: marked.contains(code))
                            .frame(minHeight: rowHeight)
                    }
                    .buttonStyle(.pressable)
                }
            }
            .padding(.vertical, 6)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: CGFloat(codes.count) * rowHeight + 12)
        .glassCard(cornerRadius: 24)
    }
}

/// Flag and name, with a ✓ when `isMarked`.
struct CountryRow: View {
    let code: String
    let isMarked: Bool

    var body: some View {
        HStack(spacing: 14) {
            Text(verbatim: RegionDisplay.flag(for: code))
                .font(.system(size: 28))
                .accessibilityHidden(true)
            Text(verbatim: RegionDisplay.name(for: code))
                .font(Typography.body)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            if isMarked {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(Palette.accentLight)
                    .accessibilityLabel("Visited")
            }
        }
        .padding(.horizontal, 18)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    ZStack {
        SpaceBackground()
        CountryList(codes: ["IT", "JP", "KZ", "PT"], marked: ["IT"], onPick: { _ in })
            .padding(16)
    }
    .preferredColorScheme(.dark)
}
