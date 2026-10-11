import SwiftUI

/// Assign tags to to-dos/projects; create a tag if needed (M5).
struct TagSheetView: View {
    @Bindable var model: AppModel
    let ids: [ID]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var selected: Set<ID> = []
    @State private var newTitle = ""

    var body: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme)
        let tags = model.entities.tags.values.sorted {
            Order.compareKeys($0.order, $1.order) < 0
        }
        NavigationStack {
            List {
                Section {
                    ForEach(tags, id: \.id) { tag in
                        Button {
                            if selected.contains(tag.id) { selected.remove(tag.id) }
                            else { selected.insert(tag.id) }
                        } label: {
                            HStack {
                                Text(tag.title)
                                    .foregroundStyle(colors.text)
                                Spacer()
                                if selected.contains(tag.id) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(colors.accent)
                                }
                            }
                        }
                        .accessibilityIdentifier("tag.row.\(tag.id)")
                    }
                }
                Section("New tag") {
                    TextField("Title", text: $newTitle)
                        .accessibilityIdentifier("tag.newTitle")
                    Button("Add tag") { addTag() }
                        .foregroundStyle(colors.accent)
                        .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("tag.add")
                }
            }
            .scrollContentBackground(.hidden)
            .background(colors.bg)
            .navigationTitle("Tags")
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
                        .accessibilityIdentifier("tag.save")
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard let id = ids.first else { return }
        if let t = model.entities.todos[id] {
            selected = Set(t.tagIds)
        } else if let p = model.entities.projects[id] {
            selected = Set(p.tagIds)
        }
    }

    private func addTag() {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        do {
            let tag = try model.store.run("Tag") { d, env in
                try Commands.createTag(d, env, title: title)
            }
            selected.insert(tag.id)
            newTitle = ""
            model.noteEntitiesChanged()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func save() {
        let ordered = model.entities.tags.values
            .filter { selected.contains($0.id) }
            .sorted { Order.compareKeys($0.order, $1.order) < 0 }
            .map(\.id)
        model.store.run("Tags") { d, env in
            Commands.setTags(d, env, ids: ids, tagIds: ordered)
        }
        model.noteEntitiesChanged()
        dismiss()
    }
}
