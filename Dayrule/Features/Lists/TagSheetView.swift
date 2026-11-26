import SwiftUI

/// Assign tags to to-dos/projects; create a tag if needed (M5). New tags are staged
/// until Save, so Cancel leaves nothing behind. Existing tags can be renamed or
/// deleted from the row menu (web `renameTag` / `deleteTag`).
struct TagSheetView: View {
    @Bindable var model: AppModel
    let ids: [ID]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dayruleDenseLayout) private var denseLayout
    @State private var selected: Set<ID> = []
    @State private var initialSelected: Set<ID> = []
    /// Titles of tags to create on Save (always assigned).
    @State private var pending: [String] = []
    @State private var newTitle = ""
    @State private var errorText: String?
    @State private var renameTarget: RenameTarget?
    @State private var renameDraft = ""
    @State private var deleteTarget: DeleteTarget?

    private struct RenameTarget: Identifiable {
        var id: ID
        var title: String
    }

    private struct DeleteTarget: Identifiable {
        var id: ID
        var title: String
    }

    var body: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme, contrast: colorSchemeContrast, reduceTransparency: reduceTransparency)
        let tags = model.entities.tags.values.sorted {
            Order.compareKeys($0.order, $1.order) < 0
        }
        DayruleSheet(
            title: "Tags",
            confirm: SheetAction(title: "Save", identifier: "tag.save") { save() },
            detents: [.medium, .large],
            isDirty: selected != initialSelected || !pending.isEmpty
        ) {
            List {
                Section {
                    if tags.isEmpty && pending.isEmpty {
                        Text("No tags yet — add one below.")
                            .font(DayruleType.helper)
                            .foregroundStyle(colors.textSecondary)
                            .dayruleSheetRow(colors: colors)
                    }
                    ForEach(tags, id: \.id) { tag in
                        tagRow(
                            displayTitle(for: tag, in: tags),
                            selected: selected.contains(tag.id)
                        ) {
                            if selected.contains(tag.id) { selected.remove(tag.id) }
                            else { selected.insert(tag.id) }
                        }
                        .contextMenu {
                            Button {
                                renameDraft = tag.title
                                renameTarget = RenameTarget(id: tag.id, title: tag.title)
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                deleteTarget = DeleteTarget(id: tag.id, title: tag.title)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .accessibilityIdentifier("tag.row.\(tag.id)")
                    }
                    ForEach(pending, id: \.self) { title in
                        tagRow(title, selected: true) {
                            pending.removeAll { $0 == title }
                        }
                    }
                }
                Section {
                    HStack(spacing: Tokens.Space.s) {
                        TextField(
                            "New tag",
                            text: $newTitle,
                            prompt: Text("New tag name").foregroundStyle(colors.textSecondary)
                        )
                        .dayruleBareField(colors: colors)
                        .submitLabel(.done)
                        .onSubmit(addTag)
                        .accessibilityIdentifier("tag.newTitle")
                        Button("Add tag", action: addTag)
                            .buttonStyle(.borderless)
                            .disabled(trimmedTitle.isEmpty)
                            .accessibilityIdentifier("tag.add")
                    }
                    .dayruleSheetRow(colors: colors)
                    if let errorText {
                        Text(errorText)
                            .font(DayruleType.error)
                            .foregroundStyle(colors.deadline)
                            .transition(.dayruleInlineError)
                            .dayruleSheetRow(colors: colors)
                    }
                } header: {
                    DayruleSectionHeader(title: "New tag", surface: .sheet)
                }
            }
            .listStyle(.plain)
            .dayruleAnimation(Motion.quick, value: errorText)
            .dayruleAnimation(Motion.standard, value: pending)
            .onChange(of: newTitle) { errorText = nil }
            .onAppear(perform: load)
            .alert(
                "Rename tag",
                isPresented: Binding(
                    get: { renameTarget != nil },
                    set: { if !$0 { renameTarget = nil } }
                )
            ) {
                TextField("Title", text: $renameDraft)
                Button("Save") { commitRename() }
                Button("Cancel", role: .cancel) { renameTarget = nil }
            } message: {
                Text("Change the name for everyone who uses this tag.")
            }
            .confirmationDialog(
                deleteDialogTitle,
                isPresented: Binding(
                    get: { deleteTarget != nil },
                    set: { if !$0 { deleteTarget = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete Tag", role: .destructive, action: commitDelete)
                Button("Cancel", role: .cancel) { deleteTarget = nil }
            } message: {
                Text("Removes it from every to-do, project and area. Child tags go too.")
            }
        }
    }

    private var trimmedTitle: String {
        newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var deleteDialogTitle: String {
        guard let title = deleteTarget?.title, !title.isEmpty else { return "Delete tag?" }
        return "Delete “\(title)”?"
    }

    private func displayTitle(for tag: Tag, in tags: [Tag]) -> String {
        if let parentId = tag.parentId,
           let parent = tags.first(where: { $0.id == parentId }),
           !parent.title.isEmpty {
            return "\(parent.title) › \(tag.title)"
        }
        return tag.title
    }

    private func tagRow(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme, contrast: colorSchemeContrast, reduceTransparency: reduceTransparency)
        return Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if selected {
                    SelectionCheckmark()
                }
            }
            .frame(minHeight: Tokens.rowMinHeight(dense: denseLayout))
        }
        .buttonStyle(.dayruleRow)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .dayruleSheetRow(colors: colors)
    }

    private func load() {
        guard let id = ids.first else { return }
        if let t = model.entities.todos[id] {
            selected = Set(t.tagIds)
        } else if let p = model.entities.projects[id] {
            selected = Set(p.tagIds)
        }
        initialSelected = selected
    }

    /// Stage a new title; an existing tag (or staged one) with the same name is selected instead.
    private func addTag() {
        let title = trimmedTitle
        guard !title.isEmpty else { return }
        if let existing = model.entities.tags.values.first(where: {
            $0.title.compare(title, options: .caseInsensitive) == .orderedSame
        }) {
            selected.insert(existing.id)
        } else if !pending.contains(where: {
            $0.compare(title, options: .caseInsensitive) == .orderedSame
        }) {
            pending.append(title)
        }
        newTitle = ""
    }

    private func commitRename() {
        guard let target = renameTarget else { return }
        let title = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        renameTarget = nil
        guard !title.isEmpty else { return }
        model.store.run("Rename Tag") { d, env in
            Commands.renameTag(d, env, id: target.id, title: title)
        }
        model.noteEntitiesChanged()
    }

    private func commitDelete() {
        guard let target = deleteTarget else { return }
        deleteTarget = nil
        model.store.run("Delete Tag") { d, env in
            Commands.deleteTag(d, env, id: target.id)
        }
        model.noteEntitiesChanged()
        let still = Set(model.entities.tags.keys)
        selected = selected.intersection(still)
        initialSelected = initialSelected.intersection(still)
    }

    private func save() {
        do {
            try model.store.run("Tags") { d, env in
                var tagIds = selected
                for title in pending {
                    let tag = try Commands.createTag(d, env, title: title)
                    tagIds.insert(tag.id)
                }
                let ordered = d.allTags()
                    .filter { tagIds.contains($0.id) }
                    .sorted { Order.compareKeys($0.order, $1.order) < 0 }
                    .map(\.id)
                Commands.setTags(d, env, ids: ids, tagIds: ordered)
            }
            model.noteEntitiesChanged()
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
