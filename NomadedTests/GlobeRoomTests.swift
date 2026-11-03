import Foundation
import Testing
@testable import Nomaded

struct GlobeRoomTests {
    private let screen = CGSize(width: 402, height: 874)

    /// The globe on screen: the camera keeps its silhouette at this radius around this centre.
    private func circle(_ framing: (offset: Double, zoom: Double)) -> (center: Double, radius: Double) {
        (screen.height / 2 - framing.offset, screen.width * GlobeTuning.baseDiameterRatio / 2 * framing.zoom)
    }

    // Between a title and a panel, above the welcome's words, and the strip left while typing.
    @Test(arguments: [(197.0, 437.0), (70.0, 585.0), (70.0, 202.0)])
    func theGlobeSitsCentredInsideItsRoom(top: Double, bottom: Double) throws {
        let framing = try #require(GlobeRoom(top: top, bottom: bottom).framing(in: screen, defaultTop: 0))
        let globe = circle(framing)
        #expect(globe.center - globe.radius >= top)
        #expect(globe.center + globe.radius <= bottom)
        #expect(abs(globe.center - (top + bottom) / 2) < 1e-9)
    }

    @Test func aTallRoomKeepsTheNormalSize() throws {
        let framing = try #require(GlobeRoom(top: 0, bottom: 874).framing(in: screen, defaultTop: 0))
        #expect(framing.zoom == 1)
        #expect(framing.offset == 0)
    }

    @Test func withoutATitleTheRoomStartsAtTheDefaultTop() throws {
        let framing = try #require(GlobeRoom(bottom: 400).framing(in: screen, defaultTop: 70))
        #expect(circle(framing).center == 235)
    }

    @Test func waitsUntilTheStepHasMeasuredItself() {
        #expect(GlobeRoom(top: 100).framing(in: screen, defaultTop: 0) == nil)
    }
}
