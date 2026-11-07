import SwiftUI

/// Rename / archive / convert / delete a project heading (M5).
struct HeadingSheetView: View {
    @Bindable var model: AppModel
    let headingId: ID
    /// Opens the project created by Convert to Project.
    var onOpenProject: ((ID) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var title = ""
    @State private var loadedTitle = ""
    @State private var titleSelection: TextSelection?
    @State private var confirmingDelete = false
    @FocusState private var titleFocused: Bool

    var body: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme)
        DayruleSheet(
            title: "Heading",
            confirm: SheetAction(
                title: "Save",
                identifier: "heading.save",
                isEnabled: !trimmedTitle.isEmpty
            ) { save() },
            size: .compact,
            detents: [.medium],
            isDirty: title != loadedTitle
        ) {
            Form {
                Section {
                    TextField(
                        "Title",
                        text: $title,
                        selection: $titleSelection,
                        prompt: Text("Title").foregroundStyle(colors.textSecondary)
                    )
                    .dayruleBareField(colors: colors)
                    .focused($titleFocused)
                    .submitLabel(.done)
                    .onSubmit(save)
                    .accessibilityIdentifier("heading.title")
                }
                .dayruleSheetRow(colors: colors)
                DayruleFormSection {
                    Button(action: convertToProject) {
                        Text("Convert to Project")
                            .foregroundStyle(colors.text)
                            .frame(minHeight: Tokens.minHit)
                    }
                    .buttonStyle(.dayruleRow)
                    .accessibilityIdentifier("heading.convertToProject")
                    Button(action: archive) {
                        Text("Archive")
                            .foregroundStyle(colors.text)
                            .frame(minHeight: Tokens.minHit)
                    }
                    .buttonStyle(.dayruleRow)
                    .accessibilityIdentifier("heading.archive")
                } footer: {
                    Text("Convert turns this heading into a project and moves its to-dos. Archive hides the heading; its to-dos stay in the project.")
                        .font(DayruleType.helper)
                        .foregroundStyle(colors.textSecondary)
                }
                .dayruleSheetRow(colors: colors)
                SheetClearSection(title: "Delete", isVisible: true, identifier: "heading.delete") {
                    confirmingDelete = true
                }
            }
            .confirmationDialog(
                "Delete heading?",
                isPresented: $confirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Delete Heading", role: .destructive, action: deleteHeading)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Its to-dos stay in the project.")
            }
            .task {
                load()
                titleSelection = TextSelection(range: title.startIndex..<title.endIndex)
                titleFocused = true
            }
        }
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func load() {
        title = model.entities.headings[headingId]?.title ?? ""
        loadedTitle = title
    }

    private func save() {
        let trimmed = trimmedTitle
        guard !trimmed.isEmpty else { return }
        model.store.run("Rename Heading") { d, env in
            Commands.updateHeading(d, env, id: headingId, title: trimmed, archived: nil)
        }
        model.noteEntitiesChanged()
        dismiss()
    }

    private func convertToProject() {
        let label = trimmedTitle.isEmpty ? loadedTitle : trimmedTitle
        do {
            let project = try model.store.run("Convert Heading to Project") { d, env in
                try Commands.convertHeadingToProject(d, env, headingId: headingId)
            }
            model.noteEntitiesChanged()
            model.undoNotice("Converted \(label) to a project")
            dismiss()
            onOpenProject?(project.id)
        } catch {
            model.notices.post(Notice(kind: .error, message: error.localizedDescription))
        }
    }

    private func archive() {
        model.store.run("Archive Heading") { d, env in
            Commands.updateHeading(d, env, id: headingId, title: nil, archived: true)
        }
        model.noteEntitiesChanged()
        dismiss()
    }

    private func deleteHeading() {
        model.store.run("Delete Heading") { d, env in
            Commands.deleteHeading(d, env, id: headingId)
        }
        model.noteEntitiesChanged()
        dismiss()
    }
}
