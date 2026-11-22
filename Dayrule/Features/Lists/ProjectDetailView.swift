import SwiftUI

/// Project page with headings and nested to-dos (web `ProjectPage`, M5).
struct ProjectDetailView: View {
    @Bindable var model: AppModel
    let projectId: ID
    /// Opens a newly converted project (list shell owns navigation).
    var onOpenProject: ((ID) -> Void)? = nil
    /// Owned by the list shell so Mac wake remount does not clear Add drafts.
    @Bindable var orgDrafts: OrgDetailDrafts
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @State private var editTarget: EditTarget?
    @State private var headingTarget: EditTarget?
    @State private var whenTarget: WhenTarget?
    @State private var deadlineTarget: WhenTarget?
    @State private var tagTarget: WhenTarget?
    @State private var moveTarget: WhenTarget?
    @State private var moveProjectPresented = false
    @State private var repeatTarget: EditTarget?
    @State private var reminderTarget: EditTarget?
    @FocusState private var titleFocused: Bool
    @State private var detailWidth: CGFloat = 0

    private struct EditTarget: Identifiable {
        var id: ID
    }

    private struct WhenTarget: Identifiable {
        var id: String { ids.joined(separator: ",") }
        var ids: [ID]
    }

    private var isCompact: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    private var readingMargin: CGFloat {
        Tokens.readingMargin(width: detailWidth, compact: isCompact)
    }

