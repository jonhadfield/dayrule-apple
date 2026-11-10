import Foundation
import Testing
@testable import Dayrule

@Suite("ListReorder")
struct ListReorderTests {
    @Test("arrayMove matches dnd-kit (swap with next)")
    func arrayMoveSwapNext() {
        #expect(ListReorder.arrayMove(["a", "b", "c"], from: 0, to: 1) == ["b", "a", "c"])
        #expect(ListReorder.arrayMove(["a", "b", "c"], from: 2, to: 0) == ["c", "a", "b"])
    }

    @Test("drop onto neighbour yields before/after for Commands.reorder")
    func dropNeighbours() {
        let peers = ["a", "b", "c"]
        let down = ListReorder.neighbours(peers: peers, dragging: "a", onto: "b")
        #expect(down?.before == "b")
        #expect(down?.after == "c")
        let up = ListReorder.neighbours(peers: peers, dragging: "c", onto: "a")
        #expect(up?.before == nil)
        #expect(up?.after == "a")
    }

    @Test("onMove destination maps like SwiftUI List")
    func onMoveNeighbours() {
        let peers = ["a", "b", "c"]
        // Move a down one step: SwiftUI destination = 2
        let moved = ListReorder.neighbours(
            peers: peers,
            source: IndexSet(integer: 0),
            destination: 2
        )
        #expect(moved?.id == "a")
        #expect(moved?.before == "b")
        #expect(moved?.after == "c")
    }

    @Test("allowsDrag excludes Done Trash Scheduled")
    func allowsDrag() {
        #expect(ListReorder.allowsDrag(in: .inbox))
        #expect(ListReorder.allowsDrag(in: .today))
        #expect(!ListReorder.allowsDrag(in: .done))
        #expect(!ListReorder.allowsDrag(in: .trash))
        #expect(!ListReorder.allowsDrag(in: .scheduled))
        #expect(ListReorder.orderField(for: .today) == .todayOrder)
        #expect(ListReorder.orderField(for: .inbox) == .order)
    }
}
