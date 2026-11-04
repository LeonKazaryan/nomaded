import simd

/// Colors the engine paints with, as sRGB components in 0…1. The app supplies them from
/// its palette, so GlobeEngine doesn't depend on the design system.
struct GlobeStyle: Sendable {
    var ocean: SIMD3<Float>
    /// Rivers. Lakes are the ocean showing through the land.
    var river: SIMD3<Float>
    var unclaimedLand: SIMD3<Float>
    /// Indexed by `CountryShape.colorSlot`, so neighbouring countries always differ.
    var idleLand: [SIMD3<Float>]
    var visitedLand: [SIMD3<Float>]

    func idleColor(slot: Int) -> SIMD3<Float> { idleLand[slot % idleLand.count] }
    func visitedColor(slot: Int) -> SIMD3<Float> { visitedLand[slot % visitedLand.count] }
}
