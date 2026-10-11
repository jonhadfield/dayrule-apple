import SwiftUI

/// Project page with headings and nested to-dos (web `ProjectPage`, M5).
struct ProjectDetailView: View {
    @Bindable var model: AppModel
    let projectId: ID
    @Environment(\.colorScheme) private var colorScheme
    @State private var draftTitle = ""
    @State private var headingDrafts: [ID: String] = [:]
    @State private var editTarget: EditTarget?
    @State private var headingTarget: EditTarget?
    @State private var whenTarget: WhenTarget?
    @State private var deadlineTarget: WhenTarget?
    @State private var tagTarget: WhenTarget?
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
        let view = Lists.projectView(model.entities, projectId, ctx)
        List {
            if let view {
                if !view.project.notes.isEmpty {
                    Text(view.project.notes)
                        .font(.subheadline)
                        .foregroundStyle(colors.textSecondary)
                        .listRowBackground(colors.bg)
                }
                let progress = Lists.projectProgress(model.entities, projectId)
                if progress.total > 0 {
                    Text("\(progress.done) of \(progress.total)")
                        .font(.caption)
                        .foregroundStyle(colors.textSecondary)
                        .listRowBackground(colors.bg)
                        .accessibilityIdentifier("project.progress")
                }

                ForEach(view.todos, id: \.id) { todo in
                    todoRow(todo, colors: colors)
                }
                addRow(headingId: nil, colors: colors, draft: $draftTitle)

                ForEach(view.headings, id: \.heading.id) { group in
                    Section {
                        ForEach(group.todos, id: \.id) { todo in
                            todoRow(todo, colors: colors)
                        }
                        addRow(
                            headingId: group.heading.id,
                            colors: colors,
                            draft: Binding(
                                get: { headingDrafts[group.heading.id] ?? "" },
                                set: { headingDrafts[group.heading.id] = $0 }
                            )
                        )
                    } header: {
                        Button {
                            headingTarget = EditTarget(id: group.heading.id)
                        } label: {
                            Text(group.heading.title)
                                .font(DayruleFont.serif(.subheadline))
                                .foregroundStyle(colors.accent)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .accessibilityIdentifier("project.heading.\(group.heading.id)")
                    }
                }
            } else {
                Text("Project not found")
                    .foregroundStyle(colors.textSecondary)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(colors.bg)
        .navigationTitle(view?.project.title ?? "Project")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button("Add Heading") { addHeading() }
                    .foregroundStyle(colors.accent)
                    .accessibilityIdentifier("project.addHeading")
                Button("Edit") { editTarget = EditTarget(id: projectId) }
                    .foregroundStyle(colors.accent)
                    .accessibilityIdentifier("project.edit")
            }
        }
        .sheet(item: $editTarget) { target in
            ItemEditorSheet(model: model, id: target.id)
        }
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
        .sheet(item: $repeatTarget) { target in
            RepeatSheetView(model: model, todoId: target.id)
        }
        .sheet(item: $reminderTarget) { target in
            ReminderSheetView(model: model, todoId: target.id)
        }
    }

    private var ctx: Lists.Context {
        Lists.Context(today: When.toLocalDate(Date()), keepVisible: nil)
    }

    @ViewBuilder
    private func todoRow(_ todo: Todo, colors: DayruleColors) -> some View {
        RuledRow {
            HStack(alignment: .center, spacing: 10) {
                DayruleCheckbox(
                    status: todo.status,
                    label: todo.status == .open ? "Complete" : "Reopen"
                ) {
                    toggleComplete(todo.id)
                }
                Text(todo.title)
                    .foregroundStyle(colors.text)
                    .strikethrough(todo.status != .open)
                    .accessibilityIdentifier("project.todo.\(todo.id)")
                Spacer(minLength: 0)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { editTarget = EditTarget(id: todo.id) }
        .contextMenu {
            Button("Edit") { editTarget = EditTarget(id: todo.id) }
            Button("When…") { whenTarget = WhenTarget(ids: [todo.id]) }
            Button("Deadline…") { deadlineTarget = WhenTarget(ids: [todo.id]) }
            Button("Tags…") { tagTarget = WhenTarget(ids: [todo.id]) }
            Button("Repeat…") { repeatTarget = EditTarget(id: todo.id) }
            Button("Reminder…") { reminderTarget = EditTarget(id: todo.id) }
            if todo.status == .open {
                Button("Complete") { toggleComplete(todo.id) }
            }
            Button("Trash", role: .destructive) { trash(todo.id) }
        }
    }

    @ViewBuilder
    private func addRow(
        headingId: ID?,
        colors: DayruleColors,
        draft: Binding<String>
    ) -> some View {
        RuledRow {
            HStack {
                TextField("Add", text: draft)
                    .accessibilityIdentifier(
                        headingId.map { "project.addField.\($0)" } ?? "project.addField"
                    )
                    .onSubmit { addTodo(headingId: headingId, draft: draft) }
                Button("Add") { addTodo(headingId: headingId, draft: draft) }
                    .foregroundStyle(colors.accent)
                    .disabled(draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier(
                        headingId.map { "project.addButton.\($0)" } ?? "project.addButton"
                    )
            }
        }
    }

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
            model.errorMessage = error.localizedDescription
        }
    }

    private func addHeading() {
        do {
            _ = try model.store.run("New Heading") { d, env in
                try Commands.createHeading(d, env, projectId: projectId, title: "New Heading")
            }
            model.noteEntitiesChanged()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func toggleComplete(_ id: ID) {
        let open = model.entities.todos[id]?.status == .open
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
}
