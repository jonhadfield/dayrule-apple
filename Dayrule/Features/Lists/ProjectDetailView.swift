import SwiftUI

/// Project page with headings and nested to-dos (web `ProjectPage`, M5).
struct ProjectDetailView: View {
    @Bindable var model: AppModel
    let projectId: ID
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @State private var draftTitle = ""
    @State private var headingDrafts: [ID: String] = [:]
    @State private var editTarget: EditTarget?
    @State private var headingTarget: EditTarget?
    @State private var whenTarget: WhenTarget?
    @State private var deadlineTarget: WhenTarget?
    @State private var tagTarget: WhenTarget?
    @State private var moveTarget: WhenTarget?
    @State private var repeatTarget: EditTarget?
    @State private var reminderTarget: EditTarget?

    private struct EditTarget: Identifiable {
        var id: ID
    }

    private struct WhenTarget: Identifiable {
        var id: String { ids.joined(separator: ",") }
        var ids: [ID]
    }

    var body: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme)
        let ctx = ctx
        let view = Lists.projectView(model.entities, projectId, ctx)
        let title = view?.project.title ?? "Project"
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

                ForEach(view.todos, id: \.id) { todo in
                    todoRow(todo, ctx: ctx, colors: colors)
                }
                addRow(headingId: nil, draft: $draftTitle)

                ForEach(view.headings, id: \.heading.id) { group in
                    Section {
                        ForEach(group.todos, id: \.id) { todo in
                            todoRow(todo, ctx: ctx, colors: colors)
                        }
                        addRow(
                            headingId: group.heading.id,
                            draft: Binding(
                                get: { headingDrafts[group.heading.id] ?? "" },
                                set: { headingDrafts[group.heading.id] = $0 }
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
                        .accessibilityHint("Rename, archive or delete heading")
                        .accessibilityIdentifier("project.heading.\(group.heading.id)")
                    }
                }
            } else {
                // Shown only until the pop below lands (project trashed or deleted elsewhere).
                DayruleEmptyState(systemImage: "bookmark", accessibilityLabel: "Project not found")
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(colors.bg)
        .navigationTitle(title)
        .dayruleListNavChrome(colors: colors)
        .dayrulePageTitle(title)
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
                } label: {
                    Label("Project actions", systemImage: "ellipsis")
                        .labelStyle(.iconOnly)
                }
                .help("Project actions")
                .accessibilityIdentifier("project.actions")
            }
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
            HeadingSheetView(model: model, headingId: target.id)
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
                RowAction(name: "Trash") { trash(todo.id, title: title) },
            ]
        )
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
            }
            Button(role: .destructive) { trash(todo.id, title: title) } label: {
                Label("Trash", systemImage: "trash")
            }
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
        model.undoNotice("Moved \(title) to Trash")
    }
}
