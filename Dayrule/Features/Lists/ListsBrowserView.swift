import SwiftUI

private struct WhenTarget: Identifiable {
    var id: String { ids.joined(separator: ",") }
    var ids: [ID]
}

/// Phone stack routes (PLAN §6.5: home → list → project).
private enum PhoneRoute: Hashable {
    case list(ListName)
    case project(ID)
}

/// Compact bottom bar: daily path + Browse (Backlog / Done / Trash / projects).
private enum PhoneTab: Hashable, CaseIterable {
    case inbox, today, scheduled, browse

    var title: String {
        switch self {
        case .inbox: "Inbox"
        case .today: "Today"
        case .scheduled: "Scheduled"
        case .browse: "Browse"
        }
    }

    /// Stable SF Symbols — same on every screen; only colour marks selection.
    var systemImage: String {
        switch self {
        case .inbox: "tray"
        case .today: "sun.max"
        case .scheduled: "calendar"
        case .browse: "square.grid.2x2"
        }
    }

    var listName: ListName? {
        switch self {
        case .inbox: .inbox
        case .today: .today
        case .scheduled: .scheduled
        case .browse: nil
        }
    }

    static func tab(for list: ListName) -> PhoneTab? {
        switch list {
        case .inbox: .inbox
        case .today: .today
        case .scheduled: .scheduled
        default: nil
        }
    }

    /// Lists shown under Browse (primary three live on the tab bar).
    static let browseLists: [ListName] = [.backlog, .done, .trash]
}

/// List shell (M3): Inbox → Trash over Entities from the vault / store.
struct ListsBrowserView: View {
    @Bindable var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selection: ListName? = .inbox
    /// Compact: Browse root; push for Backlog / Done / Trash / projects.
    @State private var phonePath: [PhoneRoute] = []
    @State private var phoneTab: PhoneTab = .inbox
    @State private var didApplyDefaultList = false
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
    private var isCompact: Bool { horizontalSizeClass == .compact }

