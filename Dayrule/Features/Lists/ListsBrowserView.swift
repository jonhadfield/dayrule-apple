import SwiftUI

private struct WhenTarget: Identifiable {
    var id: String { ids.joined(separator: ",") }
    var ids: [ID]
}

/// List shell (M3): Inbox → Trash over Entities from the vault / store.
struct ListsBrowserView: View {
    @Bindable var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var selection: ListName? = .inbox
    @State private var draftTitle = ""
    @State private var whenTarget: WhenTarget?
    @State private var deadlineTarget: WhenTarget?
    @State private var tagTarget: WhenTarget?
    @State private var editTarget: EditTarget?
    @State private var showFind = false

    private struct EditTarget: Identifiable {
        var id: ID
    }

    private var activeList: ListName { selection ?? .inbox }

    var body: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme)
        NavigationSplitView {
            List(selection: $selection) {
                if model.syncStatus == .needsUpdate {
                    Text(model.syncStatus.label)
                        .font(.footnote)
                        .foregroundStyle(Tokens.Light.deadline)
                        .listRowBackground(colors.sidebar)
                }
                ForEach(ListName.allCases, id: \.self) { name in
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
                    .accessibilityIdentifier("list.sidebar.\(name.rawValue)")
                    .tag(Optional(name))
                }
            }
            .navigationTitle("Dayrule")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Lock") { model.lock() }
                        .foregroundStyle(colors.accent)
                }
                ToolbarItem(placement: .automatic) {
                    Button("Find") { showFind = true }
                        .foregroundStyle(colors.accent)
                        .accessibilityIdentifier("sidebar.find")
                }
                ToolbarItem(placement: .automatic) {
                    Button("Settings") { model.showSettings = true }
                        .foregroundStyle(colors.accent)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Refresh") {
                        Task { await model.refreshVault() }
                    }
                    .foregroundStyle(colors.accent)
                }
            }
            .sheet(isPresented: $model.showSettings) {
                SettingsView(model: model)
            }
        } detail: {
            List {
                // Never replace existing rows with a sync banner — that races Add in e2e
                // and hides todos for the whole push/pull.
                if rows(for: activeList).isEmpty {
                    if model.syncStatus == .syncing || model.vaultLoading {
                        Text(model.syncStatus == .syncing ? "Syncing…" : "Pulling vault…")
                            .foregroundStyle(colors.textSecondary)
                    } else if let errorMessage = model.errorMessage, model.vault == nil {
                        Text(errorMessage)
                            .foregroundStyle(Tokens.Light.deadline)
                    } else {
                        RuledRow {
                            Text(emptyCopy(for: activeList))
                                .foregroundStyle(colors.textSecondary)
                        }
                    }
                } else {
                    ForEach(rows(for: activeList), id: \.id) { row in
                        RuledRow {
                            HStack(alignment: .center, spacing: 10) {
                                if row.isTodo {
                                    DayruleCheckbox(
                                        status: row.status,
                                        label: row.status == .open ? "Complete" : "Reopen"
                                    ) {
                                        toggleComplete(row.id)
                                    }
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.title)
                                        .foregroundStyle(colors.text)
                                        .strikethrough(row.status != .open)
                                        .accessibilityLabel(row.title)
                                        .accessibilityIdentifier("list.todo.\(row.id)")
                                    if let subtitle = row.subtitle {
                                        Text(subtitle)
                                            .font(.caption)
                                            .foregroundStyle(
                                                row.deadlineOverdue
                                                    ? Tokens.Light.deadline
                                                    : colors.textSecondary
                                            )
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if activeList != .trash { editTarget = EditTarget(id: row.id) }
                        }
                        .contextMenu {
                            if activeList == .trash {
                                Button("Restore") { restore(row.id) }
                            } else {
                                Button("Edit") { editTarget = EditTarget(id: row.id) }
                                Button("When…") { whenTarget = WhenTarget(ids: [row.id]) }
                                Button("Deadline…") { deadlineTarget = WhenTarget(ids: [row.id]) }
                                Button("Tags…") { tagTarget = WhenTarget(ids: [row.id]) }
                                if row.isTodo, row.status == .open {
                                    Button("Complete") { toggleComplete(row.id) }
                                }
                                Button("Trash", role: .destructive) { trash(row.id) }
                            }
                        }
                    }
                }
                if activeList == .inbox || activeList == .today {
                    RuledRow {
                        HStack {
                            TextField("Add", text: $draftTitle)
                                .accessibilityIdentifier("list.addField")
                                .onSubmit(addTodo)
                            Button("Add", action: addTodo)
                                .accessibilityIdentifier("list.addButton")
                                .foregroundStyle(colors.accent)
                                .disabled(draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                // List rows can swallow Button actions; explicit role helps XCUITest.
                                .buttonStyle(.borderless)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle(activeList.title)
            .scrollContentBackground(.hidden)
            .background(colors.bg)
            .toolbar {
                ToolbarItemGroup(placement: .automatic) {
                    Button("Find") { showFind = true }
                        .accessibilityIdentifier("list.find")
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
                    if activeList == .trash {
                        Button("Empty Trash", role: .destructive) { emptyTrash() }
                            .accessibilityIdentifier("list.emptyTrash")
                            .disabled(rows(for: .trash).isEmpty)
                    }
                    if activeList == .done, model.entities.settings.moveToDone == .manually {
                        Button("Log Completed") { logCompleted() }
                            .accessibilityIdentifier("list.logCompleted")
                    }
                }
            }
            .sheet(item: $whenTarget) { target in
                WhenSheetView(model: model, ids: target.ids)
            }
            .sheet(item: $deadlineTarget) { target in
                DeadlineSheetView(model: model, ids: target.ids)
            }
            .sheet(item: $tagTarget) { target in
                TagSheetView(model: model, ids: target.ids)
            }
            .sheet(item: $editTarget) { target in
                ItemEditorSheet(model: model, id: target.id)
            }
            .sheet(isPresented: $showFind) {
                QuickFindView(model: model) { result in
                    applyFind(result)
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
                Row(
                    id: $0.id,
                    title: $0.title,
                    subtitle: deadlineSubtitle($0.deadline),
                    isTodo: true,
                    status: $0.status,
                    deadlineOverdue: Lists.isOverdue(.todo($0), ctx)
                )
            }
        case .today:
            return Lists.today(model.entities, ctx).map {
                let kind = $0.isTodo ? nil : "Project"
                let deadline = deadlineSubtitle($0.deadline)
                let subtitle = [kind, deadline].compactMap { $0 }.joined(separator: " · ")
                return Row(
                    id: $0.id,
                    title: $0.title,
                    subtitle: subtitle.isEmpty ? nil : subtitle,
                    isTodo: $0.isTodo,
                    status: $0.status,
                    deadlineOverdue: Lists.isOverdue($0, ctx)
                )
            }
        case .scheduled:
            let s = Lists.scheduled(model.entities, ctx)
            return s.days.flatMap { day in
                day.items.map {
                    Row(id: $0.id, title: $0.title, subtitle: day.date, isTodo: $0.isTodo, status: $0.status)
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
                        status: $0.status
                    )
                }
            }
        case .notNow:
            let n = Lists.notNow(model.entities, ctx)
            return n.projects.map {
                Row(id: $0.id, title: $0.title, subtitle: "Project", isTodo: false, status: $0.status)
            } + n.todos.map {
                Row(id: $0.id, title: $0.title, subtitle: nil, isTodo: true, status: $0.status)
            }
        case .done:
            return Lists.doneList(model.entities, ctx).flatMap { day in
                day.items.map {
                    Row(id: $0.id, title: $0.title, subtitle: day.date, isTodo: $0.isTodo, status: $0.status)
                }
            }
        case .trash:
            let t = Lists.trash(model.entities)
            return t.areas.map {
                Row(id: $0.id, title: $0.title, subtitle: "Area", isTodo: false, status: .open)
            } + t.items.map {
                Row(id: $0.id, title: $0.title, subtitle: nil, isTodo: $0.isTodo, status: $0.status)
            }
        }
    }

    private func addTodo() {
        let title = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let placement: Commands.Placement = activeList == .today ? .today : .inbox
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
        let open = model.entities.todos[id]?.status == .open
            || model.entities.projects[id]?.status == .open
        let status: Status = open ? .completed : .open
        model.store.run(status == .completed ? "Complete" : "Reopen") { d, env in
            Commands.setStatus(d, env, ids: [id], status: status)
        }
        model.noteEntitiesChanged()
    }

    private func trash(_ id: ID) {
        model.store.run("Trash") { d, env in
            Commands.trashItems(d, env, ids: [id])
        }
        model.noteEntitiesChanged()
    }

    private func restore(_ id: ID) {
        model.store.run("Restore") { d, env in
            Commands.restoreItems(d, env, ids: [id])
        }
        model.noteEntitiesChanged()
    }

    private func emptyTrash() {
        model.store.run("Empty Trash") { d, _ in
            Commands.emptyTrash(d)
        }
        model.noteEntitiesChanged()
    }

    private func logCompleted() {
        model.store.run("Move to Done") { d, env in
            Commands.moveToDoneNow(d, env)
        }
        model.noteEntitiesChanged()
    }

    private func applyFind(_ result: Find.Result) {
        switch result.destination {
        case .list(let name):
            selection = name
        case .todo(let id, let home):
            selection = home
            editTarget = EditTarget(id: id)
        case .project(let id):
            selection = .backlog
            editTarget = EditTarget(id: id)
        case .area:
            selection = .backlog
        }
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

    private func deadlineSubtitle(_ deadline: LocalDate?) -> String? {
        guard let deadline else { return nil }
        return "Due \(deadline)"
    }

    private struct Row: Identifiable {
        var id: String
        var title: String
        var subtitle: String?
        var isTodo: Bool
        var status: Status
        var deadlineOverdue: Bool = false
    }
}

