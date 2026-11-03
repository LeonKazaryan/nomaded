import SwiftUI

/// A milestone's medal: a metal coin lit from the top left, with a turned rim and an inner
/// ring. Country counts carry the number, in bronze up to violet; a continent carries its
/// own silhouette, in a candy color. Unearned medals sit grey and faint.
struct MilestoneMedal: View {
    let milestone: Milestone
    /// The continent's outlines for its face; a globe stands in until they're built.
    var outlines: [ContinentMaps.Outline]?
    var size: CGFloat = 160
    var isEarned = true

    var body: some View {
        let metal = Self.metal(for: milestone)
        ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [metal.light, metal.base, metal.dark],
                    center: UnitPoint(x: 0.32, y: 0.28),
                    startRadius: 0,
                    endRadius: size * 0.75
                ))
            Circle()
                .strokeBorder(
                    AngularGradient(colors: [metal.light, metal.dark, metal.light, metal.dark, metal.light], center: .center),
                    lineWidth: size * 0.065
                )
            Circle()
                .strokeBorder(.white.opacity(0.4), lineWidth: max(1, size * 0.01))
                .padding(size * 0.12)
            face(metal)
        }
        .frame(width: size, height: size)
        .saturation(isEarned ? 1 : 0)
        .opacity(isEarned ? 1 : 0.32)
    }

    @ViewBuilder
    private func face(_ metal: Metal) -> some View {
        switch milestone {
        case .countries(let count):
            Text(count, format: .number)
                .font(.system(size: size * (count >= 100 ? 0.3 : 0.38), weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: metal.dark.opacity(0.7), radius: size * 0.015, y: size * 0.012)
        case .continent:
            if let outlines, !outlines.isEmpty {
                Canvas { context, canvas in
                    let scale = canvas.width * 0.3
                    let toFace = CGAffineTransform(translationX: canvas.width / 2, y: canvas.height / 2).scaledBy(x: scale, y: scale)
                    for outline in outlines where outline.isHome && !outline.isTiny {
                        context.fill(outline.path.applying(toFace), with: .color(.white), style: FillStyle(eoFill: true))
                    }
                }
                .padding(size * 0.14)
                .clipShape(Circle())
                .shadow(color: metal.dark.opacity(0.7), radius: size * 0.015, y: size * 0.012)
            } else {
                Image(systemName: "globe.europe.africa.fill")
                    .font(.system(size: size * 0.4, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
    }

    struct Metal {
        let light: Color
        let base: Color
        let dark: Color
    }

    /// Bronze, silver, gold, then violet and sky for the big counts; each continent has its
    /// candy color, Antarctica its ice.
    static func metal(for milestone: Milestone) -> Metal {
        let tones: (light: UInt32, dark: UInt32)
        switch milestone {
        case .countries(let count):
            switch count {
            case ..<25: tones = Palette.Medal.bronze
            case ..<50: tones = Palette.Medal.silver
            case ..<100: tones = Palette.Medal.gold
            case ..<150: tones = Palette.Medal.violet
            default: tones = Palette.Medal.sky
            }
        case .continent(let continent):
            guard continent != .antarctica else {
                tones = Palette.Medal.ice
                break
            }
            let candy = Palette.components(Palette.RGB.candy[Continent.allCases.firstIndex(of: continent)! % Palette.RGB.candy.count])
            let light = candy + (SIMD3(repeating: 1) - candy) * 0.5
            let dark = candy * 0.62
            return Metal(light: Color(components: light), base: Color(components: candy), dark: Color(components: dark))
        }
        let light = Palette.components(tones.light)
        let dark = Palette.components(tones.dark)
        return Metal(light: Color(rgb: tones.light), base: Color(components: (light + dark) / 2), dark: Color(rgb: tones.dark))
    }
}

#Preview {
    ScrollView(.horizontal) {
        HStack(spacing: 16) {
            ForEach(Milestone.all, id: \.id) { milestone in
                MilestoneMedal(milestone: milestone, size: 90)
            }
        }
        .padding()
    }
    .background(SpaceBackground())
}
