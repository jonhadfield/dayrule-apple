import SwiftUI

/// Title/notes editor for a to-do or project (M5).
struct ItemEditorSheet: View {
    @Bindable var model: AppModel
    let id: ID
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var isTodo = true

    var body: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme)
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                        .accessibilityIdentifier("editor.title")
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                        .accessibilityIdentifier("editor.notes")
                }
            }
            .scrollContentBackground(.hidden)
            .background(colors.bg)
            .navigationTitle(isTodo ? "To-do" : "Project")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(colors.accent)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .foregroundStyle(colors.accent)
                        .accessibilityIdentifier("editor.save")
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear(perform: load)
        }
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
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
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
