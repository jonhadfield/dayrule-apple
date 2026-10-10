import Foundation
import Testing
@testable import Dayrule

@Suite("generateRepeats")
@MainActor
struct GenerateRepeatsTests {
    @Test func createsTodayInstanceIdempotently() {
        let store = EntityStore(clock: StoreClock(
            now: { Date() },
            newId: { "ignored" },
            hlc: HLC(device: "dev1") { 1_700_000_000_000 }
        ))
        let today = "2026-10-04"
        let templateId = "tpl-daily"
        var e = Entities.empty()
        e.todos[templateId] = Todo(
            id: templateId,
            createdAt: "2026-10-04T09:00:00.000Z",
            updatedAt: "2026-10-04T09:00:00.000Z",
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
                every: 1,
                weekdays: nil,
                mode: .fixed,
                anchor: "2026-10-04",
                next: "2026-10-04",
                reminderTime: nil
            ),
            repeatTemplateId: nil
        )
        store.hydrate(e)
        store.generate { d, _ in
            let env = EntityStore.Env(now: Date(), today: today, newId: { "x" })
            return Repeats.generateRepeats(d, env)
        }
        store.generate { d, _ in
            let env = EntityStore.Env(now: Date(), today: today, newId: { "x" })
            return Repeats.generateRepeats(d, env)
        }
        let instanceId = Repeats.instanceId(templateId: templateId, date: today)
        #expect(store.entities.todos[instanceId]?.title == "Water plants")
        #expect(store.entities.todos[instanceId]?.startDate == today)
        #expect(store.entities.todos[instanceId]?.repeatTemplateId == templateId)
        #expect(store.entities.todos[templateId]?.repeat?.next == "2026-10-05")
        // Generated stamps beat nothing; fields use GENERATED.
        #expect(store.entities.todos[instanceId]?.clock?["title"] == generatedHlcStamp)

        let ctx = Lists.Context(today: today, keepVisible: nil)
        #expect(Lists.today(store.entities, ctx).map(\.title) == ["Water plants"])
        #expect(Lists.today(store.entities, ctx).map(\.id) == [instanceId])
    }

    @Test func afterTimeAwayCreatesOnlyLatestMissed() {
        let store = EntityStore(clock: StoreClock(
            now: { Date() },
            newId: { "ignored" },
            hlc: HLC(device: "dev1") { 1_700_000_000_000 }
        ))
        let templateId = "tpl-daily"
        var e = Entities.empty()
        e.todos[templateId] = Todo(
            id: templateId,
            createdAt: "2026-10-04T09:00:00.000Z",
            updatedAt: "2026-10-04T09:00:00.000Z",
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
                every: 1,
                weekdays: nil,
                mode: .fixed,
                anchor: "2026-10-04",
                next: "2026-10-04",
                reminderTime: nil
            ),
            repeatTemplateId: nil
        )
        store.hydrate(e)
        store.generate { d, _ in
            Repeats.generateRepeats(d, EntityStore.Env(now: Date(), today: "2026-10-04", newId: { "x" }))
        }
        store.generate { d, _ in
            Repeats.generateRepeats(d, EntityStore.Env(now: Date(), today: "2026-10-11", newId: { "x" }))
        }
        let dates = store.entities.todos.values
            .filter { $0.repeatTemplateId == templateId }
            .compactMap(\.startDate)
            .sorted()
        #expect(dates == ["2026-10-04", "2026-10-11"])
        #expect(store.entities.todos[templateId]?.repeat?.next == "2026-10-12")
    }
}
