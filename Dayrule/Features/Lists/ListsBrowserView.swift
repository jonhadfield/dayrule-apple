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
    @State private var repeatTarget: EditTarget?
    @State private var reminderTarget: EditTarget?
    @State private var editTarget: EditTarget?
    @State private var projectPath: [ID] = []
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
                    HStack(spacing: 0) {
                        // Regular-width (iPad) active mark — PLAN §6.5.
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(selection == name ? colors.accent : .clear)
                            .frame(width: 3)
                            .padding(.trailing, 8)
                        Text(name.title)
                        Spacer()
                        if let badge = badge(for: name) {
                            Text("\(badge)")
                                .foregroundStyle(
                                    name == .today && counts.overdue > 0
                                        ? Tokens.Light.deadline
                                        : colors.textSecondary
                                )
                                .accessibilityLabel(sidebarBadgeLabel(name: name, count: badge))
                        }
                    }
                    .accessibilityIdentifier("list.sidebar.\(name.rawValue)")
                    .tag(Optional(name))
                    .listRowBackground(colors.sidebar)
                }
            }
            .navigationTitle("Dayrule")
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
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
            NavigationStack(path: $projectPath) {
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
                                            label: checkboxLabel(for: row)
                                        ) {
                                            toggleComplete(row.id, title: row.title)
                                        }
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(row.title)
                                                .foregroundStyle(colors.text)
                                                .strikethrough(row.status != .open)
                                            if row.hasReminder, row.status == .open {
                                                Image(systemName: "bell")
                                                    .font(.caption)
                                                    .foregroundStyle(colors.textSecondary)
                                                    .accessibilityLabel("Has a reminder")
                                            }
                                            if row.isRepeating {
                                                Image(systemName: "repeat")
                                                    .font(.caption)
                                                    .foregroundStyle(colors.textSecondary)
                                                    .accessibilityLabel("Repeating")
                                            }
                                            if row.hasNotes {
                                                Image(systemName: "doc.text")
                                                    .font(.caption)
                                                    .foregroundStyle(colors.textSecondary)
                                                    .accessibilityLabel("Has notes")
                                            }
                                            if let checklist = row.checklistLabel {
                                                Text(checklist)
                                                    .font(.caption)
                                                    .foregroundStyle(colors.textSecondary)
                                                    .accessibilityLabel(checklist + " done")
                                            }
                                        }
                                        .accessibilityElement(children: .combine)
                                        .accessibilityLabel(rowTitleAccessibility(row))
                                        .accessibilityIdentifier("list.todo.\(row.id)")
                                        if let subtitle = row.subtitle {
                                            HStack(spacing: 4) {
                                                if row.deadlineOverdue {
                                                    Image(systemName: "exclamationmark.circle.fill")
                                                        .font(.caption2)
                                                        .foregroundStyle(Tokens.Light.deadline)
                                                        .accessibilityLabel("Overdue")
                                                }
                                                Text(subtitle)
                                                    .font(.caption)
                                                    .foregroundStyle(
                                                        row.deadlineOverdue
                                                            ? Tokens.Light.deadline
                                                            : colors.textSecondary
                                                    )
                                            }
                                        }
                                    }
                                    Spacer(minLength: 0)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard activeList != .trash else { return }
                                if !row.isTodo, model.entities.projects[row.id] != nil {
                                    projectPath = [row.id]
                                } else {
                                    editTarget = EditTarget(id: row.id)
                                }
                            }
                            .accessibilityAction(named: Text("When…")) {
                                whenTarget = WhenTarget(ids: [row.id])
                            }
                            .accessibilityAction(named: Text("Move up")) {
                                guard row.isTodo else { return }
                                moveTodo(row.id, dir: -1)
                            }
                            .accessibilityAction(named: Text("Move down")) {
                                guard row.isTodo else { return }
                                moveTodo(row.id, dir: 1)
                            }
                            .contextMenu {
                                if activeList == .trash {
                                    Button("Restore") { restore(row.id) }
                                } else {
                                    if !row.isTodo, model.entities.projects[row.id] != nil {
                                        Button("Open") { projectPath = [row.id] }
                                    }
                                    if row.isTodo, let pid = model.entities.todos[row.id]?.projectId {
                                        Button("Open Project") { projectPath = [pid] }
                                    }
                                    Button("Edit") { editTarget = EditTarget(id: row.id) }
                                    Button("When…") { whenTarget = WhenTarget(ids: [row.id]) }
                                    Button("Deadline…") { deadlineTarget = WhenTarget(ids: [row.id]) }
                                    Button("Tags…") { tagTarget = WhenTarget(ids: [row.id]) }
                                    if row.isTodo {
                                        Button("Repeat…") { repeatTarget = EditTarget(id: row.id) }
                                        Button("Reminder…") { reminderTarget = EditTarget(id: row.id) }
                                    }
                                    if row.isTodo, row.status == .open {
                                        Button("Complete") { toggleComplete(row.id, title: row.title) }
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
                .navigationDestination(for: ID.self) { projectId in
                    ProjectDetailView(model: model, projectId: projectId)
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
                .sheet(item: $repeatTarget) { target in
                    RepeatSheetView(model: model, todoId: target.id)
                }
                .sheet(item: $reminderTarget) { target in
                    ReminderSheetView(model: model, todoId: target.id)
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
        }
        .onChange(of: selection) { _, _ in projectPath = [] }
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
                todoRow(
                    $0,
                    subtitle: deadlineSubtitle($0.deadline),
                    overdue: Lists.isOverdue(.todo($0), ctx)
                )
            }
        case .today:
            return Lists.today(model.entities, ctx).map {
                let kind = $0.isTodo ? nil : "Project"
                let deadline = deadlineSubtitle($0.deadline)
                let subtitle = [kind, deadline].compactMap { $0 }.joined(separator: " · ")
                if $0.isTodo, let t = model.entities.todos[$0.id] {
                    return todoRow(t, subtitle: subtitle.isEmpty ? nil : subtitle, overdue: Lists.isOverdue($0, ctx))
                }
                return Row(
                    id: $0.id,
                    title: $0.title,
                    subtitle: subtitle.isEmpty ? nil : subtitle,
                    isTodo: false,
                    status: $0.status,
                    deadlineOverdue: Lists.isOverdue($0, ctx)
                )
            }
        case .scheduled:
            let s = Lists.scheduled(model.entities, ctx)
            return s.days.flatMap { day in
                day.items.map {
                    if $0.isTodo, let t = model.entities.todos[$0.id] {
                        return todoRow(t, subtitle: day.date, overdue: false)
                    }
                    return Row(id: $0.id, title: $0.title, subtitle: day.date, isTodo: false, status: $0.status)
                }
            }
        case .backlog:
            return Lists.backlog(model.entities, ctx).flatMap { g in
                g.todos.map {
                    todoRow($0, subtitle: containerLabel(g.container), overdue: false)
                }
            }
        case .notNow:
            let n = Lists.notNow(model.entities, ctx)
            return n.projects.map {
                Row(id: $0.id, title: $0.title, subtitle: "Project", isTodo: false, status: $0.status)
            } + n.todos.map {
                todoRow($0, subtitle: nil, overdue: false)
            }
        case .done:
            return Lists.doneList(model.entities, ctx).flatMap { day in
                day.items.map {
                    if $0.isTodo, let t = model.entities.todos[$0.id] {
                        return todoRow(t, subtitle: day.date, overdue: false)
                    }
                    return Row(id: $0.id, title: $0.title, subtitle: day.date, isTodo: false, status: $0.status)
                }
            }
        case .trash:
            let t = Lists.trash(model.entities)
            return t.areas.map {
                Row(id: $0.id, title: $0.title, subtitle: "Area", isTodo: false, status: .open)
            } + t.items.map {
                if $0.isTodo, let todo = model.entities.todos[$0.id] {
                    return todoRow(todo, subtitle: nil, overdue: false)
                }
                return Row(id: $0.id, title: $0.title, subtitle: nil, isTodo: $0.isTodo, status: $0.status)
            }
        }
    }

    private func todoRow(_ todo: Todo, subtitle: String?, overdue: Bool) -> Row {
        let checklist = model.entities.checklistItems.values.filter { $0.todoId == todo.id }
        let done = checklist.filter(\.done).count
        return Row(
            id: todo.id,
            title: todo.title.isEmpty ? "Untitled" : todo.title,
            subtitle: subtitle,
            isTodo: true,
            status: todo.status,
            deadlineOverdue: overdue,
            hasReminder: todo.reminderAt != nil,
            isRepeating: todo.repeat != nil || todo.repeatTemplateId != nil,
            hasNotes: !todo.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            checklistLabel: checklist.isEmpty ? nil : "\(done) of \(checklist.count)"
        )
    }

    private func checkboxLabel(for row: Row) -> String {
        let title = row.title.isEmpty ? "to-do" : row.title
        return row.status == .open ? "Complete \(title)" : "Reopen \(title)"
    }

    private func rowTitleAccessibility(_ row: Row) -> String {
        var parts = [row.title]
        if row.hasReminder, row.status == .open { parts.append("Has a reminder") }
        if row.isRepeating { parts.append("Repeating") }
        if row.hasNotes { parts.append("Has notes") }
        if let checklist = row.checklistLabel { parts.append("\(checklist) done") }
        if row.deadlineOverdue { parts.append("Overdue") }
        return parts.joined(separator: ", ")
    }

    private func sidebarBadgeLabel(name: ListName, count: Int) -> String {
        if name == .today, counts.overdue > 0 {
            return "\(count) items, \(counts.overdue) overdue"
        }
        return "\(count)"
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

    /// Keyboard / VoiceOver reorder (web `useGlobalKeys` Move).
    private func moveTodo(_ id: ID, dir: Int) {
        let visible = rows(for: activeList).filter(\.isTodo).map(\.id)
        guard let i = visible.firstIndex(of: id) else { return }
        let rest = visible.filter { $0 != id }
        let target = max(0, min(rest.count, i + dir))
        guard target != i else { return }
        let field: Commands.OrderField = activeList == .today ? .todayOrder : .order
        let before: ID? = target > 0 ? rest[target - 1] : nil
        let after: ID? = target < rest.count ? rest[target] : nil
        do {
            try model.store.run("Move") { d, env in
                try Commands.reorder(
                    d,
                    env,
                    collection: .todos,
                    id: id,
                    field: field,
                    before: before,
                    after: after
                )
            }
            model.noteEntitiesChanged()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func toggleComplete(_ id: ID, title: String) {
        let open = model.entities.todos[id]?.status == .open
            || model.entities.projects[id]?.status == .open
        let status: Status = open ? .completed : .open
        model.store.run(status == .completed ? "Complete" : "Reopen") { d, env in
            Commands.setStatus(d, env, ids: [id], status: status)
        }
        model.noteEntitiesChanged()
        if status == .completed {
            // Visual linger is too short for VoiceOver (PLAN §6.7).
            AccessibilityNotification.Announcement("Completed \(title).").post()
        }
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
            projectPath = []
        case .todo(let id, let home):
            selection = home
            projectPath = []
            editTarget = EditTarget(id: id)
        case .project(let id):
            selection = .backlog
            projectPath = [id]
        case .area:
            selection = .backlog
            projectPath = []
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
        var hasReminder: Bool = false
        var isRepeating: Bool = false
        var hasNotes: Bool = false
        var checklistLabel: String?
    }
}

