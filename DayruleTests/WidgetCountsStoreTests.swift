import Foundation
import Testing
@testable import Dayrule

@Suite("Widget counts store")
struct WidgetCountsStoreTests {
    @Test("publish then read round-trips open counts")
    func publishRoundTrip() {
        WidgetCountsStore.clear()
        WidgetCountsStore.publish(inboxOpen: 4, todayOpen: 2)
        let snap = WidgetCountsStore.read()
        #expect(snap.inboxOpen == 4)
        #expect(snap.todayOpen == 2)
        #expect(snap.stampedAt != nil)
        WidgetCountsStore.clear()
        let cleared = WidgetCountsStore.read()
        #expect(cleared.stampedAt == nil)
        #expect(cleared.inboxOpen == 0)
        #expect(cleared.todayOpen == 0)
    }

    @Test("clear drops membership so a locked device shows empty counts")
    func clearDropsMembership() {
        WidgetCountsStore.publish(inboxOpen: 9, todayOpen: 3)
        #expect(WidgetCountsStore.read().inboxOpen == 9)
        WidgetCountsStore.clear()
        let snap = WidgetCountsStore.read()
        #expect(snap.inboxOpen == 0)
        #expect(snap.todayOpen == 0)
        #expect(snap.stampedAt == nil)
    }

    @Test("negative inputs clamp to zero on publish")
    func publishClampsNegatives() {
        WidgetCountsStore.clear()
        WidgetCountsStore.publish(inboxOpen: -1, todayOpen: -4)
        let snap = WidgetCountsStore.read()
        #expect(snap.inboxOpen == 0)
        #expect(snap.todayOpen == 0)
        WidgetCountsStore.clear()
    }
}
