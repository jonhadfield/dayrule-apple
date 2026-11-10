import Foundation
import Testing
@testable import Dayrule

@Suite("SidebarDrop")
struct SidebarDropTests {
    @Test("list rows map to move / when / complete / trash")
    func listActions() {
        let today = "2026-11-10"
        #expect(SidebarDrop.action(for: .inbox, today: today) == .move(.inbox))
        #expect(SidebarDrop.action(for: .today, today: today) == .when(.today))
        #expect(SidebarDrop.action(for: .scheduled, today: today) == .when(.date("2026-11-11")))
        #expect(SidebarDrop.action(for: .backlog, today: today) == .move(.none))
        #expect(SidebarDrop.action(for: .notNow, today: today) == .when(.later))
        #expect(SidebarDrop.action(for: .done, today: today) == .complete)
        #expect(SidebarDrop.action(for: .trash, today: today) == .trash)
    }

    @Test("project and area drops move into the container")
    func orgActions() {
        #expect(SidebarDrop.action(projectId: "p1") == .move(.project(projectId: "p1", headingId: nil)))
        #expect(SidebarDrop.action(areaId: "a1") == .move(.area(areaId: "a1")))
    }
}
