import SwiftUI

/// Area page: nested projects and loose to-dos (web `AreaPage`, M5).
struct AreaDetailView: View {
    @Bindable var model: AppModel
    let areaId: ID
    var onOpenProject: (ID) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @State private var draftTitle = ""
    @State private var editTarget: EditTarget?
    @State private var whenTarget: WhenTarget?
    @State private var deadlineTarget: WhenTarget?
    @State private var tagTarget: WhenTarget?
    @State private var moveTarget: WhenTarget?
    @State private var repeatTarget: EditTarget?
    @State private var reminderTarget: EditTarget?
    @FocusState private var titleFocused: Bool

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
        let view = Lists.areaView(model.entities, areaId, ctx)
        let title = displayTitle(view?.area.title)
        List {
            if let view {
                ForEach(view.projects, id: \.id) { project in
                    Button {
                        onOpenProject(project.id)
                    } label: {
                        HStack(spacing: Tokens.rowGlyphSpacing) {
                            Image(systemName: "bookmark")
                                .foregroundStyle(colors.textSecondary)
                                .frame(width: Tokens.rowLeadingSlot)
                                .accessibilityHidden(true)
                            Text(project.title.isEmpty ? "New Project" : project.title)
                                .font(DayruleType.sectionSerif)
                                .foregroundStyle(colors.text)
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("area.project.\(project.id)")
                    .listRowInsets(
                        EdgeInsets(top: 0, leading: Tokens.rowInset, bottom: 0, trailing: Tokens.rowInset)
                    )
                    .listRowSeparatorTint(colors.hairline)
                    .listRowBackground(colors.bg)
                    .frame(minHeight: Tokens.rowHeight)
                }

                if !view.todos.isEmpty, !view.projects.isEmpty {
                    Section {
                        ForEach(view.todos, id: \.id) { todo in
                            todoRow(todo, ctx: ctx, colors: colors)
                        }
                        addRow(draft: $draftTitle)
                    } header: {
                        DayruleSectionHeader(title: "To-Dos", tone: .muted, style: .caps)
                    }
                } else {
                    ForEach(view.todos, id: \.id) { todo in
                        todoRow(todo, ctx: ctx, colors: colors)
                    }
                    addRow(draft: $draftTitle)
                }
            } else {
                DayruleEmptyState(systemImage: "shippingbox", accessibilityLabel: "Area not found")
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(colors.bg)
        .navigationTitle(title)
        .dayruleListNavChrome(colors: colors)
        .dayruleEditablePageTitle(
            text: areaTitleBinding,
            prompt: "New Area",
            accessibilityLabel: "Area title",
            identifier: "area.title",
            focused: $titleFocused
        )
        .onAppear {
            if (view?.area.title ?? "").isEmpty {
                titleFocused = true
            }
        }
        .onChange(of: view == nil, initial: true) { _, missing in
            if missing {
                dismiss()
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    addProject()
                } label: {
                    Label("New Project", systemImage: "bookmark")
                }
                .help("New Project")
                .accessibilityIdentifier("area.newProject")
                Button(role: .destructive) {
                    trashArea(title: title)
                } label: {
                    Label("Trash", systemImage: "trash")
                }
                .help("Move area to Trash")
                .accessibilityIdentifier("area.trash")
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

    private func displayTitle(_ title: String?) -> String {
        let value = title ?? ""
        return value.isEmpty ? "New Area" : value
    }

    private var areaTitleBinding: Binding<String> {
        Binding(
            get: { model.entities.areas[areaId]?.title ?? "" },
            set: { newValue in
                model.store.run("Rename Area") { d, env in
                    Commands.renameArea(d, env, id: areaId, title: newValue)
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
    private func todoRow(_ todo: Todo, ctx: Lists.Context, colors: DayruleColors) -> some View {
        let title = todo.title.isEmpty ? "Untitled" : todo.title
        DayruleTodoRow(
            model: rowModel(todo, title: title, ctx: ctx),
            identifier: "area.todo.\(todo.id)",
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
    private func addRow(draft: Binding<String>) -> some View {
        PaperAddRow(
            title: draft,
            canAdd: !draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            fieldIdentifier: "area.addField",
            buttonIdentifier: "area.addButton"
        ) {
            addTodo(draft: draft)
        }
    }

    // MARK: - Actions

    private func addTodo(draft: Binding<String>) {
        let title = draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        do {
            _ = try model.store.run("Add") { d, env in
                try Commands.createTodo(d, env, .init(title: title, placement: .area(areaId: areaId)))
            }
            draft.wrappedValue = ""
            model.noteEntitiesChanged()
        } catch {
            model.notices.post(Notice(kind: .error, message: error.localizedDescription))
        }
    }

    private func addProject() {
        do {
            let project = try model.store.run("New Project") { d, env in
                try Commands.createProject(d, env, title: "", areaId: areaId)
            }
            model.noteEntitiesChanged()
            onOpenProject(project.id)
        } catch {
            model.notices.post(Notice(kind: .error, message: error.localizedDescription))
        }
    }

    private func trashArea(title: String) {
        model.store.run("Trash Area") { d, env in
            Commands.trashItems(d, env, ids: [areaId])
        }
        model.noteEntitiesChanged()
        model.undoNotice("Moved \(title) to Trash")
        dismiss()
    }

    private func toggleComplete(_ id: ID, title: String) {
        let open = model.entities.todos[id]?.status == .open
        let status: Status = open ? .completed : .open
        model.store.run(status == .completed ? "Complete" : "Reopen") { d, env in
            Commands.setStatus(d, env, ids: [id], status: status)
        }
        if status == .completed {
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
