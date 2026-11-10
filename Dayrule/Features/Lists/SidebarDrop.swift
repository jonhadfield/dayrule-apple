import Foundation
import SwiftUI

/// Sidebar drop targets for dragged to-dos (web `DropTarget` / `DragLayer`).
enum SidebarDropAction: Equatable, Sendable {
    case move(Commands.MoveTarget)
    case when(Commands.When)
    case complete
    case trash
}

enum SidebarDrop {
    /// Action for a top-level list row. `today` is the local calendar day.
    static func action(for list: ListName, today: LocalDate) -> SidebarDropAction {
        switch list {
        case .inbox: .move(.inbox)
        case .today: .when(.today)
        case .scheduled: .when(.date(When.addLocalDays(today, 1)))
        case .backlog: .move(.none)
        case .notNow: .when(.later)
        case .done: .complete
        case .trash: .trash
        }
    }

    static func action(projectId: ID) -> SidebarDropAction {
        .move(.project(projectId: projectId, headingId: nil))
    }

    static func action(areaId: ID) -> SidebarDropAction {
        .move(.area(areaId: areaId))
    }
}

/// Accepts dragged to-do ids (`String` / `ID`) onto a sidebar row.
struct SidebarDropDestination: ViewModifier {
    var action: SidebarDropAction
    var onDrop: ([ID]) -> Void
    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .dropDestination(for: String.self) { items, _ in
                onDrop(items)
                return !items.isEmpty
            } isTargeted: { hovering in
                isTargeted = hovering
            }
            .overlay {
                if isTargeted {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.accentColor.opacity(0.18))
                        .padding(.horizontal, 2)
                        .allowsHitTesting(false)
                }
            }
    }
}
