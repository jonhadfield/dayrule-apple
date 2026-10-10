import SwiftUI

/// Read-only list shell (M3): Inbox → Trash over Entities from the vault.
struct ListsBrowserView: View {
    @Bindable var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var selection: ListName = .inbox
    @State private var draftTitle = ""

    var body: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme)
        NavigationSplitView {
            List(ListName.allCases, id: \.self, selection: $selection) { name in
                HStack {
                    Text(name.title)
                    Spacer()
                    if let badge = badge(for: name) {
                        Text("\(badge)")
                            .foregroundStyle(
                                name == .today && counts.overdue > 0
                                    ? Tokens.Light.deadline
                                    : colors.textSecondary
                            )
                    }
                }
                .tag(name)
            }
            .navigationTitle("Dayrule")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Lock") { model.lock() }
                        .foregroundStyle(colors.accent)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Refresh") {
                        Task { await model.refreshVault() }
                    }
                    .foregroundStyle(colors.accent)
                }
            }
        } detail: {
            List {
                if model.vaultLoading && model.vault == nil {
                    Text("Pulling vault…")
                        .foregroundStyle(colors.textSecondary)
                } else if let errorMessage = model.errorMessage, model.vault == nil {
                    Text(errorMessage)
                        .foregroundStyle(Tokens.Light.deadline)
                } else if rows(for: selection).isEmpty {
                    Text(emptyCopy(for: selection))
                        .foregroundStyle(colors.textSecondary)
                } else {
                    ForEach(rows(for: selection), id: \.id) { row in
                        HStack(alignment: .top, spacing: 10) {
                            if row.isTodo {
                                Button {
                                    toggleComplete(row.id)
                                } label: {
                                    Image(systemName: row.completed ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(colors.accent)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(row.completed ? "Reopen" : "Complete")
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.title)
                                    .foregroundStyle(colors.text)
                                    .strikethrough(row.completed)
                                if let subtitle = row.subtitle {
                                    Text(subtitle)
                                        .font(.caption)
                                        .foregroundStyle(colors.textSecondary)
                                }
                            }
                        }
                    }
                }
                if selection == .inbox || selection == .today {
                    HStack {
                        TextField("Add", text: $draftTitle)
                            .onSubmit(addTodo)
                        Button("Add", action: addTodo)
                            .foregroundStyle(colors.accent)
                            .disabled(draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .navigationTitle(selection.title)
            .scrollContentBackground(.hidden)
            .background(colors.bg)
            .toolbar {
                ToolbarItemGroup(placement: .automatic) {
                    Button("Undo") {
                        _ = model.store.undo()
                        model.noteEntitiesChanged()
                    }
                    .disabled(!model.store.canUndo)
                    Button("Redo") {
                        _ = model.store.redo()
                        model.noteEntitiesChanged()
                    }
                    .disabled(!model.store.canRedo)
                }
            }
        }
        #if os(iOS)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0).onChanged { _ in model.bumpIdle() }
        )
        #endif
    }

    private var ctx: Lists.Context {
        Lists.Context(today: When.toLocalDate(Date()), keepVisible: nil)
    }

    private var counts: Lists.SidebarCounts {
        Lists.sidebarCounts(model.entities, ctx)
    }

    private func badge(for name: ListName) -> Int? {
        switch name {
        case .inbox: counts.inbox
        case .today: counts.today
        default: nil
        }
    }

    private func rows(for name: ListName) -> [Row] {
        switch name {
        case .inbox:
            return Lists.inbox(model.entities, ctx).map {
                Row(id: $0.id, title: $0.title, subtitle: nil, isTodo: true, completed: $0.status != .open)
            }
        case .today:
            return Lists.today(model.entities, ctx).map {
                Row(
                    id: $0.id,
                    title: $0.title,
                    subtitle: $0.isTodo ? nil : "Project",
                    isTodo: $0.isTodo,
                    completed: $0.status != .open
                )
            }
        case .scheduled:
            let s = Lists.scheduled(model.entities, ctx)
            return s.days.flatMap { day in
                day.items.map {
                    Row(id: $0.id, title: $0.title, subtitle: day.date, isTodo: $0.isTodo, completed: $0.status != .open)
                }
            }
        case .backlog:
            return Lists.backlog(model.entities, ctx).flatMap { g in
                g.todos.map {
                    Row(
                        id: $0.id,
                        title: $0.title,
                        subtitle: containerLabel(g.container),
                        isTodo: true,
                        completed: $0.status != .open
                    )
                }
            }
        case .notNow:
            let n = Lists.notNow(model.entities, ctx)
            return n.projects.map {
                Row(id: $0.id, title: $0.title, subtitle: "Project", isTodo: false, completed: $0.status != .open)
            } + n.todos.map {
                Row(id: $0.id, title: $0.title, subtitle: nil, isTodo: true, completed: $0.status != .open)
            }
        case .done:
            return Lists.doneList(model.entities, ctx).flatMap { day in
                day.items.map {
                    Row(id: $0.id, title: $0.title, subtitle: day.date, isTodo: $0.isTodo, completed: true)
                }
            }
        case .trash:
            let t = Lists.trash(model.entities)
            return t.areas.map {
                Row(id: $0.id, title: $0.title, subtitle: "Area", isTodo: false, completed: false)
            } + t.items.map {
                Row(id: $0.id, title: $0.title, subtitle: nil, isTodo: $0.isTodo, completed: $0.status != .open)
            }
        }
    }

    private func addTodo() {
        let title = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let placement: Commands.Placement = selection == .today ? .today : .inbox
        do {
            _ = try model.store.run("Add") { d, env in
                try Commands.createTodo(d, env, .init(title: title, placement: placement))
            }
            draftTitle = ""
            model.noteEntitiesChanged()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func toggleComplete(_ id: ID) {
        let status: Status = model.entities.todos[id]?.status == .open ? .completed : .open
        model.store.run(status == .completed ? "Complete" : "Reopen") { d, env in
            Commands.setStatus(d, env, ids: [id], status: status)
        }
        model.noteEntitiesChanged()
    }

    private func containerLabel(_ c: Lists.Container) -> String? {
        switch c {
        case .none: nil
        case .area(let a): a.title
        case .project(let p): p.title
        }
    }

    private func emptyCopy(for name: ListName) -> String {
        if model.vault == nil { return "Pull the vault to see lists." }
        return "Nothing in \(name.title)."
    }

    private struct Row: Identifiable {
        var id: String
        var title: String
        var subtitle: String?
        var isTodo: Bool
        var completed: Bool
    }
}

private enum ListName: String, CaseIterable, Hashable {
    case inbox, today, scheduled, backlog, notNow, done, trash

    var title: String {
        switch self {
        case .inbox: "Inbox"
        case .today: "Today"
        case .scheduled: "Scheduled"
        case .backlog: "Backlog"
        case .notNow: "Not now"
        case .done: "Done"
        case .trash: "Trash"
        }
    }
}
