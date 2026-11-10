import Foundation
import Testing
@testable import Nomaded

/// The display's clock steps back a frame when the screen changes its refresh rate (typing on
/// the keyboard does it on a ProMotion iPhone). In 1.0 that negative step went into the turn's
/// speed limit as 0 / 0, the rotation became NaN, and the globe vanished until a relaunch.
struct GlobeTimeStepTests {
    @Test(arguments: [-0.00833, -1.0, 0.0, .nan, .infinity, -.infinity])
    func timeNeverRunsBackwards(_ deltaTime: Double) {
        let step = GlobeController.physicsStep(deltaTime)
        #expect(step.isFinite)
        #expect(step >= 0)
    }

    @Test func aHitchIsClamped() {
        #expect(GlobeController.physicsStep(1.0 / 120) == 1.0 / 120)
        #expect(GlobeController.physicsStep(0.5) == 1.0 / 15)
    }

    /// A turn that hasn't moved this frame, in a frame of no (or negative) time.
    @Test(arguments: [0.0, -0.00833])
    func aStillTurnInNoTimeStaysFinite(_ dt: Double) {
        #expect(GlobeController.focusStepScale(moved: 0, dt: dt) == 1)
        let scale = GlobeController.focusStepScale(moved: 120, dt: dt)
        #expect(scale.isFinite)
        #expect((0...1).contains(scale))
    }

    @Test func aFastTurnIsSlowedToTheLimit() {
        let dt = 1.0 / 120
        let allowed = GlobeTuning.maxFocusScreenSpeed * dt
        #expect(GlobeController.focusStepScale(moved: allowed / 2, dt: dt) == 1)
        #expect(abs(GlobeController.focusStepScale(moved: allowed * 4, dt: dt) - 0.25) < 1e-12)
    }
}
