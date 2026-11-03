import SwiftUI

/// The countries you've been to, alphabetically, dropping down from the counter at the top.
/// Nothing but the list: tapping a country flies the globe there.
struct VisitedCountriesPanel: View {
    /// Already in display order.
    let codes: [String]
    let onPick: (String) -> Void

    @ScaledMetric(relativeTo: .body) private var rowHeight = 56

    var body: some View {
        Group {
            if codes.isEmpty {
                Text("No visited countries yet")
                    .font(Typography.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: rowHeight)
                    .glassCard(cornerRadius: 24)
            } else {
                CountryList(codes: codes, onPick: onPick)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Visited countries")
    }
}

#Preview {
    ZStack {
        SpaceBackground()
        VStack(spacing: 16) {
            VisitedCountriesPanel(codes: ["IT", "JP", "KZ", "PT"], onPick: { _ in })
            VisitedCountriesPanel(codes: [], onPick: { _ in })
        }
        .padding(16)
    }
    .preferredColorScheme(.dark)
}
