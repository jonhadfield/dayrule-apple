import SwiftUI

/// Search overlay over decrypted entities (PLAN §5 Quick Find / M5).
struct QuickFindView: View {
    @Bindable var model: AppModel
    var onSelect: (Find.Result) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var query = ""
    @FocusState private var focused: Bool

    private var results: [Find.Result] {
        let ctx = Lists.Context(today: When.toLocalDate(Date()), keepVisible: nil)
        return Find.buildFinder(model.entities, ctx).search(query)
    }

    var body: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme)
        NavigationStack {
            List {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Search lists, projects and to-dos")
                        .foregroundStyle(colors.textSecondary)
                } else if results.isEmpty {
                    Text("Nothing matches")
                        .foregroundStyle(colors.textSecondary)
                } else {
                    ForEach(results) { row in
                        Button {
                            onSelect(row)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.title)
                                    .foregroundStyle(colors.text)
                                Text(row.detail)
                                    .font(.caption)
                                    .foregroundStyle(colors.textSecondary)
                            }
                        }
                        .accessibilityIdentifier("find.row.\(row.id)")
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(colors.bg)
            .navigationTitle("Find")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .searchable(text: $query, prompt: "Find…")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(colors.accent)
                        .accessibilityIdentifier("find.close")
                }
            }
            .onAppear { focused = true }
        }
    }
}
