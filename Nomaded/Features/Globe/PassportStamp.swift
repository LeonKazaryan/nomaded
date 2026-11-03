import SwiftUI

/// A passport stamp for a visited country: a double-ruled ink frame with the country's code
/// and the day it was first marked, tilted as if pressed by hand. Marking a country slams it
/// down onto the card: in big and turned, a thud of haptics on impact, a ring of ink.
struct PassportStamp: View {
    let code: String
    let date: Date
    let ink: Color
    /// Slam in now, rather than just be there.
    let slamsIn: Bool

    @State private var scale: Double
    @State private var turn: Double
    @State private var opacity: Double
    @State private var splash = 0.0
    @State private var impacts = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let restingTurn = -12.0

    init(code: String, date: Date, ink: Color, slamsIn: Bool) {
        self.code = code
        self.date = date
        self.ink = ink
        self.slamsIn = slamsIn
        _scale = State(initialValue: slamsIn ? 2.6 : 1)
        _turn = State(initialValue: slamsIn ? -34 : Self.restingTurn)
        _opacity = State(initialValue: slamsIn ? 0 : 1)
    }

    var body: some View {
        stamp
            .background {
                // Ink squeezed out on impact.
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(ink, lineWidth: 2)
                    .scaleEffect(1 + splash * 0.6)
                    .opacity((1 - splash) * (splash > 0 ? 0.7 : 0))
            }
            .scaleEffect(scale)
            .rotationEffect(.degrees(turn))
            .opacity(opacity)
            .sensoryFeedback(Haptics.stamp, trigger: impacts)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Visited"))
            .accessibilityValue(Text(date, format: .dateTime.day().month().year()))
            .onAppear(perform: slam)
    }

    private var stamp: some View {
        VStack(spacing: 0) {
            Text("Visited")
                .font(.system(size: 8, weight: .heavy, design: .rounded))
                .tracking(1.4)
                .textCase(.uppercase)
            Text(verbatim: code)
                .font(.system(size: 24, weight: .black, design: .rounded))
            Text(date, format: .dateTime.day().month(.abbreviated).year())
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .textCase(.uppercase)
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(ink, lineWidth: 2.2)
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(ink.opacity(0.8), lineWidth: 0.8)
                .padding(3.5)
        }
        // Ink, not paint: a touch see-through.
        .opacity(0.9)
        .fixedSize()
    }

    private func slam() {
        guard slamsIn else { return }
        if reduceMotion {
            withAnimation(Motion.smooth) {
                scale = 1
                turn = Self.restingTurn
                opacity = 1
            }
            return
        }
        withAnimation(Motion.press) { opacity = 1 }
        // Down hard, a small rebound, still.
        withAnimation(Motion.slam) {
            scale = 1
            turn = Self.restingTurn
        }
        Task {
            // Roughly when it first touches the card.
            try? await Task.sleep(for: .seconds(0.13))
            impacts += 1
            withAnimation(Motion.smooth) { splash = 1 }
        }
    }
}

#Preview {
    ZStack {
        SpaceBackground()
        PassportStamp(code: "IT", date: .now, ink: Palette.candy[0], slamsIn: true)
    }
}
