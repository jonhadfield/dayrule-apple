import Foundation
import Testing
@testable import Dayrule

@Suite("Repeats.onInstanceDone")
@MainActor
struct RepeatsStoreTests {
    @Test func schedulesNextAfterCompletionInstance() {
        var e = Entities.empty()
        let template = Todo(
            id: "tpl",
            createdAt: "2026-10-01T09:00:00.000Z",
            updatedAt: "2026-10-01T09:00:00.000Z",
            clock: nil,
            title: "Water plants",
            notes: "",
            projectId: nil,
            headingId: nil,
            areaId: nil,
            status: .open,
            start: .ready,
            startDate: nil,
            tonight: false,
            deadline: nil,
            tagIds: [],
            order: "a0",
            todayOrder: nil,
            completedAt: nil,
            trashedAt: nil,
            reminderAt: nil,
            repeat: RepeatRule(
                freq: .day,
                every: 3,
                weekdays: nil,
                mode: .afterCompletion,
                anchor: "2026-10-01",
                next: nil,
                reminderTime: nil
            ),
            repeatTemplateId: nil
        )
        var instance = template
        instance.id = "inst"
        instance.repeat = nil
        instance.repeatTemplateId = "tpl"
        instance.startDate = "2026-10-04"
        e.todos["tpl"] = template
        e.todos["inst"] = instance

        let store = EntityStore(
            entities: e,
            clock: StoreClock(
                now: { Date(timeIntervalSince1970: 1_700_000_000) },
                newId: { "x" },
                hlc: HLC(device: "dev1") { 1_700_000_000_000 }
            )
        )
        // Force env.today via completing on a known local day — use setStatus path.
        // StoreClock.now drives When.toLocalDate; pin to 2026-10-04 local by using noon UTC
        // may vary by TZ. Instead call Repeats directly with a fixed Env.
        let draft = Draft(base: store.entities)
        let env = EntityStore.Env(
            now: Date(timeIntervalSince1970: 1_728_000_000),
            today: "2026-10-04",
            newId: { "x" }
        )
        Commands.setStatus(draft, env, ids: ["inst"], status: .completed)
        let changes = draft.changes()
        #expect(!changes.isEmpty)
        let next = ApplyChanges.apply(store.entities, changes, direction: .forward)
        #expect(next.todos["inst"]?.status == .completed)
        #expect(next.todos["tpl"]?.repeat?.next == "2026-10-07")
    }
}
