import SwiftUI

/// Where things sit in a story frame (`StoryFilm.size`, points). Stories show the app's bars
/// over the top and bottom of a frame, so the words stay inside `top`…`bottom`.
enum StoryLayout {
    static let top: CGFloat = 76
    static let bottom: CGFloat = 70
    /// How far below the middle the globe sits, between the numbers and the name.
    static let globeOffset = 60.0
    /// The counter's digits, the frame's one big number.
    static let counterSize: CGFloat = 86
    static let counterWordSize: CGFloat = 26
    static let wordmarkSize: CGFloat = 26
}

// A story frame is drawn in layers, each only when it changes: deep space once, the warp
// over its first moments, the globe's shading while the globe flies in, the words as they
// come and count. Drawn offscreen at a fixed size, they don't follow Dynamic Type: a film
// looks the same whoever made it. Frames and points are top-down, as in SwiftUI.

/// Deep space behind everything.
struct StoryBackdrop: View {
    var body: some View {
        SpaceStill(time: 0)
            .frame(width: StoryFilm.size.width, height: StoryFilm.size.height)
    }
}

/// The jump out of hyperspace, `time` seconds in, behind the arriving globe.
struct StoryWarp: View {
    let time: Double

    var body: some View {
        Canvas { context, size in
            WarpField.draw(at: time, in: context, size: size)
        }
        .frame(width: StoryFilm.size.width, height: StoryFilm.size.height)
    }
}

/// The globe's shading and glow, as on screen.
struct StoryShading: View, Hashable {
    let x: Double
    let y: Double
    let radius: Double

    /// Rounded, so a globe that has settled draws the same layer every frame.
    init(center: CGPoint, radius: Double) {
        x = (center.x * 10).rounded() / 10
        y = (center.y * 10).rounded() / 10
        self.radius = (radius * 10).rounded() / 10
    }

    var body: some View {
        GlobeShading(radius: radius, center: CGPoint(x: x, y: y))
            .frame(width: StoryFilm.size.width, height: StoryFilm.size.height)
    }
}

/// When each part of the words comes in, in seconds.
enum StoryTiming {
    static let header = 0.5
    /// The counter, at the earliest: it waits for the first country.
    static let counter = 1.3
    /// The numbers come in as the camera pulls back for the finale (`StoryPlan.finale`), and
    /// the name this long after them.
    static let brandAfterFinale = 0.5
    static let reveal = 0.6
    static let pop = 0.28

    /// How far in a part that starts at `start` is, `time` seconds in: 0…1, rounded so
    /// frames a hair apart draw the same.
    static func reveal(_ start: Double, at time: Double) -> Double {
        let t = min(max((time - start) / reveal, 0), 1)
        return ((1 - pow(1 - t, 3)) * 100).rounded() / 100
    }
}

/// The words at the top of a story: the counter, and in the finale the numbers under it.
/// A strip, not a whole frame: it changes with every country counted, and a smaller layer
/// is quicker to draw and to move to the GPU.
struct StoryHeadline: View {
    /// Where it sits in the frame, with room for its parts to rise into place.
    static let frame = CGRect(x: 0, y: StoryLayout.top - 12, width: StoryFilm.size.width, height: 196)

    /// What it shows. Equal states draw equal layers: the film draws one only when this changes.
    struct State: Hashable {
        /// Countries counted so far.
        var countries: Int
        /// 0…1: how far in each part has come.
        var header: Double
        var counter: Double
        /// 1 the moment a country is counted, back to 0 a beat later.
        var pop: Double
        var finale: Double

        /// `firstCounted`: when the first country was counted, `nil` before. The counter comes
        /// in with it, never as "0 countries"; with only territories, in the finale, which
        /// starts at `finale`.
        init(time: Double, countries: Int, firstCounted: Double?, lastCounted: Double, finale: Double) {
            self.countries = countries
            header = StoryTiming.reveal(StoryTiming.header, at: time)
            counter = StoryTiming.reveal(max(StoryTiming.counter, firstCounted ?? finale), at: time)
            pop = (pow(max(0, 1 - (time - lastCounted) / StoryTiming.pop), 2) * 10).rounded() / 10
            self.finale = StoryTiming.reveal(finale, at: time)
        }
    }

    let state: State
    let stats: WorldStats
    let year: Int

