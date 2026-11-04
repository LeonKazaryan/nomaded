extension GlobeStyle {
    static let nomaded = GlobeStyle(
        ocean: Palette.components(Palette.RGB.ocean),
        river: Palette.components(Palette.RGB.river),
        unclaimedLand: Palette.components(Palette.RGB.landUnclaimed),
        idleLand: Palette.idleLandShades,
        visitedLand: Palette.RGB.candy.map(Palette.components)
    )
}
