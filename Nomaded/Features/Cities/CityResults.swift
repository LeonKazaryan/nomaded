import SwiftUI

/// What a city search found, in a glass card, or a line saying why there's nothing to show.
/// Shared by the search in a country's card and the Cities tab of the main search.
struct CityResults: View {
    let search: CitySearch
    /// Shown before anything's typed.
    let hint: LocalizedStringKey
    let onPick: (CitySearch.Result) -> Void

    @ScaledMetric(relativeTo: .body) private var rowHeight = 58

    var body: some View {
        Group {
            if let note {
                Text(note)
                    .font(Typography.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: rowHeight)
                    .padding(.horizontal, 16)
                    .glassCard(cornerRadius: 24)
                    .transition(.opacity)
            } else {
                list
            }
        }
        .animation(Motion.snappy, value: note == nil)
    }

    private var note: LocalizedStringKey? {
        switch search.problem {
        case .offline: return "Can't reach Maps. Check the connection and try again."
        case .otherCountry: return "That city is in another country"
        case .notOnGlobe: return "That place isn't on the globe"
        case nil: break
        }
        if search.query.trimmingCharacters(in: .whitespaces).isEmpty { return hint }
        if search.results.isEmpty { return "No cities found" }
        return nil
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(search.results) { result in
                    Button {
                        onPick(result)
                    } label: {
                        row(result)
                    }
                    .buttonStyle(.pressable)
                    .disabled(search.resolving != nil)
                }
            }
            .padding(.vertical, 6)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: CGFloat(search.results.count) * rowHeight + 12)
        .glassCard(cornerRadius: 24)
    }

    private func row(_ result: CitySearch.Result) -> some View {
        HStack(spacing: 14) {
            Group {
                if search.resolving == result.id {
                    ProgressView()
                } else if result.isCapital {
                    Image(systemName: "star.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Palette.capital)
                        .accessibilityLabel("Capital")
                } else {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Palette.accentLight)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: result.title)
                    .font(Typography.body)
                    .foregroundStyle(.primary)
                if !result.subtitle.isEmpty {
                    Text(verbatim: result.subtitle)
                        .font(Typography.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .frame(minHeight: rowHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
