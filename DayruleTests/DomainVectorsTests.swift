import Foundation
import Testing
@testable import Dayrule

/// Known-answer domain vectors (PLAN §16 / M3).
@Suite("Domain vectors")
struct DomainVectorsTests {
    private struct File: Decodable {
        var version: Int
        var parseWhen: [WhenCase]
        var order: OrderSection
        var hlc: HlcSection
        var merge: MergeSection?
        var lists: ListsSection?
        var repeats: RepeatsSection?
        var find: FindSection?
        var generatedInstances: GeneratedInstancesSection?
    }

    private struct GeneratedInstancesSection: Decodable {
        var template: GeneratedTemplate
        var cases: [GeneratedCase]
    }

    private struct GeneratedTemplate: Decodable {
        var id: String
        var title: String
        var notes: String
        var order: String
        var `repeat`: GeneratedRepeat
    }

    private struct GeneratedRepeat: Decodable {
        var freq: String
        var every: Int
        var mode: String
        var anchor: String
        var next: String
    }

    private struct GeneratedCase: Decodable {
        var name: String
        var today: String
        var expect: GeneratedExpect
    }

    private struct GeneratedExpect: Decodable {
        var instance: GeneratedTodoSnap?
        var latestInstance: GeneratedTodoSnap?
        var templateNext: String
        var instanceDates: [String]
    }

    private struct GeneratedTodoSnap: Decodable, Equatable {
        var id: String
        var title: String
        var notes: String
        var status: String
        var start: String
        var startDate: String?
        var tonight: Bool
        var order: String
        var repeatTemplateId: String?
        var reminderAt: String?
        var createdAt: String
        var updatedAt: String
    }

    private struct FindSection: Decodable {
        var today: String
        var seed: FindSeed
        var search: [FindSearchCase]
        var homeOf: [FindHomeCase]
    }

    private struct FindSeed: Decodable {
        var tags: [TagSeed]
        var areas: [FindAreaSeed]
        var projects: [FindProjectSeed]
        var todos: [FindTodoSeed]
    }

    private struct TagSeed: Decodable {
        var id: String
        var title: String
    }

    private struct FindAreaSeed: Decodable {
        var id: String
        var title: String
        var order: String
        var trashedAt: String?
    }

    private struct FindProjectSeed: Decodable {
        var id: String
        var title: String
        var areaId: String?
        var start: String
        var startDate: String?
        var order: String
        var trashedAt: String?
    }

    private struct FindTodoSeed: Decodable {
        var id: String
        var title: String
        var notes: String
        var start: String
        var startDate: String?
        var deadline: String?
        var tonight: Bool
        var status: String
        var projectId: String?
        var areaId: String?
        var tagIds: [String]
        var order: String
        var todayOrder: String?
        var trashedAt: String?
        var completedAt: String?
    }

    private struct FindSearchCase: Decodable {
        var query: String
        var top: FindHit?
    }

    private struct FindHit: Decodable, Equatable {
        var kind: String
        var path: String
        var todoId: String?
        var detail: String
    }

    private struct FindHomeCase: Decodable {
        var todoId: String
        var path: String
    }

    private struct ListsSection: Decodable {
        var today: String
        var seed: ListsSeed
        var expect: ListsExpect
    }

    private struct ListsSeed: Decodable {
        var areas: [AreaSeed]
        var projects: [ProjectSeed]
        var todos: [TodoSeed]
    }

    private struct AreaSeed: Decodable {
        var id: String
        var title: String
        var order: String
    }

    private struct ProjectSeed: Decodable {
        var id: String
        var title: String
        var areaId: String?
        var start: String
        var startDate: String?
        var order: String
    }

    private struct TodoSeed: Decodable {
        var id: String
        var title: String
        var start: String
        var startDate: String?
        var deadline: String?
        var tonight: Bool
        var status: String
        var projectId: String?
        var areaId: String?
        var order: String
        var todayOrder: String?
        var trashedAt: String?
    }

    private struct ListsExpect: Decodable {
        var inbox: [String]
        var today: [String]
        var scheduled: ScheduledExpect
        var notNow: NotNowExpect
        var sidebarCounts: SidebarCountsExpect
    }

