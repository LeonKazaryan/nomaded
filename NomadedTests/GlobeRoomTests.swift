import Foundation
import Testing
@testable import Nomaded

struct GlobeRoomTests {
    private let screen = CGSize(width: 402, height: 874)

    /// The globe on screen: the camera keeps its silhouette at this radius around this centre.
    private func circle(_ framing: (offset: Double, shift: Double, zoom: Double), in screen: CGSize? = nil) -> (center: CGPoint, radius: Double) {
        let screen = screen ?? self.screen
        return (
            CGPoint(x: screen.width / 2 + framing.shift, y: screen.height / 2 - framing.offset),
            GlobeTuning.baseDiameter(in: screen) / 2 * framing.zoom
        )
    }

    // Between a title and a panel, above the welcome's words, and the strip left while typing.
    @Test(arguments: [(197.0, 437.0), (70.0, 585.0), (70.0, 202.0)])
    func theGlobeSitsCentredInsideItsRoom(top: Double, bottom: Double) throws {
        let framing = try #require(GlobeRoom(top: top, bottom: bottom).framing(in: screen, defaultTop: 0))
        let globe = circle(framing)
        #expect(globe.center.y - globe.radius >= top)
        #expect(globe.center.y + globe.radius <= bottom)
        #expect(abs(globe.center.y - (top + bottom) / 2) < 1e-9)
        #expect(globe.center.x == screen.width / 2)
    }

    /// An iPad on its side: the step is a column on the left, the globe fills the rest.
    @Test func besideAColumnTheGlobeSitsCentredRightOfIt() throws {
        let iPad = CGSize(width: 1376, height: 1032)
        let room = GlobeRoom(top: 24, bottom: 1012, left: 500, right: 1376)
        let framing = try #require(room.framing(in: iPad, defaultTop: 0))
        let globe = circle(framing, in: iPad)
        #expect(abs(globe.center.x - 938) < 1e-9)
        #expect(abs(globe.center.y - 518) < 1e-9)
        #expect(globe.center.x - globe.radius >= 500)
        #expect(globe.center.y - globe.radius >= 24 && globe.center.y + globe.radius <= 1012)
    }

    /// Held sideways the globe takes most of the height, not the width: the whole planet fits.
    @Test func aWideScreenSizesTheGlobeByItsHeight() {
        #expect(GlobeTuning.baseDiameter(in: CGSize(width: 1376, height: 1032)) < 1032 * 0.8)
        #expect(GlobeTuning.baseDiameter(in: screen) == screen.width * GlobeTuning.baseDiameterRatio)
    }

    @Test func aTallRoomKeepsTheNormalSize() throws {
        let framing = try #require(GlobeRoom(top: 0, bottom: 874).framing(in: screen, defaultTop: 0))
        #expect(framing.zoom == 1)
        #expect(framing.offset == 0)
    }

    @Test func withoutATitleTheRoomStartsAtTheDefaultTop() throws {
        let framing = try #require(GlobeRoom(bottom: 400).framing(in: screen, defaultTop: 70))
        #expect(circle(framing).center.y == 235)
    }

    @Test func waitsUntilTheStepHasMeasuredItself() {
        #expect(GlobeRoom(top: 100).framing(in: screen, defaultTop: 0) == nil)
    }
}
