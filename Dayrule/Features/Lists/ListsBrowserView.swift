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
        case .today: "circle.circle"
        case .scheduled: "calendar"
        case .browse: "folder"
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
    /// Per-list Add drafts so switching tabs doesn’t leak half-typed titles.
    @State private var draftTitles: [ListName: String] = [:]
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
                        phoneChromeToolbar(colors: colors)
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
                .dayruleListNavChrome(colors: colors)
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
                .toolbar { phoneChromeToolbar(colors: colors) }
        } detail: {
            NavigationStack(path: $projectPath) {
                listDetail(list: activeList, colors: colors)
                    .navigationDestination(for: ID.self) { projectId in
                        ProjectDetailView(model: model, projectId: projectId)
                    }
            }
        }
    }

    /// Lock · Find · Settings on every phone tab (Refresh lives under Settings → Sync now).
    @ToolbarContentBuilder
    private func phoneChromeToolbar(colors: DayruleColors) -> some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button {
                model.lock()
            } label: {
                Image(systemName: "lock")
            }
            .foregroundStyle(colors.accent)
            .accessibilityLabel("Lock")
        }
        ToolbarItem(placement: .automatic) {
            Button {
                showFind = true
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .foregroundStyle(colors.accent)
            .accessibilityIdentifier("sidebar.find")
            .accessibilityLabel("Find")
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                model.showSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .foregroundStyle(colors.accent)
            .accessibilityLabel("Settings")
        }
    }

    private func draftBinding(for list: ListName) -> Binding<String> {
        Binding(
            get: { draftTitles[list] ?? "" },
            set: { draftTitles[list] = $0 }
        )
    }

    @ViewBuilder
    private func sidebarList(colors: DayruleColors, phoneLinks: Bool) -> some View {
        if phoneLinks {
            List {
                phoneBrowseRows(colors: colors)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(colors.bg)
        } else {
            List(selection: $selection) {
                sidebarRows(colors: colors)
            }
        }
    }

    /// Phone Browse: ALL-CAPS park lists with circular counts + PROJECTS (PLAN §6.5).
    @ViewBuilder
    private func phoneBrowseRows(colors: DayruleColors) -> some View {
        if model.syncStatus == .needsUpdate {
            Text(model.syncStatus.label)
                .font(.footnote)
                .foregroundStyle(Tokens.Light.deadline)
                .listRowBackground(colors.bg)
        }
        ForEach(PhoneTab.browseLists, id: \.self) { name in
            NavigationLink(value: PhoneRoute.list(name)) {
                HStack(spacing: 12) {
                    Image(systemName: browseIcon(for: name))
                        .font(.body)
                        .foregroundStyle(colors.text)
                        .frame(width: 22)
                    Text(name.title.uppercased())
                        .font(.body.weight(.medium))
                        .foregroundStyle(colors.text)
                    Spacer(minLength: 0)
                    if let count = browseCount(for: name) {
                        Text("\(count)")
                            .font(.subheadline)
                            .foregroundStyle(colors.textSecondary)
                            .frame(minWidth: 28, minHeight: 28)
                            .overlay {
                                Circle()
                                    .stroke(colors.hairline, lineWidth: 1)
                            }
                            .accessibilityLabel(sidebarBadgeLabel(name: name, count: count))
                    }
                }
            }
            .accessibilityIdentifier("list.sidebar.\(name.rawValue)")
            .listRowBackground(colors.bg)
            .listRowSeparatorTint(colors.hairline)
        }
        let projects = browseProjects
        if !projects.isEmpty {
            Section {
                ForEach(projects, id: \.id) { project in
                    NavigationLink(value: PhoneRoute.project(project.id)) {
                        HStack(spacing: 12) {
                            Image(systemName: "bookmark")
                                .font(.body)
                                .foregroundStyle(colors.text)
                                .frame(width: 22)
                            Text(project.title.isEmpty ? "Untitled" : project.title)
                                .foregroundStyle(colors.text)
                            Spacer(minLength: 0)
                        }
                    }
                    .accessibilityIdentifier("list.sidebar.project.\(project.id)")
                    .listRowBackground(colors.bg)
                    .listRowSeparatorTint(colors.hairline)
                }
            } header: {
                Text("PROJECTS")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(colors.textSecondary)
                    .textCase(nil)
            }
        }
    }

    @ViewBuilder
    private func sidebarRows(colors: DayruleColors) -> some View {
        if model.syncStatus == .needsUpdate {
            Text(model.syncStatus.label)
                .font(.footnote)
                .foregroundStyle(Tokens.Light.deadline)
                .listRowBackground(colors.sidebar)
        }
        let names = ListName.allCases.filter { $0 != .notNow }
        ForEach(names, id: \.self) { name in
            HStack(spacing: 0) {
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

    private func browseIcon(for name: ListName) -> String {
        switch name {
        case .backlog: "sparkle"
        case .done: "checkmark.circle"
        case .trash: "trash"
        default: "list.bullet"
        }
    }

    private var browseProjects: [Project] {
        model.entities.projects.values
            .filter { !Lists.isTrashed(model.entities, .project($0)) && $0.status == .open }
            .sorted {
                let c = Order.compareKeys($0.order, $1.order)
                if c != 0 { return c < 0 }
                return Order.compareKeys($0.id, $1.id) < 0
            }
    }

    private func browseCount(for name: ListName) -> Int? {
        switch name {
        case .backlog:
            let main = Lists.backlog(model.entities, ctx).reduce(0) { $0 + $1.todos.count }
            let parked = Lists.notNow(model.entities, ctx)
            return main + parked.todos.count + parked.projects.count
        case .done:
            return Lists.doneList(model.entities, ctx).reduce(0) { $0 + $1.items.count }
        case .trash:
            let t = Lists.trash(model.entities)
            return t.areas.count + t.items.count
        default:
            return nil
        }
    }

    @ViewBuilder
    private func listDetail(list: ListName, colors: DayruleColors) -> some View {
        List {
            if list == .backlog {
                backlogSections(colors: colors)
            } else if list == .scheduled {
                scheduledSections(colors: colors)
            } else if rows(for: list).isEmpty {
                // Never replace existing rows with a sync banner — that races Add in e2e
                // and hides todos for the whole push/pull.
                if model.syncStatus == .syncing || model.vaultLoading {
                    Text(model.syncStatus == .syncing ? "Syncing…" : "Pulling vault…")
                        .foregroundStyle(colors.textSecondary)
                } else if model.vault == nil, model.errorMessage != nil {
                    vaultMissingRow(colors: colors)
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
                PaperAddRow(title: draftBinding(for: list), colors: colors) {
                    addTodo(to: list)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(list.title)
        .dayruleListNavChrome(colors: colors)
        .scrollContentBackground(.hidden)
        .background(colors.bg)
        .toolbar {
            // Pushed Browse destinations replace the tab-root toolbar — repeat chrome.
            if isCompact, !phonePath.isEmpty {
                phoneChromeToolbar(colors: colors)
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
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
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(colors.accent)
                }
                .accessibilityIdentifier("list.find")
                .accessibilityLabel("List actions")
            }
        }
    }

    @ViewBuilder
    private func scheduledSections(colors: DayruleColors) -> some View {
        let scheduled = Lists.scheduled(model.entities, ctx)
        let dayGroups = scheduled.days.filter { !$0.items.isEmpty }
        let monthGroups = scheduled.months.filter { !$0.items.isEmpty }
        if dayGroups.isEmpty, monthGroups.isEmpty, scheduled.waiting.isEmpty {
            if model.syncStatus == .syncing || model.vaultLoading {
                Text(model.syncStatus == .syncing ? "Syncing…" : "Pulling vault…")
                    .foregroundStyle(colors.textSecondary)
            } else if model.vault == nil, model.errorMessage != nil {
                vaultMissingRow(colors: colors)
            } else {
                RuledRow {
                    Text(emptyCopy(for: .scheduled))
                        .foregroundStyle(colors.textSecondary)
                }
            }
        } else {
            ForEach(dayGroups, id: \.date) { day in
                Section {
                    ForEach(day.items, id: \.id) { item in
                        listRow(scheduledRow(item), list: .scheduled, colors: colors)
                    }
                } header: {
                    Text(scheduledDayHeader(day.date))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(colors.accent)
                        .textCase(nil)
                }
            }
            ForEach(monthGroups, id: \.month) { month in
                Section {
                    ForEach(month.items, id: \.id) { item in
                        listRow(scheduledRow(item), list: .scheduled, colors: colors)
                    }
                } header: {
                    Text(month.month.uppercased())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(colors.accent)
                        .textCase(nil)
                }
            }
            if !scheduled.waiting.isEmpty {
                Section {
                    ForEach(scheduled.waiting, id: \.id) { item in
                        listRow(scheduledRow(item), list: .scheduled, colors: colors)
                    }
                } header: {
                    Text("WAITING")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(colors.accent)
                        .textCase(nil)
                }
            }
        }
    }

    private func scheduledRow(_ item: ListItem) -> Row {
        if item.isTodo, let t = model.entities.todos[item.id] {
            return todoRow(t, subtitle: nil, trailing: nil, overdue: false)
        }
        return Row(
            id: item.id,
            title: item.title,
            subtitle: nil,
            isTodo: false,
            status: item.status
        )
    }

    @ViewBuilder
    private func vaultMissingRow(colors: DayruleColors) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.errorMessage ?? "Sign in again")
                .foregroundStyle(Tokens.Light.deadline)
            Button("Sign in") {
                model.showSignInGate()
            }
            .foregroundStyle(colors.accent)
            .accessibilityIdentifier("list.signInAgain")
        }
        .padding(.vertical, 8)
    }

    private func scheduledDayHeader(_ date: LocalDate) -> String {
        let tomorrow = When.addLocalDays(ctx.today, 1)
        if date == tomorrow { return "TOMORROW" }
        guard let d = When.fromLocalDate(date) else { return date.uppercased() }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEEE"
        return formatter.string(from: d).uppercased()
    }

    @ViewBuilder
    private func backlogSections(colors: DayruleColors) -> some View {
        let main = rows(for: .backlog)
        let parked = rows(for: .notNow)
        if main.isEmpty, parked.isEmpty {
            if model.syncStatus == .syncing || model.vaultLoading {
                Text(model.syncStatus == .syncing ? "Syncing…" : "Pulling vault…")
                    .foregroundStyle(colors.textSecondary)
            } else if model.vault == nil, model.errorMessage != nil {
                vaultMissingRow(colors: colors)
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
                    // Non-Today lists keep subtitle under the title; Today uses trailing chips.
                    if list != .today, let subtitle = row.subtitle {
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
                if let trailing = row.trailing {
                    HStack(spacing: 4) {
                        Image(systemName: trailing.systemImage)
                            .font(.caption)
                        Text(trailing.label)
                            .font(.caption)
                    }
                    .foregroundStyle(
                        trailing.isOverdue ? Tokens.Light.deadline : colors.accent
                    )
                    .accessibilityLabel(trailing.label)
                }
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
                    trailing: nil,
                    overdue: Lists.isOverdue(.todo($0), ctx)
                )
            }
        case .today:
            return Lists.today(model.entities, ctx).map {
                let trailing = todayTrailing(for: $0)
                let kind = $0.isTodo ? nil : "Project"
                if $0.isTodo, let t = model.entities.todos[$0.id] {
                    return todoRow(
                        t,
                        subtitle: kind,
                        trailing: trailing,
                        overdue: Lists.isOverdue($0, ctx)
                    )
                }
                return Row(
                    id: $0.id,
                    title: $0.title,
                    subtitle: kind,
                    isTodo: false,
                    status: $0.status,
                    deadlineOverdue: Lists.isOverdue($0, ctx),
                    trailing: trailing
                )
            }
        case .scheduled:
            // Prefer `scheduledSections`; this path is unused for phone listDetail.
            return Lists.scheduled(model.entities, ctx).days.flatMap { day in
                day.items.map { scheduledRow($0) }
            }
        case .backlog:
            return Lists.backlog(model.entities, ctx).flatMap { g in
                g.todos.map {
                    todoRow($0, subtitle: containerLabel(g.container), trailing: nil, overdue: false)
                }
            }
        case .notNow:
            let n = Lists.notNow(model.entities, ctx)
            return n.projects.map {
                Row(id: $0.id, title: $0.title, subtitle: "Project", isTodo: false, status: $0.status)
            } + n.todos.map {
                todoRow($0, subtitle: nil, trailing: nil, overdue: false)
            }
        case .done:
            return Lists.doneList(model.entities, ctx).flatMap { day in
                day.items.map {
                    if $0.isTodo, let t = model.entities.todos[$0.id] {
                        return todoRow(t, subtitle: day.date, trailing: nil, overdue: false)
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
                    return todoRow(todo, subtitle: nil, trailing: nil, overdue: false)
                }
                return Row(id: $0.id, title: $0.title, subtitle: nil, isTodo: $0.isTodo, status: $0.status)
            }
        }
    }

    private func todayTrailing(for item: ListItem) -> TrailingChip? {
        if Lists.isOverdue(item, ctx) {
            return TrailingChip(systemImage: "clock", label: overdueLabel(deadline: item.deadline), isOverdue: true)
        }
        if let start = item.startDate, start < ctx.today {
            return TrailingChip(systemImage: "clock", label: overdueLabel(startDate: start), isOverdue: true)
        }
        if item.startDate == ctx.today || item.deadline == ctx.today {
            return TrailingChip(systemImage: "calendar", label: "Today", isOverdue: false)
        }
        if item.deadline != nil {
            return TrailingChip(systemImage: "calendar", label: "Today", isOverdue: false)
        }
        return TrailingChip(systemImage: "calendar", label: "Today", isOverdue: false)
    }

    private func overdueLabel(deadline: LocalDate? = nil, startDate: LocalDate? = nil) -> String {
        let anchor = deadline ?? startDate
        guard let anchor, let past = When.fromLocalDate(anchor) else { return "Overdue" }
        let hours = max(1, Int(Date().timeIntervalSince(past) / 3600))
        if hours < 48 { return "\(hours)h overdue" }
        let days = max(1, hours / 24)
        return "\(days)d overdue"
    }

    private func todoRow(_ todo: Todo, subtitle: String?, trailing: TrailingChip?, overdue: Bool) -> Row {
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
            checklistLabel: checklist.isEmpty ? nil : "\(done) of \(checklist.count)",
            trailing: trailing
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
        let title = (draftTitles[list] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
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
            draftTitles[list] = ""
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

    private struct TrailingChip: Equatable {
        var systemImage: String
        var label: String
        var isOverdue: Bool
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
        var trailing: TrailingChip?
    }
}

