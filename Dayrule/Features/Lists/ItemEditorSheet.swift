import SwiftUI

/// Title/notes editor for a to-do or project (M5). Paper card with a terracotta
/// leading rule, matching web `TodoEditor` (PLAN §6.3). To-dos also edit checklist
/// items live (web `addChecklistItem` / `updateChecklistItem` / `removeChecklistItem`).
struct ItemEditorSheet: View {
    @Bindable var model: AppModel
    let id: ID
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var loadedTitle: String = ""
    @State private var loadedNotes: String = ""
    @State private var isTodo = true
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case title, notes
        case checklist(ID)
    }

    var body: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme)
        DayruleSheet(
            title: isTodo ? "To-do" : "Project",
            confirm: SheetAction(
                title: "Save",
                identifier: "editor.save",
                isEnabled: !trimmedTitle.isEmpty
            ) { save() },
            size: .tall,
            isDirty: title != loadedTitle || notes != loadedNotes
        ) {
            ScrollView {
                editorCard(colors: colors)
                    .padding(Tokens.Space.l)
            }
            .scrollDismissesKeyboard(.interactively)
            .task {
                load()
                focus = .title
            }
        }
    }

    private func editorCard(colors: DayruleColors) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            TextField(
                "Title",
                text: $title,
                prompt: Text("Title").foregroundStyle(colors.textSecondary),
                axis: .vertical
            )
            .dayruleRowTitle()
            .lineLimit(1...4)
            .dayruleBareField(colors: colors)
            .focused($focus, equals: .title)
            .submitLabel(.next)
            .onSubmit { focus = .notes }
            .accessibilityIdentifier("editor.title")
            .onChange(of: title) { _, value in
                // A vertical field takes Return as a newline; titles are one line,
                // so treat it as "next field".
                guard value != loadedTitle, value.contains(where: \.isNewline) else {
                    return
                }
                title = value.filter { !$0.isNewline }
                focus = .notes
            }

            TextEditor(text: $notes)
                .dayruleRowTitle()
                .frame(minHeight: 120)
                .scrollContentBackground(.hidden)
                .foregroundStyle(colors.text)
                .focused($focus, equals: .notes)
                .overlay(alignment: .topLeading) {
                    if notes.isEmpty {
                        Text("Notes")
                            .dayruleRowTitle()
                            .foregroundStyle(colors.textSecondary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityLabel("Notes")
                .accessibilityIdentifier("editor.notes")

            if isTodo {
                checklistSection(colors: colors)
            }
        }
        .padding(Tokens.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.sidebar.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusCard, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.radiusCard, style: .continuous)
                .strokeBorder(colors.hairline, lineWidth: 1)
        )
        // Terracotta leading rule (web `border-l-[3px] border-l-accent`).
        .overlay(alignment: .leading) {
            colors.accent
                .frame(width: 3)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: Tokens.radiusCard,
                        bottomLeadingRadius: Tokens.radiusCard,
                        style: .continuous
                    )
                )
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func checklistSection(colors: DayruleColors) -> some View {
        let items = checklistItems
        VStack(alignment: .leading, spacing: 0) {
            if !items.isEmpty {
                colors.hairline.frame(height: 1)
                    .padding(.top, Tokens.Space.xs)
                ForEach(items, id: \.id) { item in
                    checklistRow(item, colors: colors)
                    colors.hairline.frame(height: 1)
                }
            }
            Button {
                addChecklistItem()
            } label: {
                Label("Checklist", systemImage: "checklist")
                    .font(DayruleType.meta)
                    .foregroundStyle(colors.textSecondary)
            }
            .buttonStyle(.plain)
            .padding(.top, Tokens.Space.s)
            .accessibilityIdentifier("editor.checklist.add")
        }
    }

    private func checklistRow(_ item: ChecklistItem, colors: DayruleColors) -> some View {
        HStack(spacing: Tokens.Space.s) {
            Button {
                toggleChecklistDone(item)
            } label: {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.done ? colors.accent : colors.textSecondary)
                    .imageScale(.medium)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.done ? "Mark not done" : "Mark done")
            .accessibilityIdentifier("editor.checklist.done.\(item.id)")

            TextField(
                "Checklist item",
                text: Binding(
                    get: { model.entities.checklistItems[item.id]?.title ?? item.title },
                    set: { setChecklistTitle(item.id, $0) }
                ),
                prompt: Text("Item").foregroundStyle(colors.textSecondary)
            )
            .font(DayruleType.meta)
            .strikethrough(item.done)
            .foregroundStyle(item.done ? colors.textSecondary : colors.text)
            .dayruleBareField(colors: colors)
            .focused($focus, equals: .checklist(item.id))
            .submitLabel(.next)
            .onSubmit { addChecklistItem() }
            .accessibilityIdentifier("editor.checklist.title.\(item.id)")

            Button {
                removeChecklistItem(item.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(colors.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove checklist item")
            .accessibilityIdentifier("editor.checklist.remove.\(item.id)")
        }
        .padding(.vertical, Tokens.Space.xs)
    }

    private var checklistItems: [ChecklistItem] {
        model.entities.checklistItems.values
            .filter { $0.todoId == id }
            .sorted { Order.compareKeys($0.order, $1.order) < 0 }
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func load() {
        if let t = model.entities.todos[id] {
            isTodo = true
            title = t.title
            notes = t.notes
        } else if let p = model.entities.projects[id] {
            isTodo = false
            title = p.title
            notes = p.notes
        }
        loadedTitle = title
        loadedNotes = notes
    }

    private func save() {
        let trimmed = trimmedTitle
        guard !trimmed.isEmpty else { return }
        model.store.run("Edit") { d, env in
            if isTodo {
                Commands.updateTodo(d, env, id: id, title: trimmed, notes: notes)
            } else {
                Commands.updateProject(d, env, id: id, title: trimmed, notes: notes)
            }
        }
        model.noteEntitiesChanged()
        dismiss()
    }

    private func addChecklistItem() {
        do {
            let item = try model.store.run("Checklist") { d, env in
                try Commands.addChecklistItem(d, env, todoId: id, title: "")
            }
            model.noteEntitiesChanged()
            focus = .checklist(item.id)
        } catch {
            model.notices.post(Notice(kind: .error, message: error.localizedDescription))
        }
    }

    private func toggleChecklistDone(_ item: ChecklistItem) {
        model.store.run("Checklist") { d, env in
            Commands.updateChecklistItem(d, env, id: item.id, done: !item.done)
        }
        model.noteEntitiesChanged()
    }

    private func setChecklistTitle(_ itemId: ID, _ title: String) {
        model.store.run("Checklist") { d, env in
            Commands.updateChecklistItem(d, env, id: itemId, title: title)
        }
        model.noteEntitiesChanged(animation: nil)
    }

    private func removeChecklistItem(_ itemId: ID) {
        model.store.run("Checklist") { d, _ in
            Commands.removeChecklistItem(d, id: itemId)
        }
        model.noteEntitiesChanged()
    }
}
