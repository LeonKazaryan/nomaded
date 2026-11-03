import SwiftUI

/// The countries you've been to, alphabetically, dropping down from the counter at the top.
/// Territories follow under their own heading, matching the counter's "+N". Nothing but the
/// list: tapping a place flies the globe there.
struct VisitedCountriesPanel: View {
    /// Each already in display order.
    let places: VisitedPlaces
    let onPick: (String) -> Void

    @ScaledMetric(relativeTo: .body) private var rowHeight = 56

    var body: some View {
        Group {
            if places.countries.isEmpty, places.territories.isEmpty {
                Text("No visited countries yet")
                    .font(Typography.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: rowHeight)
                    .glassCard(cornerRadius: 24)
            } else {
                CountryList(codes: places.countries, territories: places.territories, onPick: onPick)
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
            VisitedCountriesPanel(places: VisitedPlaces(countries: ["IT", "JP", "KZ", "PT"], territories: ["GL"]), onPick: { _ in })
            VisitedCountriesPanel(places: VisitedPlaces(), onPick: { _ in })
        }
        .padding(16)
    }
    .preferredColorScheme(.dark)
}
