import SwiftUI

/// "Welcome back": a world that came back from iCloud (a new device, or the app installed
/// again) says where it came from, just under the counter it's filling.
struct RestoredBanner: View {
    let onDismiss: () -> Void

    @State private var hasAppeared = false

    var body: some View {
        Button(action: onDismiss) {
            HStack(spacing: 14) {
                Image(systemName: "checkmark.icloud.fill")
                    .font(Typography.title)
                    .foregroundStyle(Palette.atmosphere)
                    .symbolEffect(.bounce, value: hasAppeared)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome back")
                        .font(Typography.headline)
                    Text("Your countries and cities are back from iCloud")
                        .font(Typography.caption)
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .glassCard(cornerRadius: 24)
            .contentShape(.hoverEffect, RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.pressable)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Hides this message")
        .onAppear { hasAppeared = true }
    }
}

#Preview {
    ZStack {
        SpaceBackground()
        RestoredBanner(onDismiss: {})
            .frame(maxWidth: Metrics.panelWidth)
            .padding(16)
    }
}
