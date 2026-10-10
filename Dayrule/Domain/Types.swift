import Foundation

typealias ID = String
typealias Timestamp = String

enum Status: String, Codable, Sendable, Equatable {
    case open, completed, canceled
}

/// Where an item sits before scheduling (web `StartBucket`).
enum StartBucket: String, Codable, Sendable, Equatable {
    case inbox, ready, later
}

struct Area: Equatable, Sendable {
    var id: ID
    var createdAt: Timestamp
    var updatedAt: Timestamp
    var clock: FieldClock?
    var title: String
    var order: OrderKey
    var tagIds: [ID]
    var trashedAt: Timestamp?
}

struct Project: Equatable, Sendable {
    var id: ID
    var createdAt: Timestamp
    var updatedAt: Timestamp
    var clock: FieldClock?
    var title: String
    var notes: String
    var areaId: ID?
    var status: Status
    /// Never `inbox` for projects.
    var start: StartBucket
    var startDate: LocalDate?
    var tonight: Bool
    var deadline: LocalDate?
    var tagIds: [ID]
    var order: OrderKey
    var todayOrder: OrderKey?
    var completedAt: Timestamp?
    var trashedAt: Timestamp?
}

struct Heading: Equatable, Sendable {
    var id: ID
    var createdAt: Timestamp
    var updatedAt: Timestamp
    var clock: FieldClock?
    var projectId: ID
    var title: String
    var order: OrderKey
    var archived: Bool
}

struct RepeatRule: Equatable, Sendable {
    enum Freq: String, Codable, Sendable { case day, week, month, year }
    enum Mode: String, Codable, Sendable { case fixed, afterCompletion }

    var freq: Freq
    var every: Int
    var weekdays: [Int]?
    var mode: Mode
    var anchor: LocalDate
    var next: LocalDate?
    var reminderTime: String?
}

struct Todo: Equatable, Sendable {
    var id: ID
    var createdAt: Timestamp
    var updatedAt: Timestamp
    var clock: FieldClock?
    var title: String
    var notes: String
    var projectId: ID?
    var headingId: ID?
    var areaId: ID?
    var status: Status
    var start: StartBucket
    var startDate: LocalDate?
    var tonight: Bool
    var deadline: LocalDate?
    var tagIds: [ID]
    var order: OrderKey
    var todayOrder: OrderKey?
    var completedAt: Timestamp?
    var trashedAt: Timestamp?
    var reminderAt: String?
    var `repeat`: RepeatRule?
    var repeatTemplateId: ID?
}

struct ChecklistItem: Equatable, Sendable {
    var id: ID
    var createdAt: Timestamp
    var updatedAt: Timestamp
    var clock: FieldClock?
    var todoId: ID
    var title: String
    var done: Bool
    var order: OrderKey
}

struct Tag: Equatable, Sendable {
    var id: ID
    var createdAt: Timestamp
    var updatedAt: Timestamp
    var clock: FieldClock?
    var title: String
    var parentId: ID?
    var order: OrderKey
}

enum DoneMode: String, Codable, Sendable, Equatable {
    case immediately, daily, manually
}

struct Settings: Equatable, Sendable {
    var clock: FieldClock?
    var moveToDone: DoneMode
    var lastMovedToDoneAt: Timestamp?
}

struct Entities: Equatable, Sendable {
    var areas: [ID: Area]
    var projects: [ID: Project]
    var headings: [ID: Heading]
    var todos: [ID: Todo]
    var checklistItems: [ID: ChecklistItem]
    var tags: [ID: Tag]
    var settings: Settings

    static func empty() -> Entities {
        Entities(
            areas: [:],
            projects: [:],
            headings: [:],
            todos: [:],
            checklistItems: [:],
            tags: [:],
            settings: Settings(clock: nil, moveToDone: .immediately, lastMovedToDoneAt: nil)
        )
    }
}

/// Todo or Project as list row payload (web `Item`).
enum ListItem: Equatable, Sendable {
    case todo(Todo)
    case project(Project)

    var id: ID {
        switch self {
        case .todo(let t): t.id
        case .project(let p): p.id
        }
    }

    var title: String {
        switch self {
        case .todo(let t): t.title
        case .project(let p): p.title
        }
    }

    var status: Status {
        switch self {
        case .todo(let t): t.status
        case .project(let p): p.status
        }
    }

    var start: StartBucket {
        switch self {
        case .todo(let t): t.start
        case .project(let p): p.start
        }
    }

    var startDate: LocalDate? {
        switch self {
        case .todo(let t): t.startDate
        case .project(let p): p.startDate
        }
    }

    var deadline: LocalDate? {
        switch self {
        case .todo(let t): t.deadline
        case .project(let p): p.deadline
        }
    }

    var order: OrderKey {
        switch self {
        case .todo(let t): t.order
        case .project(let p): p.order
        }
    }

    var todayOrder: OrderKey? {
        switch self {
        case .todo(let t): t.todayOrder
        case .project(let p): p.todayOrder
        }
    }

    var completedAt: Timestamp? {
        switch self {
        case .todo(let t): t.completedAt
        case .project(let p): p.completedAt
        }
    }

    var trashedAt: Timestamp? {
        switch self {
        case .todo(let t): t.trashedAt
        case .project(let p): p.trashedAt
        }
    }

    var areaId: ID? {
        switch self {
        case .todo(let t): t.areaId
        case .project(let p): p.areaId
        }
    }

    var tagIds: [ID] {
        switch self {
        case .todo(let t): t.tagIds
        case .project(let p): p.tagIds
        }
    }

    var isTodo: Bool {
        if case .todo = self { return true }
        return false
    }

    var asTodo: Todo? {
        if case .todo(let t) = self { return t }
        return nil
    }

    var asProject: Project? {
        if case .project(let p) = self { return p }
        return nil
    }
}
