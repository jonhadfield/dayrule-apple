import SwiftUI

/// Rename / archive / delete a project heading (M5).
struct HeadingSheetView: View {
    @Bindable var model: AppModel
    let headingId: ID
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var title = ""

    var body: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme)
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                        .accessibilityIdentifier("heading.title")
                }
            }
            .scrollContentBackground(.hidden)
            .background(colors.bg)
            .navigationTitle("Heading")
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
                        .accessibilityIdentifier("heading.save")
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button("Archive") { archive() }
                        .foregroundStyle(colors.textSecondary)
                        .accessibilityIdentifier("heading.archive")
                    Spacer()
                    Button("Delete", role: .destructive) { deleteHeading() }
                        .accessibilityIdentifier("heading.delete")
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        title = model.entities.headings[headingId]?.title ?? ""
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        model.store.run("Rename Heading") { d, env in
            Commands.updateHeading(d, env, id: headingId, title: trimmed, archived: nil)
        }
        model.noteEntitiesChanged()
        dismiss()
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
