import CoreGraphics
import Testing
@testable import Dayrule

struct FoldLayoutTests {
    @Test("flat display uses the whole container")
    func noDivisionUsesContainer() {
        let slot = FoldLayout.contentSlot(
            in: CGSize(width: 466, height: 678),
            divisions: []
        )
        #expect(slot == CGRect(x: 0, y: 0, width: 466, height: 678))
    }

    @Test("equal book-fold panes prefer the leading side")
    func verticalFoldPrefersLeadingWhenTied() {
        let slot = FoldLayout.contentSlot(
            in: CGSize(width: 951, height: 669),
            divisions: [CGRect(x: 455.5, y: 0, width: 40, height: 669)]
        )
        #expect(slot.origin == .zero)
        #expect(slot.width == 455.5)
        #expect(slot.height == 669)
    }

    @Test("off-centre fold uses the larger pane")
    func verticalFoldUsesLargerSide() {
        let slot = FoldLayout.contentSlot(
            in: CGSize(width: 951, height: 669),
            divisions: [CGRect(x: 200, y: 0, width: 40, height: 669)]
        )
        #expect(slot.minX == 240)
        #expect(slot.width == 711)
    }

    @Test("horizontal fold prefers the top pane when tied")
    func horizontalFoldPrefersTopWhenTied() {
        let slot = FoldLayout.contentSlot(
            in: CGSize(width: 669, height: 951),
            divisions: [CGRect(x: 0, y: 455.5, width: 669, height: 40)]
        )
        #expect(slot.origin == .zero)
        #expect(slot.height == 455.5)
        #expect(slot.width == 669)
    }
}