    var body: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme)
        let ctx = ctx
        let view = Lists.projectView(model.entities, projectId, ctx)
        let title = displayTitle(view?.project.title)
        List {
            if let view {
                if !view.project.notes.isEmpty {
                    RuledRow(style: .note) {
                        Text(view.project.notes)
                            .font(.subheadline)
                            .foregroundStyle(colors.textSecondary)
                    }
                }
                let progress = Lists.projectProgress(model.entities, projectId)
                if progress.total > 0 {
                    RuledRow(style: .note) {
                        HStack(spacing: Tokens.Space.m) {
                            ProgressView(value: Double(progress.done), total: Double(progress.total))
                                .tint(colors.accent)
                            Text("\(progress.done) of \(progress.total)")
                                .font(DayruleType.meta)
                                .monospacedDigit()
                                .foregroundStyle(colors.textSecondary)
                                .contentTransition(.numericText(value: Double(progress.done)))
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(progress.done) of \(progress.total) to-dos done")
                        .accessibilityIdentifier("project.progress")
                    }
                }

                let loosePeers = view.todos.map(\.id)
                ForEach(view.todos, id: \.id) { todo in
                    reorderableTodoRow(todo, ctx: ctx, colors: colors, peers: loosePeers)
                }
                .onMove { source, destination in
                    moveTodos(peers: loosePeers, source: source, destination: destination)
                }

                ForEach(view.headings, id: \.heading.id) { group in
                    let peers = group.todos.map(\.id)
                    Section {
                        ForEach(group.todos, id: \.id) { todo in
                            reorderableTodoRow(todo, ctx: ctx, colors: colors, peers: peers)
                        }
                        .onMove { source, destination in
                            moveTodos(peers: peers, source: source, destination: destination)
                        }
                        addRow(
                            headingId: group.heading.id,
                            draft: orgDrafts.headingTitleBinding(
                                projectId: projectId,
                                headingId: group.heading.id
                            )
                        )
                    } header: {
                        Button {
                            headingTarget = EditTarget(id: group.heading.id)
                        } label: {
                            DayruleSectionHeader(title: group.heading.title, tone: .accent, style: .serif)
                        }
                        .buttonStyle(.dayruleRow)
                        .listRowInsets(EdgeInsets())
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityHint("Rename, convert, archive or delete heading")
                        .accessibilityIdentifier("project.heading.\(group.heading.id)")
                        .contextMenu {
                            Button {
                                convertHeadingToProject(group.heading.id, title: group.heading.title)
                            } label: {
                                Label("Convert to Project", systemImage: "bookmark")
                            }
                        }
                    }
                }
            } else {
                // Shown only until the pop below lands (project trashed or deleted elsewhere).
                DayruleEmptyState(systemImage: "bookmark", accessibilityLabel: "Project not found")
            }
        }
        .listStyle(.plain)
        .dayrulePaperList()
        .scrollContentBackground(.hidden)
        .background(colors.bg)
        .navigationTitle(title)
        .dayruleListNavChrome(colors: colors)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            detailWidth = width
        }
        #if !os(macOS)
        .contentMargins(.horizontal, readingMargin, for: .scrollContent)
        #endif
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if view != nil {
                PinnedPaperAddBar(
                    title: orgDrafts.projectTitleBinding(for: projectId),
                    colors: colors,
                    fieldIdentifier: "project.addField",
                    buttonIdentifier: "project.addButton"
                ) {
                    addTodo(
                        headingId: nil,
                        draft: orgDrafts.projectTitleBinding(for: projectId)
                    )
                }
            }
        }
        .dayruleEditablePageTitle(
            text: projectTitleBinding,
            prompt: "New Project",
            accessibilityLabel: "Project title",
            identifier: "project.title",
            focused: $titleFocused
        )
        .environment(\.dayruleReadingMargin, readingMargin)
        .onAppear {
            if (view?.project.title ?? "").isEmpty {
                titleFocused = true
            }
        }
        .onChange(of: view == nil, initial: true) { _, missing in
            if missing {
                dismiss()
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { addHeading() } label: {
                        Label("Add Heading", systemImage: "text.badge.plus")
                    }
                    .accessibilityIdentifier("project.addHeading")
                    Button { editTarget = EditTarget(id: projectId) } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .accessibilityIdentifier("project.edit")
                    Button {
                        toggleProjectComplete(title: title)
                    } label: {
                        if view?.project.status == .open {
                            Label("Complete Project", systemImage: "checkmark.circle")
                        } else {
                            Label("Reopen Project", systemImage: "arrow.uturn.backward.circle")
                        }
                    }
                    .accessibilityIdentifier("project.toggleComplete")
                    Button {
                        convertToTodo(title: title)
                    } label: {
                        Label("Convert to To-Do", systemImage: "checklist")
                    }
                    .accessibilityIdentifier("project.convertToTodo")
                    Button {
                        moveProjectPresented = true
                    } label: {
                        Label("Move…", systemImage: "arrow.right.square")
                    }
                    .accessibilityIdentifier("project.move")
                    Divider()
                    Button { model.undoLast() } label: {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                    }
                    .disabled(!model.store.canUndo)
                    Button {
                        _ = model.store.redo()
                        model.noteEntitiesChanged()
                    } label: {
                        Label("Redo", systemImage: "arrow.uturn.forward")
                    }
                    .disabled(!model.store.canRedo)
                    Divider()
                    Button(role: .destructive) {
                        trashProject(title: title)
                    } label: {
                        Label("Move to Trash", systemImage: "trash")
                    }
                    .accessibilityIdentifier("project.trash")
                } label: {
                    DayruleToolbarGlyph(systemImage: "ellipsis")
                }
                .buttonStyle(.plain)
                .help("Project actions")
                .accessibilityLabel("Project actions")
                .accessibilityIdentifier("project.actions")
            }
            .dayruleHideToolbarGlass()
        }
        .sheet(item: sheetEditTarget) { target in
            ItemEditorSheet(model: model, id: target.id)
        }
        #if os(iOS)
        .fullScreenCover(item: coverEditTarget) { target in
            ItemEditorSheet(model: model, id: target.id)
        }
        #endif
        .sheet(item: $headingTarget) { target in
            HeadingSheetView(model: model, headingId: target.id) { id in
                onOpenProject?(id)
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
        .sheet(item: $moveTarget) { target in
            MoveSheetView(model: model, ids: target.ids)
        }
        .sheet(isPresented: $moveProjectPresented) {
            MoveProjectSheetView(model: model, projectId: projectId)
        }
        .sheet(item: $repeatTarget) { target in
            RepeatSheetView(model: model, todoId: target.id)
        }
        .sheet(item: $reminderTarget) { target in
            ReminderSheetView(model: model, todoId: target.id)
        }
    }

    private var ctx: Lists.Context {
        Lists.Context(today: When.toLocalDate(Date()), keepVisible: model.linger.keepVisible)
    }

    private func displayTitle(_ title: String?) -> String {
        let value = title ?? ""
        return value.isEmpty ? "New Project" : value
    }

    private var projectTitleBinding: Binding<String> {
        Binding(
            get: { model.entities.projects[projectId]?.title ?? "" },
            set: { newValue in
                model.store.run("Rename") { d, env in
                    Commands.updateProject(d, env, id: projectId, title: newValue, notes: nil)
                }
                model.noteEntitiesChanged()
            }
        )
    }

    // MARK: - Editor presentation (PLAN §6.5: full screen on iPhone, sheet elsewhere)

    private var editorIsFullScreen: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    private var sheetEditTarget: Binding<EditTarget?> {
        Binding(
            get: { editorIsFullScreen ? nil : editTarget },
            set: { editTarget = $0 }
        )
    }

    private var coverEditTarget: Binding<EditTarget?> {
        Binding(
            get: { editorIsFullScreen ? editTarget : nil },
            set: { editTarget = $0 }
        )
    }

    // MARK: - Rows

    @ViewBuilder
    private func reorderableTodoRow(
        _ todo: Todo,
        ctx: Lists.Context,
        colors: DayruleColors,
        peers: [ID]
    ) -> some View {
        todoRow(todo, ctx: ctx, colors: colors)
            .draggable(todo.id) {
                Text(todo.title.isEmpty ? "Untitled" : todo.title)
                    .font(DayruleType.rowTitle(dense: true))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(colors.bg)
                    .overlay(Rectangle().strokeBorder(colors.hairline, lineWidth: 1))
            }
            .dropDestination(for: String.self) { items, _ in
                guard let from = items.first else { return false }
                return dropTodo(dragging: from, onto: todo.id, peers: peers)
            }
    }

    @ViewBuilder
    private func todoRow(_ todo: Todo, ctx: Lists.Context, colors: DayruleColors) -> some View {
        let title = todo.title.isEmpty ? "Untitled" : todo.title
        DayruleTodoRow(
            model: rowModel(todo, title: title, ctx: ctx),
            identifier: "project.todo.\(todo.id)",
            onToggle: { toggleComplete(todo.id, title: title) },
            onOpen: { editTarget = EditTarget(id: todo.id) },
            accessibilityActions: [
                RowAction(name: "When…") { whenTarget = WhenTarget(ids: [todo.id]) },
                RowAction(name: "Deadline…") { deadlineTarget = WhenTarget(ids: [todo.id]) },
                RowAction(name: "Tags…") { tagTarget = WhenTarget(ids: [todo.id]) },
                RowAction(name: "Move…") { moveTarget = WhenTarget(ids: [todo.id]) },
                RowAction(name: "Repeat…") { repeatTarget = EditTarget(id: todo.id) },
                RowAction(name: "Reminder…") { reminderTarget = EditTarget(id: todo.id) },
                RowAction(name: "Move up") { moveTodo(todo.id, dir: -1, peers: peersForTodo(todo.id)) },
                RowAction(name: "Move down") { moveTodo(todo.id, dir: 1, peers: peersForTodo(todo.id)) },
                RowAction(name: "Trash") { trash(todo.id, title: title) },
            ]
        )
        .equatable()
        .opacity(model.linger.fading.contains(todo.id) ? 0 : 1)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                whenTarget = WhenTarget(ids: [todo.id])
            } label: {
                Label("When…", systemImage: "calendar")
            }
            .tint(colors.accent)
        }
        .contextMenu {
            Section {
                Button { editTarget = EditTarget(id: todo.id) } label: {
                    Label("Edit", systemImage: "pencil")
                }
            }
            Section {
                Button { whenTarget = WhenTarget(ids: [todo.id]) } label: {
                    Label("When…", systemImage: "calendar")
                }
                Button { deadlineTarget = WhenTarget(ids: [todo.id]) } label: {
                    Label("Deadline…", systemImage: "flag")
                }
                Button { tagTarget = WhenTarget(ids: [todo.id]) } label: {
                    Label("Tags…", systemImage: "tag")
                }
                Button { moveTarget = WhenTarget(ids: [todo.id]) } label: {
                    Label("Move…", systemImage: "arrow.right.square")
                }
                Button { repeatTarget = EditTarget(id: todo.id) } label: {
                    Label("Repeat…", systemImage: "repeat")
                }
                Button { reminderTarget = EditTarget(id: todo.id) } label: {
                    Label("Reminder…", systemImage: "bell")
                }
            }
            Section {
                if todo.status == .open {
                    Button { toggleComplete(todo.id, title: title) } label: {
                        Label("Complete", systemImage: "checkmark.circle")
                    }
                    Button { cancel(todo.id, title: title) } label: {
                        Label("Cancel", systemImage: "xmark.circle")
                    }
                } else {
                    Button { toggleComplete(todo.id, title: title) } label: {
                        Label("Reopen", systemImage: "arrow.uturn.backward.circle")
                    }
                }
                Button { convertTodoToProject(todo.id, title: title) } label: {
                    Label("Convert to Project", systemImage: "bookmark")
                }
            }
            Button(role: .destructive) { trash(todo.id, title: title) } label: {
                Label("Trash", systemImage: "trash")
            }
        }
    }

    private func convertTodoToProject(_ id: ID, title: String) {
        do {
            let project = try model.store.run("Convert to Project") { d, env in
                try Commands.convertTodoToProject(d, env, todoId: id)
            }
            model.noteEntitiesChanged()
            model.undoNotice("Converted \(title) to a project")
            onOpenProject?(project.id)
        } catch {
            model.notices.post(Notice(kind: .error, message: error.localizedDescription))
        }
    }

    private func rowModel(_ todo: Todo, title: String, ctx: Lists.Context) -> TodoRowModel {
        let checklist = model.entities.checklistItems.values.filter { $0.todoId == todo.id }
        return TodoRowModel(
            id: todo.id,
            title: title,
            status: todo.status,
            subtitle: todo.deadline.map { DayruleDateFormat.due($0, today: ctx.today) },
            subtitleIsOverdue: Lists.isOverdue(.todo(todo), ctx),
            hasReminder: todo.reminderAt != nil,
            repeats: todo.repeat != nil || todo.repeatTemplateId != nil,
            hasNotes: !todo.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            checklist: checklist.isEmpty
                ? nil
                : (done: checklist.filter(\.done).count, total: checklist.count)
        )
    }

    @ViewBuilder
    private func addRow(headingId: ID?, draft: Binding<String>) -> some View {
        PaperAddRow(
            title: draft,
            canAdd: !draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            fieldIdentifier: headingId.map { "project.addField.\($0)" } ?? "project.addField",
            buttonIdentifier: headingId.map { "project.addButton.\($0)" } ?? "project.addButton"
        ) {
            addTodo(headingId: headingId, draft: draft)
        }
    }

    // MARK: - Reorder

    private func peersForTodo(_ id: ID) -> [ID] {
        guard let view = Lists.projectView(model.entities, projectId, ctx) else { return [] }
        if view.todos.contains(where: { $0.id == id }) {
            return view.todos.map(\.id)
        }
        for group in view.headings where group.todos.contains(where: { $0.id == id }) {
            return group.todos.map(\.id)
        }
        return []
    }

    private func moveTodo(_ id: ID, dir: Int, peers: [ID]) {
        guard let i = peers.firstIndex(of: id) else { return }
        let destination = i + dir + (dir > 0 ? 1 : 0)
        guard destination >= 0, destination <= peers.count,
              let neighbours = ListReorder.neighbours(
                  peers: peers,
                  source: IndexSet(integer: i),
                  destination: destination
              )
        else { return }
        applyTodoReorder(id: neighbours.id, before: neighbours.before, after: neighbours.after)
    }

    private func moveTodos(peers: [ID], source: IndexSet, destination: Int) {
        guard let neighbours = ListReorder.neighbours(
            peers: peers,
            source: source,
            destination: destination
        ) else { return }
        applyTodoReorder(id: neighbours.id, before: neighbours.before, after: neighbours.after)
    }

    @discardableResult
    private func dropTodo(dragging: ID, onto: ID, peers: [ID]) -> Bool {
        guard let neighbours = ListReorder.neighbours(peers: peers, dragging: dragging, onto: onto)
        else { return false }
        applyTodoReorder(id: dragging, before: neighbours.before, after: neighbours.after)
        return true
    }

    private func applyTodoReorder(id: ID, before: ID?, after: ID?) {
        do {
            try model.store.run("Reorder") { d, env in
                try Commands.reorder(
                    d,
                    env,
                    collection: .todos,
                    id: id,
                    field: .order,
                    before: before,
                    after: after
                )
            }
            model.noteEntitiesChanged()
        } catch {
            model.notices.post(Notice(kind: .error, message: error.localizedDescription))
        }
    }

    // MARK: - Actions

    private func addTodo(headingId: ID?, draft: Binding<String>) {
        let title = draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        do {
            _ = try model.store.run("Add") { d, env in
                try Commands.createTodo(
                    d, env,
                    .init(title: title, placement: .project(projectId: projectId, headingId: headingId))
                )
            }
            draft.wrappedValue = ""
            model.noteEntitiesChanged()
            model.bumpHaptic(\.add)
        } catch {
            model.notices.post(Notice(kind: .error, message: error.localizedDescription))
        }
    }

    private func addHeading() {
        do {
            let heading = try model.store.run("New Heading") { d, env in
                try Commands.createHeading(d, env, projectId: projectId, title: "New Heading")
            }
            model.noteEntitiesChanged()
            // Straight into rename, so "New Heading" never lingers as a placeholder.
            headingTarget = EditTarget(id: heading.id)
        } catch {
            model.notices.post(Notice(kind: .error, message: error.localizedDescription))
        }
    }

    private func toggleComplete(_ id: ID, title: String) {
        let open = model.entities.todos[id]?.status == .open
        let status: Status = open ? .completed : .open
        model.store.run(status == .completed ? "Complete" : "Reopen") { d, env in
            Commands.setStatus(d, env, ids: [id], status: status)
        }
        if status == .completed {
            // Keep the row for the pop and tick; the notice also announces it (PLAN §6.7).
            model.linger.hold(id)
            model.noteEntitiesChanged()
            model.undoNotice("Completed \(title)")
        } else {
            model.linger.release(id)
            model.noteEntitiesChanged()
        }
    }

    private func cancel(_ id: ID, title: String) {
        model.store.run("Cancel") { d, env in
            Commands.setStatus(d, env, ids: [id], status: .canceled)
        }
        model.linger.hold(id)
        model.noteEntitiesChanged()
        model.undoNotice("Canceled \(title)")
    }

    private func trash(_ id: ID, title: String) {
        model.store.run("Trash") { d, env in
            Commands.trashItems(d, env, ids: [id])
        }
        model.noteEntitiesChanged()
        model.bumpHaptic(\.trash)
        model.undoNotice("Moved \(title) to Trash")
    }

    private func trashProject(title: String) {
        model.store.run("Trash Project") { d, env in
            Commands.trashItems(d, env, ids: [projectId])
        }
        model.noteEntitiesChanged()
        model.bumpHaptic(\.trash)
        model.undoNotice("Moved \(title) to Trash")
        dismiss()
    }

    private func toggleProjectComplete(title: String) {
        let open = model.entities.projects[projectId]?.status == .open
        let status: Status = open ? .completed : .open
        model.store.run(status == .completed ? "Complete Project" : "Reopen Project") { d, env in
            Commands.setStatus(d, env, ids: [projectId], status: status)
        }
        model.noteEntitiesChanged()
        if status == .completed {
            model.undoNotice("Completed \(title)")
        }
    }

    private func convertToTodo(title: String) {
        do {
            _ = try model.store.run("Convert to To-Do") { d, env in
                try Commands.convertProjectToTodo(d, env, projectId: projectId)
            }
            model.noteEntitiesChanged()
            model.undoNotice("Converted \(title) to a to-do")
        } catch {
            model.notices.post(Notice(kind: .error, message: error.localizedDescription))
        }
    }

    private func convertHeadingToProject(_ id: ID, title: String) {
        do {
            let project = try model.store.run("Convert Heading to Project") { d, env in
                try Commands.convertHeadingToProject(d, env, headingId: id)
            }
            model.noteEntitiesChanged()
            model.undoNotice("Converted \(title) to a project")
            onOpenProject?(project.id)
        } catch {
            model.notices.post(Notice(kind: .error, message: error.localizedDescription))
        }
    }
}