    var body: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme)
        Group {
            if isCompact {
                phoneBrowser(colors: colors)
            } else {
                splitBrowser(colors: colors)
            }
        }
        .onAppear { applyDefaultDestinationIfNeeded() }
        .onChange(of: model.vaultLoading) { _, loading in
            if !loading { applyDefaultDestinationIfNeeded() }
        }
        .onChange(of: selection) { _, _ in
            if !isCompact { projectPath = [] }
        }
        .onChange(of: phonePath) { _, path in
            if let name = path.reversed().compactMap({ route -> ListName? in
                if case .list(let n) = route { return n }
                return nil
            }).first {
                selection = name
            }
        }
        .onChange(of: phoneTab) { _, tab in
            phonePath = []
            if let name = tab.listName {
                selection = name
            }
        }
        .sheet(isPresented: $model.showSettings) {
            SettingsView(model: model)
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

    // MARK: - Phone (NavigationStack) / regular (NavigationSplitView)

    @ViewBuilder
    private func phoneBrowser(colors: DayruleColors) -> some View {
        VStack(spacing: 0) {
            NavigationStack(path: $phonePath) {
                phoneTabRoot(colors: colors)
                    .toolbar {
                        if phoneTab == .browse {
                            sidebarToolbar(colors: colors)
                        } else {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Lock") { model.lock() }
                                    .foregroundStyle(colors.accent)
                            }
                            ToolbarItem(placement: .automatic) {
                                Button("Settings") { model.showSettings = true }
                                    .foregroundStyle(colors.accent)
                            }
                        }
                    }
                    .navigationDestination(for: PhoneRoute.self) { route in
                        switch route {
                        case .list(let name):
                            listDetail(list: name, colors: colors)
                        case .project(let projectId):
                            ProjectDetailView(model: model, projectId: projectId)
                        }
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            phoneTabBar(colors: colors)
        }
        .background(colors.bg)
    }

    @ViewBuilder
    private func phoneTabRoot(colors: DayruleColors) -> some View {
        switch phoneTab {
        case .browse:
            sidebarList(colors: colors, phoneLinks: true)
                .navigationTitle("Browse")
        case .inbox:
            listDetail(list: .inbox, colors: colors)
        case .today:
            listDetail(list: .today, colors: colors)
        case .scheduled:
            listDetail(list: .scheduled, colors: colors)
        }
    }

    private func phoneTabBar(colors: DayruleColors) -> some View {
        HStack(spacing: 0) {
            ForEach(PhoneTab.allCases, id: \.self) { tab in
                Button {
                    phoneTab = tab
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 18, weight: phoneTab == tab ? .semibold : .regular))
                        Text(tab.title)
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .foregroundStyle(phoneTab == tab ? colors.accent : colors.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("phone.tab.\(String(describing: tab))")
                .accessibilityAddTraits(phoneTab == tab ? .isSelected : [])
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 2)
        .background(colors.sidebar)
        .overlay(alignment: .top) {
            colors.hairline.frame(height: 1)
        }
    }

    /// After unlock: Today if it has work, otherwise Inbox.
    private func applyDefaultDestinationIfNeeded() {
        guard !didApplyDefaultList else { return }
        guard !model.vaultLoading else { return }
        let preferToday = !Lists.today(model.entities, ctx).isEmpty
        let name: ListName = preferToday ? .today : .inbox
        selection = name
        if isCompact {
            phoneTab = preferToday ? .today : .inbox
            phonePath = []
        }
        didApplyDefaultList = true
    }

    @ViewBuilder
    private func splitBrowser(colors: DayruleColors) -> some View {
        NavigationSplitView {
            sidebarList(colors: colors, phoneLinks: false)
                .navigationTitle("Dayrule")
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
                .toolbar { sidebarToolbar(colors: colors) }
        } detail: {
            NavigationStack(path: $projectPath) {
                listDetail(list: activeList, colors: colors)
                    .navigationDestination(for: ID.self) { projectId in
                        ProjectDetailView(model: model, projectId: projectId)
                    }
            }
        }
    }

    @ToolbarContentBuilder
    private func sidebarToolbar(colors: DayruleColors) -> some ToolbarContent {
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

    @ViewBuilder
    private func sidebarList(colors: DayruleColors, phoneLinks: Bool) -> some View {
        if phoneLinks {
            List {
                sidebarRows(colors: colors, phoneLinks: true)
            }
        } else {
            List(selection: $selection) {
                sidebarRows(colors: colors, phoneLinks: false)
            }
        }
    }

    @ViewBuilder
    private func sidebarRows(colors: DayruleColors, phoneLinks: Bool) -> some View {
        if model.syncStatus == .needsUpdate {
            Text(model.syncStatus.label)
                .font(.footnote)
                .foregroundStyle(Tokens.Light.deadline)
                .listRowBackground(colors.sidebar)
        }
        // Phone Browse: park/archive lists only (Inbox/Today/Scheduled are tabs).
        let names: [ListName] = phoneLinks
            ? PhoneTab.browseLists
            : ListName.allCases.filter { $0 != .notNow }
        ForEach(names, id: \.self) { name in
            let label = HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(!phoneLinks && selection == name ? colors.accent : .clear)
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

            if phoneLinks {
                NavigationLink(value: PhoneRoute.list(name)) { label }
                    .listRowBackground(colors.sidebar)
            } else {
                label
                    .tag(Optional(name))
                    .listRowBackground(colors.sidebar)
            }
        }
    }

    @ViewBuilder
    private func listDetail(list: ListName, colors: DayruleColors) -> some View {
        List {
            if list == .backlog {
                backlogSections(colors: colors)
            } else if rows(for: list).isEmpty {
                // Never replace existing rows with a sync banner — that races Add in e2e
                // and hides todos for the whole push/pull.
                if model.syncStatus == .syncing || model.vaultLoading {
                    Text(model.syncStatus == .syncing ? "Syncing…" : "Pulling vault…")
                        .foregroundStyle(colors.textSecondary)
                } else if let errorMessage = model.errorMessage, model.vault == nil {
                    Text(errorMessage)
                        .foregroundStyle(Tokens.Light.deadline)
                } else {
                    RuledRow {
                        Text(emptyCopy(for: list))
                            .foregroundStyle(colors.textSecondary)
                    }
                }
            } else {
                ForEach(rows(for: list), id: \.id) { row in
                    listRow(row, list: list, colors: colors)
                }
            }
            if list == .inbox || list == .today || list == .backlog || list == .scheduled {
                RuledRow {
                    HStack {
                        TextField("Add", text: $draftTitle)
                            .accessibilityIdentifier("list.addField")
                            .onSubmit { addTodo(to: list) }
                        Button("Add") { addTodo(to: list) }
                            .accessibilityIdentifier("list.addButton")
                            .foregroundStyle(colors.accent)
                            .disabled(draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .buttonStyle(.borderless)
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(list.title)
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
                if list == .trash {
                    Button("Empty Trash", role: .destructive) { emptyTrash() }
                        .accessibilityIdentifier("list.emptyTrash")
                        .disabled(rows(for: .trash).isEmpty)
                }
                if list == .done, model.entities.settings.moveToDone == .manually {
                    Button("Log Completed") { logCompleted() }
                        .accessibilityIdentifier("list.logCompleted")
                }
            }
        }
    }

    @ViewBuilder
    private func backlogSections(colors: DayruleColors) -> some View {
        let main = rows(for: .backlog)
        let parked = rows(for: .notNow)
        if main.isEmpty, parked.isEmpty {
            if model.syncStatus == .syncing || model.vaultLoading {
                Text(model.syncStatus == .syncing ? "Syncing…" : "Pulling vault…")
                    .foregroundStyle(colors.textSecondary)
            } else {
                RuledRow {
                    Text(emptyCopy(for: .backlog))
                        .foregroundStyle(colors.textSecondary)
                }
            }
        } else {
            ForEach(main, id: \.id) { row in
                listRow(row, list: .backlog, colors: colors)
            }
            if !parked.isEmpty {
                Section {
                    ForEach(parked, id: \.id) { row in
                        listRow(row, list: .notNow, colors: colors)
                    }
                } header: {
                    Text("Not now")
                        .foregroundStyle(colors.textSecondary)
                }
            }
        }
    }

    @ViewBuilder
    private func listRow(_ row: Row, list: ListName, colors: DayruleColors) -> some View {
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
            guard list != .trash else { return }
            if !row.isTodo, model.entities.projects[row.id] != nil {
                openProject(row.id)
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
            if list == .trash {
                Button("Restore") { restore(row.id) }
            } else {
                if !row.isTodo, model.entities.projects[row.id] != nil {
                    Button("Open") { openProject(row.id) }
                }
                if row.isTodo, let pid = model.entities.todos[row.id]?.projectId {
                    Button("Open Project") { openProject(pid) }
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

    private func openProject(_ id: ID) {
        if isCompact {
            phonePath.append(.project(id))
        } else {
            projectPath = [id]
        }
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

    private func addTodo(to list: ListName) {
        let title = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        // Use the list on screen, not `selection` — on phone those can diverge.
        do {
            _ = try model.store.run("Add") { d, env in
                switch list {
                case .today:
                    return try Commands.createTodo(d, env, .init(title: title, placement: .today))
                case .backlog:
                    return try Commands.createTodo(d, env, .init(title: title, placement: .ready))
                case .scheduled:
                    let todo = try Commands.createTodo(d, env, .init(title: title, placement: .ready))
                    let tomorrow = When.addLocalDays(env.today, 1)
                    try Commands.setWhen(d, env, ids: [todo.id], when: .date(tomorrow))
                    return todo
                default:
                    return try Commands.createTodo(d, env, .init(title: title, placement: .inbox))
                }
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
            if isCompact { navigatePhone(to: name) }
        case .todo(let id, let home):
            selection = home
            projectPath = []
            if isCompact { navigatePhone(to: home) }
            editTarget = EditTarget(id: id)
        case .project(let id):
            selection = .backlog
            projectPath = isCompact ? [] : [id]
            if isCompact {
                phoneTab = .browse
                phonePath = [.list(.backlog), .project(id)]
            }
        case .area:
            selection = .backlog
            projectPath = []
            if isCompact {
                phoneTab = .browse
                phonePath = [.list(.backlog)]
            }
        }
    }

    private func navigatePhone(to name: ListName) {
        if let tab = PhoneTab.tab(for: name) {
            phoneTab = tab
            phonePath = []
        } else {
            phoneTab = .browse
            // Not now lives inside Backlog on phone.
            let dest: ListName = name == .notNow ? .backlog : name
            phonePath = [.list(dest)]
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

