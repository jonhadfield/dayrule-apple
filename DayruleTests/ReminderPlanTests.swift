import Foundation
import Testing
@testable import Dayrule

@Suite("ReminderPlan")
struct ReminderPlanTests {
    @Test("upcoming sorts and caps at 64")
    func upcomingCap() {
        var e = Entities.empty()
        for i in 0..<70 {
            let id = String(format: "t-%02d", i)
            var t = Todo(
                id: id,
                createdAt: "2026-10-01T00:00:00.000Z",
                updatedAt: "2026-10-01T00:00:00.000Z",
                clock: nil,
                title: "T\(i)",
                notes: "",
                projectId: nil,
                headingId: nil,
                areaId: nil,
                status: .open,
                start: .inbox,
                startDate: nil,
                tonight: false,
                deadline: nil,
                tagIds: [],
                order: String(format: "a%02d", i),
                todayOrder: nil,
                completedAt: nil,
                trashedAt: nil,
                reminderAt: String(format: "2026-12-%02dT09:00", (i % 28) + 1),
                repeat: nil,
                repeatTemplateId: nil
            )
            // Spread across days then hours via id order tie-break
            t.reminderAt = String(format: "2027-01-01T%02d:%02d", i / 60, i % 60)
            e.todos[id] = t
        }
        let now = When.fromLocalDate("2026-10-10")!
        let got = ReminderPlan.upcoming(e, now: now)
        #expect(got.count == 64)
        #expect(got.first?.fireAt == "2027-01-01T00:00")
        #expect(got.last?.fireAt == "2027-01-01T01:03")
    }

    @Test("skips trashed and past reminders")
    func skips() {
        var e = Entities.empty()
        e.todos["past"] = makeTodo(id: "past", at: "2020-01-01T09:00")
        e.todos["trash"] = makeTodo(id: "trash", at: "2030-01-01T09:00", trashed: true)
        e.todos["ok"] = makeTodo(id: "ok", at: "2030-01-01T10:00")
        let now = When.fromLocalDate("2026-10-10")!
        let got = ReminderPlan.upcoming(e, now: now)
        #expect(got.map(\.todoId) == ["ok"])
    }

    @Test("request body hides title unless opted in")
    func bodies() {
        let entries = [
            ReminderPlan.Entry(todoId: "a", fireAt: "2026-10-11T14:00", title: "Secret"),
        ]
        let generic = ReminderPlan.requests(from: entries, showTitles: false)
        #expect(generic[0].body == "Reminder at 14:00")
        let titled = ReminderPlan.requests(from: entries, showTitles: true)
        #expect(titled[0].body == "Secret")
        #expect(titled[0].identifier.hasPrefix(ReminderPlan.idPrefix))
    }

    private func makeTodo(id: ID, at: String, trashed: Bool = false) -> Todo {
        Todo(
            id: id,
            createdAt: "2026-10-01T00:00:00.000Z",
            updatedAt: "2026-10-01T00:00:00.000Z",
            clock: nil,
            title: id,
            notes: "",
            projectId: nil,
            headingId: nil,
            areaId: nil,
            status: .open,
            start: .inbox,
            startDate: nil,
            tonight: false,
            deadline: nil,
            tagIds: [],
            order: "a0",
            todayOrder: nil,
            completedAt: nil,
            trashedAt: trashed ? "2026-10-02T00:00:00.000Z" : nil,
            reminderAt: at,
            repeat: nil,
            repeatTemplateId: nil
        )
    }
}
