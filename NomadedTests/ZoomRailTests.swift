import Foundation
import Testing
@testable import Nomaded

struct ZoomRailTests {
    @Test func theRailSpansTheWholeZoomRange() {
        let range = GlobeTuning.zoomRange
        #expect(abs(ZoomRailScale.level(ofZoom: range.lowerBound)) < 1e-9)
        #expect(abs(ZoomRailScale.level(ofZoom: range.upperBound) - 1) < 1e-9)
    }

    /// The fill keeps pace with the finger: sliding the rail's own length crosses the range.
    @Test func slidingTheRailsLengthCrossesTheWholeRange() {
        let range = GlobeTuning.zoomRange
        let zoom = range.lowerBound * ZoomRailScale.magnification(travel: ZoomRailScale.length)
        #expect(abs(zoom - range.upperBound) < 1e-9)
    }

    @Test func upZoomsInAndDownZoomsOut() {
        let doubling = GlobeTuning.zoomRailPointsPerDoubling
        #expect(abs(ZoomRailScale.magnification(travel: doubling) - 2) < 1e-9)
        #expect(abs(ZoomRailScale.magnification(travel: -doubling) - 0.5) < 1e-9)
        #expect(ZoomRailScale.magnification(travel: 0) == 1)
    }

    /// Fits the edge of an iPhone between the bar and the home indicator.
    @Test func theRailFitsAnIPhonesEdge() {
        #expect(ZoomRailScale.length > 300 && ZoomRailScale.length < 600)
    }

    @Test func aTouchIsATapUntilItMovesThenItsDirectionDecides() {
        #expect(ZoomRailScale.intent(of: CGSize(width: 3, height: 4)) == nil)
        #expect(ZoomRailScale.intent(of: CGSize(width: 2, height: -20)) == .zoom)
        #expect(ZoomRailScale.intent(of: CGSize(width: 4, height: 20)) == .zoom)
        #expect(ZoomRailScale.intent(of: CGSize(width: -20, height: 6)) == .spin)
    }
}
