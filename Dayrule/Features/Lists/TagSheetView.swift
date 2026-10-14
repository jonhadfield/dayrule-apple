import SwiftUI

/// Assign tags to to-dos/projects; create a tag if needed (M5). New tags are staged
/// until Save, so Cancel leaves nothing behind.
struct TagSheetView: View {
    @Bindable var model: AppModel
    let ids: [ID]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var selected: Set<ID> = []
    @State private var initialSelected: Set<ID> = []
    /// Titles of tags to create on Save (always assigned).
    @State private var pending: [String] = []
    @State private var newTitle = ""
    @State private var errorText: String?

    var body: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme)
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
                        tagRow(tag.title, selected: selected.contains(tag.id)) {
                            if selected.contains(tag.id) { selected.remove(tag.id) }
                            else { selected.insert(tag.id) }
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
                    DayruleSectionHeader(title: "New tag")
                }
            }
            .listStyle(.plain)
            .dayruleAnimation(Motion.quick, value: errorText)
            .dayruleAnimation(Motion.standard, value: pending)
            .onChange(of: newTitle) { errorText = nil }
            .onAppear(perform: load)
        }
    }

    private var trimmedTitle: String {
        newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func tagRow(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme)
        return Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if selected {
                    SelectionCheckmark()
                }
            }
            .frame(minHeight: Tokens.rowHeight)
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
