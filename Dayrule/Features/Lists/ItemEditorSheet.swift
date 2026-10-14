import SwiftUI

/// Title/notes editor for a to-do or project (M5). Paper card with a terracotta
/// leading rule, matching web `TodoEditor` (PLAN §6.3).
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

    private enum Field {
        case title, notes
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
            .font(DayruleType.rowTitle)
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
                .font(DayruleType.rowTitle)
                .frame(minHeight: 160)
                .scrollContentBackground(.hidden)
                .foregroundStyle(colors.text)
                .focused($focus, equals: .notes)
                .overlay(alignment: .topLeading) {
                    if notes.isEmpty {
                        Text("Notes")
                            .font(DayruleType.rowTitle)
                            .foregroundStyle(colors.textSecondary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityLabel("Notes")
                .accessibilityIdentifier("editor.notes")
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
}