    var body: some View {
        VStack(spacing: 0) {
            header
                .revealed(state.header)
            counter
                .revealed(state.counter)
            finale
                .padding(.top, 2)
                .revealed(state.finale)
        }
        .padding(.top, 12)
        .padding(.horizontal, 24)
        .multilineTextAlignment(.center)
        .frame(width: Self.frame.width, height: Self.frame.height, alignment: .top)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("My world")
                .textCase(.uppercase)
            Text(verbatim: "·")
            Text(verbatim: "\(year)")
        }
        .font(.system(size: 13, weight: .bold, design: .rounded))
        .tracking(2.4)
        .foregroundStyle(.secondary)
    }

    /// "27 countries" with the number huge, in whatever order the language puts them.
    private var counter: some View {
        let digits = state.countries.formatted()
        var phrase = AttributedString(localized: "\(state.countries) countries")
        phrase.font = .system(size: StoryLayout.counterWordSize, weight: .bold, design: .rounded)
        if let range = phrase.range(of: digits) {
            phrase[range].font = .system(size: StoryLayout.counterSize, weight: .heavy, design: .rounded)
        }
        return Text(phrase)
            .foregroundStyle(LinearGradient(colors: [.white, Palette.accentLight], startPoint: .top, endPoint: .bottom))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .scaleEffect(1 + 0.08 * state.pop)
    }

    private var finale: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Text("\(stats.countries.share.formatted(.percent.precision(.fractionLength(0)))) of the world")
                Text(verbatim: "·")
                Text("\(stats.visitedContinents) of \(stats.continents.count) continents")
            }
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            if stats.territories > 0 {
                Text("+\(stats.territories) territories")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

/// Darkens the top of the frame behind the words while the camera is in close: up close
/// the globe fills the frame, and white numbers over a lemon-yellow country don't read.
struct StoryScrim: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: Palette.night.opacity(0.85), location: 0),
                .init(color: Palette.night.opacity(0.55), location: 0.22),
                .init(color: Palette.night.opacity(0), location: 0.45),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(width: StoryFilm.size.width, height: StoryFilm.size.height)
    }
}

/// A flag on a pin, standing on a country as it fills on the tour. Drawn once per country;
/// the film pops, moves and fades it.
struct StoryPin: View {
    /// The image's size around the pin, with room for its shadow, and where its tip is.
    static let size = CGSize(width: 46, height: 54)
    static let tip = CGPoint(x: 23, y: 42)
    private static let badge = 32.0

    let flag: String

    var body: some View {
        VStack(spacing: -2) {
            Text(verbatim: flag)
                .font(.system(size: 19))
                .frame(width: Self.badge, height: Self.badge)
                .background(Circle().fill(.white))
                .overlay(Circle().strokeBorder(Palette.accentLight, lineWidth: 2))
            // The point it stands on.
            Triangle()
                .fill(.white)
                .frame(width: 10, height: 8)
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.45), radius: 4, y: 2)
        .padding(.top, 4)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .top)
    }

    private struct Triangle: Shape {
        func path(in rect: CGRect) -> Path {
            Path { path in
                path.move(to: CGPoint(x: rect.minX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
                path.closeSubpath()
            }
        }
    }

    /// How big a pin is `age` seconds after it pops up: out of nothing, a little past full
    /// size, and settling, like the app's pop spring.
    static func scale(age: Double) -> Double {
        guard age > 0 else { return 0 }
        let damping = 0.45, frequency = 2 * Double.pi / 0.42
        let decay = damping * frequency, ringing = frequency * (1 - damping * damping).squareRoot()
        return 1 - exp(-decay * age) * (cos(ringing * age) + decay / ringing * sin(ringing * age))
    }
}

/// The name at the bottom of a story.
struct StoryBrand: View {
    static let frame = CGRect(
        x: 0, y: StoryFilm.size.height - StoryLayout.bottom - 64, width: StoryFilm.size.width, height: 64
    )

    /// 0…1: how far in it has come.
    let progress: Double

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 8) {
                Image(systemName: "globe.europe.africa.fill")
                    .foregroundStyle(Palette.accentLight)
                Text(verbatim: "Nomaded")
            }
            .font(.system(size: StoryLayout.wordmarkSize, weight: .heavy, design: .rounded))
            Text("Your travel passport")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .revealed(progress)
        .frame(width: Self.frame.width, height: Self.frame.height, alignment: .bottom)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }
}

private extension View {
    /// Comes in from a little below, out of a blur.
    func revealed(_ progress: Double) -> some View {
        opacity(progress)
            .offset(y: (1 - progress) * 14)
            .blur(radius: (1 - progress) * 6)
    }
}
