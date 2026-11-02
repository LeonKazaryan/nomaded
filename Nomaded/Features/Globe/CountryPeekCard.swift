import SwiftUI

/// Compact card for the selected country with the main action.
struct CountryPeekCard: View {
    let code: String
    let isVisited: Bool
    let onToggleVisited: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Text(verbatim: RegionDisplay.flag(for: code))
                    .font(.system(size: 48))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: RegionDisplay.name(for: code))
                        .font(Typography.title)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    Text(isVisited ? "Visited" : "Not visited yet")
                        .font(Typography.label)
                        .foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                }

                Spacer(minLength: 0)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(.white.opacity(0.12), in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Close")
            }

            Button(action: onToggleVisited) {
                HStack(spacing: 8) {
                    Image(systemName: isVisited ? "checkmark.seal.fill" : "plus.circle.fill")
                        .contentTransition(.symbolEffect(.replace))
                    Text(isVisited ? "Visited" : "Mark as visited")
                }
            }
            .buttonStyle(.capsule(isVisited ? .inverted : .accent))
            .accessibilityAddTraits(isVisited ? .isSelected : [])
            .accessibilityHint(isVisited ? "Removes the country from your visited list" : "")
        }
        .padding(20)
        .glassCard(cornerRadius: 30)
        .animation(Motion.snappy, value: isVisited)
    }
}

#Preview {
    ZStack {
        SpaceBackground()
        VStack(spacing: 16) {
            CountryPeekCard(code: "IT", isVisited: false, onToggleVisited: {}, onClose: {})
            CountryPeekCard(code: "KZ", isVisited: true, onToggleVisited: {}, onClose: {})
        }
        .padding(16)
    }
    .preferredColorScheme(.dark)
}
