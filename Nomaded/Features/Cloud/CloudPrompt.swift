import SwiftUI

/// "Keep your world in iCloud": this device can't sync, so marks would stay on it alone. A
/// Liquid Glass card over the dimmed screen says why it matters, the three steps to turn
/// iCloud on, and opens Settings. Turned on and back, the cloud ticks and the card goes by
/// itself. When iCloud is on but turned the marks down, the card says what iCloud said:
/// that's for whoever has to fix it.
struct CloudPrompt: View {
    let state: CloudSync.State
    let onDismiss: () -> Void

    /// Seconds the "it's in iCloud" card stays before it goes by itself.
    private static let successStay = 1.8

    @State private var appeared = false
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isSynced: Bool {
        if case .synced = state { true } else { false }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)
                .accessibilityHidden(true)
            card
                .frame(maxWidth: 420)
                .padding(20)
                .scaleEffect(appeared || reduceMotion ? 1 : 0.9)
                .offset(y: appeared || reduceMotion ? 0 : 24)
                .blur(radius: appeared || reduceMotion ? 0 : 10)
                .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(reduceMotion ? Motion.smooth : Motion.bouncy) { appeared = true }
        }
        .task(id: isSynced) {
            // iCloud came on while the card was up: it shows the tick, then goes.
            guard isSynced else { return }
            try? await Task.sleep(for: .seconds(Self.successStay))
            guard !Task.isCancelled else { return }
            onDismiss()
        }
        .sensoryFeedback(Haptics.restored, trigger: isSynced) { _, isSynced in isSynced }
    }

    private var card: some View {
        VStack(spacing: 18) {
            icon
            VStack(spacing: 8) {
                Text(title)
                    .font(Typography.title)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .font(Typography.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .fixedSize(horizontal: false, vertical: true)
            // New words come out of a blur as the old ones go into one, never both legible.
            .id(wording)
            .transition(reduceMotion ? .opacity : AnyTransition(.blurReplace))

            switch state {
            case .failed(let detail):
                VStack(alignment: .leading, spacing: 6) {
                    Text("What iCloud said")
                        .font(Typography.caption)
                        .foregroundStyle(.secondary)
                    Text(verbatim: detail)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                Button(action: onDismiss) {
                    Text("Got it").frame(maxWidth: .infinity)
                }
                .liquidPrimaryButton()
            case .synced:
                EmptyView()
            default:
                steps
                    .transition(.opacity)
                VStack(spacing: 4) {
                    Button {
                        if let settings = URL(string: UIApplication.openSettingsURLString) { openURL(settings) }
                    } label: {
                        Text("Open Settings").frame(maxWidth: .infinity)
                    }
                    .liquidPrimaryButton()
                    Button("Not now", action: onDismiss)
                        .font(Typography.label)
                        .foregroundStyle(.secondary)
                        .frame(minHeight: 44)
                        .buttonStyle(.pressable)
                }
            }
        }
        .padding(24)
        .liquidGlass(RoundedRectangle(cornerRadius: 36, style: .continuous))
        .animation(Motion.smooth, value: state)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    /// The cloud, with a soft glow behind: a warning while it can't sync, a tick once it does.
    private var icon: some View {
        Image(systemName: isSynced ? "checkmark.icloud.fill" : "exclamationmark.icloud.fill")
            .font(.system(size: 54, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(isSynced ? Palette.candy[3] : Palette.atmosphere)
            .contentTransition(.symbolEffect(.replace))
            .symbolEffect(.bounce, value: appeared)
            .symbolEffect(.bounce, value: isSynced)
            .frame(width: 96, height: 96)
            .background {
                Circle()
                    .fill(RadialGradient(
                        colors: [(isSynced ? Palette.candy[3] : Palette.atmosphere).opacity(0.35), .clear],
                        center: .center, startRadius: 0, endRadius: 48
                    ))
            }
            .accessibilityHidden(true)
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 14) {
            step(1, systemImage: "gearshape.fill", text: "Open Settings and tap your name at the top", note: "No name there? Tap Sign in to your iPhone")
            step(2, systemImage: "icloud.fill", text: "Tap iCloud and turn on iCloud Drive", note: nil)
            step(3, systemImage: "arrow.uturn.backward", text: "Come back here: your world saves itself", note: nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func step(_ number: Int, systemImage: String, text: LocalizedStringKey, note: LocalizedStringKey?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(Typography.label)
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Palette.accent, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(text)
                    .font(Typography.label)
                if let note {
                    Text(note)
                        .font(Typography.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 5)
        }
        // One after another, after the card.
        .opacity(appeared ? 1 : 0)
        .offset(x: appeared || reduceMotion ? 0 : 16)
        .animation((reduceMotion ? Motion.smooth : Motion.bouncy).delay(0.12 + Double(number) * Motion.stagger * 2), value: appeared)
        .accessibilityElement(children: .combine)
    }

    /// Which words the card says: when this changes, they change.
    private var wording: Int {
        switch state {
        case .synced: 2
        case .failed: 1
        default: 0
        }
    }

    private var title: LocalizedStringKey {
        switch state {
        case .synced: "Your world is in iCloud"
        case .failed: "Couldn't sync with iCloud"
        default: "Keep your world in iCloud"
        }
    }

    private var message: LocalizedStringKey {
        switch state {
        case .synced: "It's on all your devices now."
        case .failed: "Your marks are safe on this device. They go to iCloud as soon as it takes them."
        default: "For now your countries and cities are only on this device. With iCloud they're on all your iPhones and iPads, and come back on a new phone."
        }
    }
}

/// How iCloud is doing, in a line at the end of the statistics: saved and when, or off, or
/// failing. Off and failing open the prompt that says what to do.
struct CloudStatusLine: View {
    let state: CloudSync.State
    let onOpen: () -> Void

    var body: some View {
        switch state {
        case .off:
            EmptyView()
        case .unavailable, .failed:
            Button(action: onOpen) {
                label.contentShape(.hoverEffect, Capsule())
            }
            .buttonStyle(.pressable)
            .accessibilityHint(state == .unavailable ? "Shows how to turn on iCloud" : "Shows what went wrong")
        case .checking, .synced:
            label
        }
    }

    private var label: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .symbolRenderingMode(.hierarchical)
            text
                .foregroundStyle(.secondary)
            if state == .unavailable || isFailed {
                Image(systemName: "chevron.right")
                    .font(Typography.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .font(Typography.caption)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .liquidGlass(Capsule())
        .accessibilityElement(children: .combine)
    }

    private var isFailed: Bool {
        if case .failed = state { true } else { false }
    }

    private var symbol: String {
        switch state {
        case .synced: "checkmark.icloud.fill"
        case .unavailable: "icloud.slash.fill"
        case .failed: "exclamationmark.icloud.fill"
        default: "icloud.fill"
        }
    }

    private var tint: Color {
        switch state {
        case .synced: Palette.candy[3]
        case .unavailable, .failed: Palette.candy[1]
        default: Palette.atmosphere
        }
    }

    @ViewBuilder
    private var text: some View {
        switch state {
        case .synced(let date?): Text("Saved in iCloud · \(date, format: .relative(presentation: .named))")
        case .synced(nil): Text("iCloud is on")
        case .unavailable: Text("iCloud is off · only on this device")
        case .failed: Text("Couldn't sync with iCloud")
        default: Text("Checking iCloud…")
        }
    }
}