    private struct ScheduledExpect: Decodable {
        var days: [DayExpect]
        var months: [MonthExpect]
        var waiting: [String]
    }

    private struct DayExpect: Decodable {
        var date: String
        var ids: [String]
    }

    private struct MonthExpect: Decodable {
        var month: String
        var ids: [String]
    }

    private struct NotNowExpect: Decodable {
        var projects: [String]
        var todos: [String]
    }

    private struct SidebarCountsExpect: Decodable {
        var inbox: Int
        var today: Int
        var overdue: Int
    }

    private struct RepeatsSection: Decodable {
        var instanceId: [InstanceIdCase]
        var sequences: [SequenceCase]
        var onOrAfter: [OnOrAfterCase]
        var dueAfterCompletion: [DueAfterCase]
    }

    private struct InstanceIdCase: Decodable {
        var templateId: String
        var date: String
        var result: String
    }

    private struct SequenceCase: Decodable {
        var name: String
        var rule: RepeatRuleDTO
        var count: Int
        var result: [String]
    }

    private struct OnOrAfterCase: Decodable {
        var rule: RepeatRuleDTO
        var from: String
        var result: String
    }

    private struct DueAfterCase: Decodable {
        var rule: RepeatRuleDTO
        var done: String
        var result: String
    }

    /// Shared-vector shape of a Repeat rule (no `next` / reminderTime required).
    private struct RepeatRuleDTO: Decodable {
        var freq: String
        var every: Int
        var weekdays: [Int]?
        var mode: String
        var anchor: String

