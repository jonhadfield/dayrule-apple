import SwiftUI

/// Paper Add: leading terracotta + (focus or submit) + title field.
struct PaperAddRow: View {
    @Binding var title: String
    var colors: DayruleColors
    var fieldIdentifier: String = "list.addField"
    var buttonIdentifier: String = "list.addButton"
    var onSubmit: () -> Void
    @FocusState private var fieldFocused: Bool

    private var canAdd: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        RuledRow {
            HStack(spacing: 12) {
                Button {
                    if canAdd {
                        onSubmit()
                    } else {
                        fieldFocused = true
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(colors.bg)
                        .frame(width: 36, height: 36)
                        .background(colors.accent)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(buttonIdentifier)
                .accessibilityLabel("Add")
                TextField("Add", text: $title)
                    .foregroundStyle(colors.text)
                    .focused($fieldFocused)
                    .accessibilityIdentifier(fieldIdentifier)
                    .onSubmit(onSubmit)
            }
        }
    }
}
