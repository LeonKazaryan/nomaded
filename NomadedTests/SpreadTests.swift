import SwiftUI
import Testing
@testable import Nomaded

struct SpreadTests {
    /// iPhone Duo's inner screen held like a book: 951 × 669 points, the fold down the middle.
    private func book(fold: CGRect = CGRect(x: 475, y: 0, width: 0, height: 669), safeArea: EdgeInsets = EdgeInsets(top: 24, leading: 0, bottom: 20, trailing: 0)) -> Spread {
        Spread(
            window: CGSize(width: 951, height: 669),
            fold: fold,
            margins: EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12),
            safeArea: safeArea,
            isBent: false
        )
    }

    @Test func aFoldDownTheMiddleMakesPagesSideBySide() {
        let spread = book()
        #expect(spread.layout == .sideBySide)
        #expect(spread.firstPage == CGRect(x: 0, y: 0, width: 463, height: 669))
        #expect(spread.secondPage == CGRect(x: 487, y: 0, width: 464, height: 669))
    }

    @Test func aBentFoldKeepsItsWidthOutOfBothPages() {
        let spread = book(fold: CGRect(x: 465, y: 0, width: 20, height: 669))
        #expect(spread.firstPage.maxX == 453)
        #expect(spread.secondPage.minX == 497)
    }

    @Test func aFoldAcrossStacksThePages() {
        let spread = Spread(
            window: CGSize(width: 669, height: 951),
            fold: CGRect(x: 0, y: 475, width: 669, height: 0),
            margins: EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0),
            safeArea: EdgeInsets(),
            isBent: true
        )
        #expect(spread.layout == .stacked)
        #expect(spread.firstPage == CGRect(x: 0, y: 0, width: 669, height: 463))
        #expect(spread.secondPage == CGRect(x: 0, y: 487, width: 669, height: 464))
    }

    @Test func paddingConfinesASafeAreaViewToAPage() {
        let spread = book(safeArea: EdgeInsets(top: 24, leading: 10, bottom: 20, trailing: 30))
        let left = spread.insets(confiningTo: spread.firstPage)
        // The view spans 10…921: it keeps clear of everything from the left page's edge on.
        #expect(left.leading == 0)
        #expect(left.trailing == CGFloat(951 - 30 - 463))
        #expect(left.top == 0 && left.bottom == 0)
        let right = spread.insets(confiningTo: spread.secondPage)
        #expect(right.leading == CGFloat(487 - 10))
        #expect(right.trailing == 0)
    }

    @Test func columnsMeetOverTheFold() {
        let spread = book(safeArea: EdgeInsets(top: 24, leading: 10, bottom: 20, trailing: 30))
        let columns = spread.columns(padding: 16)
        #expect(columns.first == CGFloat(463 - 26))
        #expect(columns.gap == 24)
        #expect(columns.second == CGFloat(951 - 30 - 16 - 487))
        // Together they fill the padded safe area exactly.
        #expect(columns.first + columns.gap + columns.second == CGFloat(951 - 10 - 30 - 32))
    }
}
