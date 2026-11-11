import SwiftUI

/// "+ City", the last of the country card's city chips.
///
/// Many people mark countries and never find out they can add cities. So every time a country
/// with no cities yet is marked, the chip lights up in the accent color and pulses twice, a
/// ring spreading off it each time, while "Where exactly? Add a city" grows out of it. A few
/// seconds later the words go back into the chip.
/// Reduce Motion: the light and the words, no pulse.
struct AddCityChip: View {
    /// The country was just marked: its stamp is slamming into the card.
    let justMarked: Bool
    /// Cities there already: nothing to point out.
    let countryHasCities: Bool
    /// Something covers the card, like a milestone: the hint waits for it to go.
    let isCovered: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = Phase.idle
    @State private var pulses = 0

    private enum Phase { case idle, waiting, showing, done }

    /// One pulse: the chip swells and settles, a ring spreads off it.
    private struct Beat {
        var scale = 1.0
        /// The ring's way out, 0…1.
        var ring = 0.0
    }

    /// After the mark, once the fill, the stamp and the confetti have had their moment. Longer
    /// than a milestone's 1.1 s, so one that's coming is already on screen and the hint waits.
    private static let lead = 1.3
    private static let pulseGap = 0.8
    /// How long the words stay.
    private static let visible = 2.8

    var body: some View {
        let isLit = phase == .showing
        Button(action: action) {
            Label("City", systemImage: "plus")
                .font(Typography.label)
                .foregroundStyle(isLit ? AnyShapeStyle(.white) : AnyShapeStyle(Palette.accentLight))
                .padding(.horizontal, 14)
                .frame(minHeight: 40)
                .background {
                    Capsule()
                        .fill(Palette.accent)
                        .shadow(color: Palette.accent.opacity(0.8), radius: 12)
                        .opacity(isLit ? 1 : 0)
                }
                .overlay(Capsule().strokeBorder(Palette.accentLight.opacity(isLit ? 0 : 0.6), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                .keyframeAnimator(initialValue: Beat(), trigger: pulses) { chip, beat in
                    chip
                        .background {
                            Capsule()
                                .stroke(Palette.accentLight, lineWidth: 2)
                                .padding(-14 * beat.ring)
                                .opacity(beat.ring > 0 ? (1 - beat.ring) * 0.9 : 0)
                        }
                        .scaleEffect(beat.scale)
                } keyframes: { _ in
                    KeyframeTrack(\.scale) {
                        SpringKeyframe(1.12, duration: 0.14, spring: Motion.pop)
                        SpringKeyframe(1, duration: 0.6, spring: Motion.pop)
                    }
                    KeyframeTrack(\.ring) {
                        MoveKeyframe(0)
                        SpringKeyframe(1, duration: 0.9, spring: Motion.ripple)
                    }
                }
                .padding(.vertical, 2)
                .contentShape(Capsule())
                .contentShape(.hoverEffect, Capsule())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Add a city")
        .overlay(alignment: .trailing) {
            if isLit {
                words
                    .padding(.leading, 10)
                    // A zero-width frame on the chip's trailing edge: the words run on to the
                    // right of it, and take no room in the row.
                    .frame(width: 0, alignment: .leading)
                    .transition(wordsTransition)
            }
        }
        // In with a bounce, back into the chip calmly.
        .animation(isLit && !reduceMotion ? Motion.bouncy : Motion.smooth, value: isLit)
        .onChange(of: justMarked) { _, marked in
            if !marked {
                // Unmarked before or while it showed: it goes quietly.
                phase = .idle
            } else if phase != .waiting, phase != .showing, !countryHasCities, !Self.isMuted {
                phase = .waiting
            }
        }
        // A milestone taking the stage cancels the wait; once it's gone, the wait starts over.
        .task(id: phase == .waiting && !isCovered) {
            guard phase == .waiting, !isCovered else { return }
            do { try await Task.sleep(for: .seconds(Self.lead)) } catch { return }
            show()
        }
        .task(id: phase) {
            guard phase == .showing else { return }
            let end = ContinuousClock.now + .seconds(Self.visible)
            do {
                if !reduceMotion {
                    pulses += 1
                    try await Task.sleep(for: .seconds(Self.pulseGap))
                    pulses += 1
                }
                try await Task.sleep(until: end)
            } catch { return }
            phase = .done
        }
    }

    /// Tapping the words adds a city too.
    private var words: some View {
        Text("Where exactly?\n**Add a city**")
            .font(Typography.caption)
            .multilineTextAlignment(.leading)
            .fixedSize()
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            // VoiceOver hears it as an announcement instead.
            .accessibilityHidden(true)
    }

    /// Grows out of the chip and shrinks back into it; Reduce Motion just fades.
    private var wordsTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .scale(scale: 0.4, anchor: .leading).combined(with: .offset(x: -16)).combined(with: .opacity),
                removal: .scale(scale: 0.7, anchor: .leading).combined(with: .opacity)
            )
    }

    private func show() {
        phase = .showing
        // After "France marked as visited", not over it.
        var message = AttributedString(localized: "Where exactly?\n**Add a city**")
        message.accessibilitySpeechAnnouncementPriority = .low
        AccessibilityNotification.Announcement(message).post()
    }

    /// Scripted debug runs (`-NomadedDebug…`) skip the hint, so screenshots stay as they were,
    /// unless `-NomadedDebugCityHint YES` asks for it.
    private static let isMuted: Bool = {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("-NomadedDebug") }
            && !UserDefaults.standard.bool(forKey: "NomadedDebugCityHint")
        #else
        false
        #endif
    }()
}

#Preview {
    @Previewable @State var marked = false
    ZStack {
        SpaceBackground()
        VStack(alignment: .leading, spacing: 24) {
            AddCityChip(justMarked: marked, countryHasCities: false, isCovered: false) {}
            Button(marked ? "Unmark" : "Mark") { marked.toggle() }
                .buttonStyle(.capsule(.subtle))
        }
        .padding(20)
        .glassCard(cornerRadius: 30)
        .padding(16)
    }
    .preferredColorScheme(.dark)
}
