extension GlobeStyle {
    static let nomaded = GlobeStyle(
        ocean: Palette.components(Palette.RGB.ocean),
        unclaimedLand: Palette.components(Palette.RGB.landUnclaimed),
        idleLand: Palette.idleLandShades,
        visitedLand: Palette.RGB.candy.map(Palette.components)
    )
}
