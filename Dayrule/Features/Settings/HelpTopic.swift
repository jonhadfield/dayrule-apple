import Foundation

/// Help topics shipped in the app (web `features/help/topics.ts`). Offline; no network.
enum HelpTopic: String, CaseIterable, Identifiable {
    case start
    case lists
    case scheduling
    case projects
    case devices
    case privacy
    case shortcuts
    case data

    var id: String { rawValue }

    var title: String {
        switch self {
        case .start: "Getting started"
        case .lists: "The lists"
        case .scheduling: "Dates, deadlines and repeats"
        case .projects: "Projects and areas"
        case .devices: "Phones, computers and sync"
        case .privacy: "Your password and privacy"
        case .shortcuts: "Shortcuts and gestures"
        case .data: "Your data"
        }
    }

    var summary: String {
        switch self {
        case .start: "Add to-dos, sort them, get them done."
        case .lists: "Inbox, Today, Scheduled, Backlog, Done and Trash."
        case .scheduling: "When to start something, when it’s due, and doing it again."
        case .projects: "Group to-dos into bigger pieces of work."
        case .devices: "Use Dayrule everywhere, even offline."
        case .privacy: "How encryption works, and what to keep safe."
        case .shortcuts: "Swipes on a phone, menus on a Mac."
        case .data: "Export, import, Done, Trash and deleting your account."
        }
    }
}