        func asRule() throws -> RepeatRule {
            guard let freq = RepeatRule.Freq(rawValue: freq) else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: [], debugDescription: "bad freq \(freq)")
                )
            }
            guard let mode = RepeatRule.Mode(rawValue: mode) else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: [], debugDescription: "bad mode \(mode)")
                )
            }
            return RepeatRule(
                freq: freq,
                every: every,
                weekdays: weekdays,
                mode: mode,
                anchor: anchor,
                next: nil,
                reminderTime: nil
            )
        }
    }

    private struct MergeSection: Decodable {
        var triples: [MergeTriple]
        var tombstones: [TombstoneCase]
        var latestStamp: [LatestStampCase]
    }

    private struct MergeTriple: Decodable {
        var local: AnyJSON?
        var remote: AnyJSON
        var result: AnyJSON
    }

    private struct TombstoneCase: Decodable {
        var entity: AnyJSON?
        var tombstone: String
        var result: TombstoneResultDTO
    }

    private struct TombstoneResultDTO: Decodable {
        var kind: String
        var value: AnyJSON?
    }

    private struct LatestStampCase: Decodable {
        var entity: AnyJSON
        var result: String
    }

    /// Opaque JSON object for merge fixtures.
    private struct AnyJSON: Decodable, Equatable {
        var value: Any

        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let obj = try? c.decode([String: AnyJSON].self) {
                value = obj.mapValues(\.value)
            } else if let arr = try? c.decode([AnyJSON].self) {
                value = arr.map(\.value)
            } else if let s = try? c.decode(String.self) {
                value = s
            } else if let b = try? c.decode(Bool.self) {
                value = b
            } else if let i = try? c.decode(Int.self) {
                value = i
            } else if let d = try? c.decode(Double.self) {
                value = d
            } else if c.decodeNil() {
                value = NSNull()
            } else {
                throw DecodingError.dataCorruptedError(in: c, debugDescription: "unsupported JSON")
            }
        }

        static func == (lhs: AnyJSON, rhs: AnyJSON) -> Bool {
            jsonEquals(lhs.value, rhs.value)
        }

        var dictionary: [String: Any]? { value as? [String: Any] }
    }

    private static func jsonEquals(_ a: Any, _ b: Any) -> Bool {
        switch (a, b) {
        case let (x as String, y as String): x == y
        case let (x as Bool, y as Bool): x == y
        case let (x as Int, y as Int): x == y
        case let (x as Double, y as Double): x == y
        case (is NSNull, is NSNull): true
        case let (x as [String: Any], y as [String: Any]):
            x.keys == y.keys && x.keys.allSatisfy { jsonEquals(x[$0] as Any, y[$0] as Any) }
        case let (x as [Any], y as [Any]):
            x.count == y.count && zip(x, y).allSatisfy { jsonEquals($0, $1) }
        default:
            false
        }
    }

    private struct WhenCase: Decodable {
        var input: String
        var today: String
        var result: WhenDTO?
    }

    private struct WhenDTO: Decodable, Equatable {
        var kind: String
        var date: String?
    }

    private struct OrderSection: Decodable {
        var keyBetween: [KeyBetweenCase]
        var keysBetween: [KeysBetweenCase]
        var compare: [CompareCase]
    }

    private struct KeyBetweenCase: Decodable {
        var before: String?
        var after: String?
        var result: String
    }

    private struct KeysBetweenCase: Decodable {
        var before: String?
        var after: String?
        var n: Int
        var result: [String]
    }

    private struct CompareCase: Decodable {
        var a: String
        var b: String
        var result: Int
    }

    private struct HlcSection: Decodable {
        var device: String
        var steps: [HlcStep]
    }

    private struct HlcStep: Decodable {
        var op: String
        var now: Int?
        var stamp: String?
        var result: String?
    }

    private func load() throws -> File {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root.appendingPathComponent("docs/shared/domain-vectors.json")
        return try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
    }

    private func localDay(_ iso: String) -> Date {
        When.fromLocalDate(iso)!
    }

    @Test("parseWhen matches shared vectors")
    func parseWhenVectors() throws {
        let file = try load()
        for c in file.parseWhen {
            let got = When.parseWhen(c.input, today: localDay(c.today))
            let dto: WhenDTO? = {
                guard let got else { return nil }
                switch got {
                case .today: return WhenDTO(kind: "today", date: nil)
                case .later: return WhenDTO(kind: "later", date: nil)
                case .date(let d): return WhenDTO(kind: "date", date: d)
                }
            }()
            #expect(dto == c.result, "parseWhen(\(c.input), \(c.today))")
        }
    }

    @Test("order keys match shared vectors")
    func orderVectors() throws {
        let file = try load()
        for c in file.order.keyBetween {
            let got = try Order.keyBetween(c.before, c.after)
            #expect(got == c.result)
        }
        for c in file.order.keysBetween {
            let got = try Order.keysBetween(c.before, c.after, c.n)
            #expect(got == c.result)
        }
        for c in file.order.compare {
            #expect(Order.compareKeys(c.a, c.b) == c.result)
        }
    }

    @Test("HLC tick/observe matches shared vectors")
    func hlcVectors() throws {
        final class NowBox: @unchecked Sendable { var value = 0 }
        let file = try load()
        let box = NowBox()
        var clock = HLC(device: file.hlc.device, now: { box.value })
        for step in file.hlc.steps {
            switch step.op {
            case "tick":
                box.value = step.now!
                let stamp = clock.tick()
                #expect(stamp == step.result)
            case "observe":
                clock.observe(step.stamp!)
            default:
                Issue.record("unknown HLC op \(step.op)")
            }
        }
    }

    @Test("mergeEntity and tombstones match shared vectors")
    func mergeVectors() throws {
        let file = try load()
        #expect(file.version == 2)
        let merge = try #require(file.merge)
        for t in merge.triples {
            let got = Merge.mergeEntity(local: t.local?.dictionary, remote: t.remote.dictionary!)
            #expect(Self.jsonEquals(got, t.result.value))
        }
        for t in merge.tombstones {
            let got = Merge.resolveTombstone(entity: t.entity?.dictionary, tombstone: t.tombstone)
            switch (got, t.result.kind) {
            case (.delete, "delete"):
                break
            case (.keep(let v), "keep"):
                #expect(Self.jsonEquals(v, t.result.value!.value))
            default:
                Issue.record("tombstone mismatch \(t.tombstone)")
            }
        }
        for t in merge.latestStamp {
            let clock = t.entity.dictionary?["clock"] as? FieldClock
            #expect(Merge.latestStamp(clock) == t.result)
        }
    }

    private func entities(from seed: ListsSeed) throws -> Entities {
        let ts = "2026-10-01T09:00:00.000Z"
        var e = Entities.empty()
        for a in seed.areas {
            e.areas[a.id] = Area(
                id: a.id,
                createdAt: ts,
                updatedAt: ts,
                clock: nil,
                title: a.title,
                order: a.order,
                tagIds: [],
                trashedAt: nil
            )
        }
        for p in seed.projects {
            guard let start = StartBucket(rawValue: p.start) else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: [], debugDescription: "bad project start \(p.start)")
                )
            }
            e.projects[p.id] = Project(
                id: p.id,
                createdAt: ts,
                updatedAt: ts,
                clock: nil,
                title: p.title,
                notes: "",
                areaId: p.areaId,
                status: .open,
                start: start,
                startDate: p.startDate,
                tonight: false,
                deadline: nil,
                tagIds: [],
                order: p.order,
                todayOrder: nil,
                completedAt: nil,
                trashedAt: nil
            )
        }
        for t in seed.todos {
            guard let start = StartBucket(rawValue: t.start) else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: [], debugDescription: "bad todo start \(t.start)")
                )
            }
            guard let status = Status(rawValue: t.status) else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: [], debugDescription: "bad todo status \(t.status)")
                )
            }
            e.todos[t.id] = Todo(
                id: t.id,
                createdAt: ts,
                updatedAt: ts,
                clock: nil,
                title: t.title,
                notes: "",
                projectId: t.projectId,
                headingId: nil,
                areaId: t.areaId,
                status: status,
                start: start,
                startDate: t.startDate,
                tonight: t.tonight,
                deadline: t.deadline,
                tagIds: [],
                order: t.order,
                todayOrder: t.todayOrder,
                completedAt: nil,
                trashedAt: t.trashedAt,
                reminderAt: nil,
                repeat: nil,
                repeatTemplateId: nil
            )
        }
        return e
    }

    @Test("list selectors match shared vectors")
    func listSelectorVectors() throws {
        let file = try load()
        let lists = try #require(file.lists)
        let e = try entities(from: lists.seed)
        let ctx = Lists.Context(today: lists.today, keepVisible: nil)
        #expect(Lists.inbox(e, ctx).map(\.id) == lists.expect.inbox)
        #expect(Lists.today(e, ctx).map(\.id) == lists.expect.today)
        let sched = Lists.scheduled(e, ctx)
        #expect(sched.days.map(\.date) == lists.expect.scheduled.days.map(\.date))
        for (got, want) in zip(sched.days, lists.expect.scheduled.days) {
            #expect(got.items.map(\.id) == want.ids, "scheduled day \(want.date)")
        }
        #expect(sched.months.map(\.month) == lists.expect.scheduled.months.map(\.month))
        for (got, want) in zip(sched.months, lists.expect.scheduled.months) {
            #expect(got.items.map(\.id) == want.ids, "scheduled month \(want.month)")
        }
        #expect(sched.waiting.map(\.id) == lists.expect.scheduled.waiting)
        let later = Lists.notNow(e, ctx)
        #expect(later.projects.map(\.id) == lists.expect.notNow.projects)
        #expect(later.todos.map(\.id) == lists.expect.notNow.todos)
        let counts = Lists.sidebarCounts(e, ctx)
        #expect(counts.inbox == lists.expect.sidebarCounts.inbox)
        #expect(counts.today == lists.expect.sidebarCounts.today)
        #expect(counts.overdue == lists.expect.sidebarCounts.overdue)
    }

    @Test("repeat sequences and instanceId match shared vectors")
    func repeatVectors() throws {
        let file = try load()
        let repeats = try #require(file.repeats)
        for c in repeats.instanceId {
            #expect(Repeats.instanceId(templateId: c.templateId, date: c.date) == c.result)
        }
        for c in repeats.sequences {
            let rule = try c.rule.asRule()
            var got: [LocalDate] = [RepeatMath.occurrenceOnOrAfter(rule, rule.anchor)]
            while got.count < c.count {
                got.append(RepeatMath.occurrenceAfter(rule, got[got.count - 1]))
            }
            #expect(got == c.result, "sequence \(c.name)")
        }
        for c in repeats.onOrAfter {
            let rule = try c.rule.asRule()
            #expect(RepeatMath.occurrenceOnOrAfter(rule, c.from) == c.result)
        }
        for c in repeats.dueAfterCompletion {
            let rule = try c.rule.asRule()
            #expect(RepeatMath.dueAfterCompletion(rule, c.done) == c.result)
        }
    }

    @Test("generateRepeats instances match shared vectors")
    @MainActor
    func generatedInstanceVectors() throws {
        let file = try load()
        let section = try #require(file.generatedInstances)
        for c in section.cases {
            let store = try makeGeneratedStore(template: section.template, today: c.today)
            store.generate { d, env in Repeats.generateRepeats(d, env) }
            // Idempotent on the same day.
            store.generate { d, env in Repeats.generateRepeats(d, env) }
            let dates = store.entities.todos.values
                .filter { $0.repeatTemplateId == section.template.id }
                .compactMap(\.startDate)
                .sorted()
            #expect(dates == c.expect.instanceDates, "\(c.name) dates")
            #expect(
                store.entities.todos[section.template.id]?.repeat?.next == c.expect.templateNext,
                "\(c.name) template next"
            )
            if let want = c.expect.instance {
                let got = try #require(store.entities.todos[want.id])
                #expect(Self.snap(got) == want, "\(c.name) instance")
            }
            if let want = c.expect.latestInstance {
                let got = try #require(store.entities.todos[want.id])
                #expect(Self.snap(got) == want, "\(c.name) latest instance")
            }
        }
    }

    @MainActor
    private func makeGeneratedStore(template: GeneratedTemplate, today: String) throws -> EntityStore {
        guard let freq = RepeatRule.Freq(rawValue: template.repeat.freq),
              let mode = RepeatRule.Mode(rawValue: template.repeat.mode)
        else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "bad generated template repeat")
            )
        }
        final class MsBox: @unchecked Sendable {
            var value: Double
            init(_ value: Double) { self.value = value }
        }
        let box = MsBox(
            ISO8601DateFormatter().date(from: "\(today)T09:00:00Z")!.timeIntervalSince1970 * 1000
        )
        let store = EntityStore(clock: StoreClock(
            now: {
                box.value += 1000
                return Date(timeIntervalSince1970: box.value / 1000)
            },
            newId: { "unused" },
            hlc: HLC(device: "vec") { Int(box.value) }
        ))
        var e = Entities.empty()
        e.todos[template.id] = Todo(
            id: template.id,
            createdAt: "2026-10-04T09:00:00.000Z",
            updatedAt: "2026-10-04T09:00:00.000Z",
            clock: nil,
            title: template.title,
            notes: template.notes,
            projectId: nil,
            headingId: nil,
            areaId: nil,
            status: .open,
            start: .ready,
            startDate: nil,
            tonight: false,
            deadline: nil,
            tagIds: [],
            order: template.order,
            todayOrder: nil,
            completedAt: nil,
            trashedAt: nil,
            reminderAt: nil,
            repeat: RepeatRule(
                freq: freq,
                every: template.repeat.every,
                weekdays: nil,
                mode: mode,
                anchor: template.repeat.anchor,
                next: template.repeat.next,
                reminderTime: nil
            ),
            repeatTemplateId: nil
        )
        store.hydrate(e)
        return store
    }

    private static func snap(_ t: Todo) -> GeneratedTodoSnap {
        GeneratedTodoSnap(
            id: t.id,
            title: t.title,
            notes: t.notes,
            status: t.status.rawValue,
            start: t.start.rawValue,
            startDate: t.startDate,
            tonight: t.tonight,
            order: t.order,
            repeatTemplateId: t.repeatTemplateId,
            reminderAt: t.reminderAt,
            createdAt: t.createdAt,
            updatedAt: t.updatedAt
        )
    }

    @Test("Quick Find search and homeOf match shared vectors")
    func findVectors() throws {
        let file = try load()
        let find = try #require(file.find)
        let e = try findEntities(from: find.seed)
        let ctx = Lists.Context(today: find.today, keepVisible: nil)
        let finder = Find.buildFinder(e, ctx)
        for c in find.search {
            let hit = finder.search(c.query).first
            #expect(Self.findHit(hit, entities: e, ctx: ctx) == c.top, "find search \(c.query)")
        }
        for c in find.homeOf {
            let todo = try #require(e.todos[c.todoId])
            #expect(Self.webPath(entities: e, todo: todo, ctx: ctx) == c.path)
        }
    }

    private func findEntities(from seed: FindSeed) throws -> Entities {
        let ts = "2026-10-01T09:00:00.000Z"
        var e = Entities.empty()
        for tag in seed.tags {
            e.tags[tag.id] = Tag(
                id: tag.id,
                createdAt: ts,
                updatedAt: ts,
                clock: nil,
                title: tag.title,
                parentId: nil,
                order: "a0"
            )
        }
        for a in seed.areas {
            e.areas[a.id] = Area(
                id: a.id,
                createdAt: ts,
                updatedAt: ts,
                clock: nil,
                title: a.title,
                order: a.order,
                tagIds: [],
                trashedAt: a.trashedAt
            )
        }
        for p in seed.projects {
            guard let start = StartBucket(rawValue: p.start) else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: [], debugDescription: "bad project start \(p.start)")
                )
            }
            e.projects[p.id] = Project(
                id: p.id,
                createdAt: ts,
                updatedAt: ts,
                clock: nil,
                title: p.title,
                notes: "",
                areaId: p.areaId,
                status: .open,
                start: start,
                startDate: p.startDate,
                tonight: false,
                deadline: nil,
                tagIds: [],
                order: p.order,
                todayOrder: nil,
                completedAt: nil,
                trashedAt: p.trashedAt
            )
        }
        for t in seed.todos {
            guard let start = StartBucket(rawValue: t.start) else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: [], debugDescription: "bad todo start \(t.start)")
                )
            }
            guard let status = Status(rawValue: t.status) else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: [], debugDescription: "bad todo status \(t.status)")
                )
            }
            e.todos[t.id] = Todo(
                id: t.id,
                createdAt: ts,
                updatedAt: ts,
                clock: nil,
                title: t.title,
                notes: t.notes,
                projectId: t.projectId,
                headingId: nil,
                areaId: t.areaId,
                status: status,
                start: start,
                startDate: t.startDate,
                tonight: t.tonight,
                deadline: t.deadline,
                tagIds: t.tagIds,
                order: t.order,
                todayOrder: t.todayOrder,
                completedAt: t.completedAt,
                trashedAt: t.trashedAt,
                reminderAt: nil,
                repeat: nil,
                repeatTemplateId: nil
            )
        }
        return e
    }

    private static func findHit(
        _ result: Find.Result?,
        entities: Entities,
        ctx: Lists.Context
    ) -> FindHit? {
        guard let result else { return nil }
        let path: String
        switch result.destination {
        case .list(let name):
            path = name == .notNow ? "/backlog" : "/\(name.rawValue)"
        case .project(let id):
            path = "/project/\(id)"
        case .area(let id):
            path = "/area/\(id)"
        case .todo(let id, _):
            guard let todo = entities.todos[id] else { return nil }
            path = webPath(entities: entities, todo: todo, ctx: ctx)
        }
        return FindHit(
            kind: result.kind.rawValue,
            path: path,
            todoId: result.todoId,
            detail: result.detail
        )
    }

    /// Mirror web `homeOf(...).path` for shared-vector asserts.
    private static func webPath(entities: Entities, todo: Todo, ctx: Lists.Context) -> String {
        if Lists.isTrashed(entities, .todo(todo)) { return "/trash" }
        if todo.repeat != nil { return "/scheduled" }
        if Lists.isInDone(entities, .todo(todo), ctx) { return "/done" }
        if let project = Lists.projectOf(entities, todo) {
            return "/project/\(project.id)"
        }
        if let areaId = todo.areaId, entities.areas[areaId] != nil {
            return "/area/\(areaId)"
        }
        switch Find.homeOf(entities, todo, ctx).list {
        case .notNow: return "/backlog"
        default: return "/\(Find.homeOf(entities, todo, ctx).list.rawValue)"
        }
    }
}
