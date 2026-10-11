import SwiftUI

/// Paper Add control: terracotta + circle and field (keeps SyncUITests IDs).
struct PaperAddRow: View {
    @Binding var title: String
    var colors: DayruleColors
    var onSubmit: () -> Void

    private var canAdd: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        RuledRow {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(colors.accent)
                    .accessibilityHidden(true)
                TextField("Add", text: $title)
                    .foregroundStyle(colors.text)
                    .accessibilityIdentifier("list.addField")
                    .onSubmit(onSubmit)
                Button("Add", action: onSubmit)
                    .accessibilityIdentifier("list.addButton")
                    .foregroundStyle(colors.accent)
                    .disabled(!canAdd)
                    .buttonStyle(.borderless)
            }
        }
    }
}
