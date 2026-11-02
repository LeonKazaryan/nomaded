import SwiftUI

/// A labelled number on a glass tile: "Continents 5 of 7".
/// Text stays in neutral ink; color only goes on the icon.
struct StatTile: View {
    let label: LocalizedStringKey
    let value: Int
    let systemImage: String
    /// Optional context after the value, e.g. "of 7".
    var detail: LocalizedStringKey?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(label)
            } icon: {
                Image(systemName: systemImage).foregroundStyle(Palette.accentLight)
            }
            .font(Typography.caption)
            .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value, format: .number.notation(.compactName))
                    .font(Typography.statValue)
                    .contentTransition(.numericText(value: Double(value)))
                if let detail {
                    Text(detail)
                        .font(Typography.label)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassCard(cornerRadius: 22)
        .animation(Motion.bouncy, value: value)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    HStack {
        StatTile(label: "Continents", value: 5, systemImage: "globe.americas.fill", detail: "of 7")
        StatTile(label: "Cities", value: 64, systemImage: "building.2.fill")
    }
    .padding()
    .background(SpaceBackground())
}
