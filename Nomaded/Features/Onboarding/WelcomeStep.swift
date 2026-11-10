import SwiftUI

/// The first thing a new user sees, while the globe drops out of hyperspace behind it:
/// "Nomaded" falls into place letter by letter with a soft tick each, then the promise,
/// then the way in.
struct WelcomeStep: View {
    /// The words wait for the globe: it starts flying in once it has loaded.
    let isGlobeReady: Bool
    /// An iPad held sideways: the words stand left of the globe instead of under it.
    let sideBySide: Bool
    /// The globe stays above (or beside) the words.
    @Binding var globeRoom: GlobeRoom
    let onStart: () -> Void

    @State private var revealed = false
    @State private var letterTicks = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var sizeClass

    private static let name = Array("Nomaded")
    /// The globe is still flying in until about here.
    private static let firstLetter = 1.3
    private static let letterStep = 0.07

    var body: some View {
        Group {
            if sideBySide {
                SideColumn(globeRoom: $globeRoom) { words }
            } else {
                words
                    .frame(maxWidth: Metrics.panelWidth)
                    .onScreenEdge(.top) { globeRoom.bottom = $0 }
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 24)
            }
        }
        .sensoryFeedback(Haptics.letter, trigger: letterTicks)
        .onChange(of: isGlobeReady, initial: true) { _, isReady in
            if isReady { reveal() }
        }
    }

    private var words: some View {
        VStack(spacing: 14) {
            wordmark
            promise
            startButton
        }
    }

    private var wordmark: some View {
        HStack(spacing: 1) {
            ForEach(Array(Self.name.enumerated()), id: \.offset) { index, letter in
                letterView(letter, index: index)
            }
        }
        .font(.system(size: sizeClass == .regular ? 72 : 54, weight: .heavy, design: .rounded))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Nomaded"))
        .accessibilityAddTraits(.isHeader)
    }

    private func letterView(_ letter: Character, index: Int) -> some View {
        let delay = Self.firstLetter + Double(index) * Self.letterStep
        return Text(String(letter))
            .opacity(revealed ? 1 : 0)
            .offset(y: revealed || reduceMotion ? 0 : 26)
            .blur(radius: revealed || reduceMotion ? 0 : 8)
            .animation(reduceMotion ? Motion.smooth : Motion.bouncy.delay(delay), value: revealed)
    }

    private var promise: some View {
        VStack(spacing: 8) {
            Text("Your travel passport")
                .font(Typography.title)
            Text("Mark the countries you've been to and watch your world fill with color.")
                .font(Typography.body)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
        .opacity(revealed ? 1 : 0)
        .offset(y: revealed || reduceMotion ? 0 : 14)
        .animation(reduceMotion ? Motion.smooth : Motion.smooth.delay(Self.firstLetter + 0.6), value: revealed)
    }

    private var startButton: some View {
        Button(action: onStart) {
            Text("Get started")
        }
        .buttonStyle(.capsule(.accent))
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .scaleEffect(revealed || reduceMotion ? 1 : 0.8)
        .opacity(revealed ? 1 : 0)
        .animation(reduceMotion ? Motion.smooth : Motion.bouncy.delay(Self.firstLetter + 1.0), value: revealed)
    }

    private func reveal() {
        guard !revealed else { return }
        revealed = true
        guard !reduceMotion else { return }
        Task {
            // A soft tick as each letter lands.
            try? await Task.sleep(for: .seconds(Self.firstLetter + 0.12))
            for _ in Self.name {
                letterTicks += 1
                try? await Task.sleep(for: .seconds(Self.letterStep))
            }
        }
    }
}
