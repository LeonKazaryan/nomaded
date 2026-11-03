import SwiftUI

/// Compact card for the selected country with the main action.
///
/// Once the country is marked, the button splits: a small ✓ stays (tap to unmark) and
/// "Next country" grows out of it, so adding countries one after another is a single tap.
struct CountryPeekCard: View {
    let code: String
    let isVisited: Bool
    let onToggleVisited: () -> Void
    let onFindNext: () -> Void
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .headline) private var buttonHeight = 54

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

            HStack(spacing: 10) {
                Button(action: onToggleVisited) {
                    HStack(spacing: 8) {
                        Image(systemName: isVisited ? "checkmark.seal.fill" : "plus.circle.fill")
                            .contentTransition(.symbolEffect(.replace))
                        if !isVisited {
                            Text("Mark as visited")
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .transition(.opacity)
                        }
                    }
                }
                .buttonStyle(.capsule(isVisited ? .inverted : .accent))
                .frame(width: isVisited ? buttonHeight : nil)
                .accessibilityLabel(isVisited ? "Visited" : "Mark as visited")
                .accessibilityAddTraits(isVisited ? .isSelected : [])
                .accessibilityHint(isVisited ? "Removes the country from your visited list" : "")

                if isVisited {
                    Button(action: onFindNext) {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                            Text("Next country")
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                    .buttonStyle(.capsule(.accent))
                    .transition(nextTransition)
                }
            }
        }
        .padding(20)
        .glassCard(cornerRadius: 30)
        .animation(reduceMotion ? Motion.snappy : Motion.bouncy, value: isVisited)
    }

    /// Grows out of the ✓ next to it; Reduce Motion just fades it in.
    private var nextTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .scale(scale: 0.4, anchor: .leading).combined(with: .opacity),
                removal: .opacity
            )
    }
}

#Preview {
    ZStack {
        SpaceBackground()
        VStack(spacing: 16) {
            CountryPeekCard(code: "IT", isVisited: false, onToggleVisited: {}, onFindNext: {}, onClose: {})
            CountryPeekCard(code: "KZ", isVisited: true, onToggleVisited: {}, onFindNext: {}, onClose: {})
        }
        .padding(16)
    }
    .preferredColorScheme(.dark)
}
