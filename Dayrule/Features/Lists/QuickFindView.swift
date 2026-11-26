import SwiftUI

/// Search overlay over decrypted entities (PLAN §5 Quick Find / M5).
struct QuickFindView: View {
    @Bindable var model: AppModel
    var onSelect: (Find.Result) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var query = ""
    @State private var searchPresented = false
    @FocusState private var focused: Bool

    private var results: [Find.Result] {
        let ctx = Lists.Context(today: When.toLocalDate(Date()), keepVisible: nil)
        return Find.buildFinder(model.entities, ctx).search(query)
    }

    var body: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme, contrast: colorSchemeContrast, reduceTransparency: reduceTransparency)
        // Cancel sits in .cancellationAction (Esc), so Return stays free to pick the top result.
        DayruleSheet(title: "Find", dismissTitle: "Cancel", dismissIdentifier: "find.close", size: .tall) {
            List {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    DayruleNoteRow(text: "Search lists, projects and to-dos")
                } else if results.isEmpty {
                    DayruleNoteRow(text: "Nothing matches")
                } else {
                    ForEach(results) { row in
                        resultRow(row, colors: colors)
                    }
                }
            }
            .listStyle(.plain)
            .dayrulePaperList(macScrollFill: colors.bg)
            #if os(iOS)
            .searchable(
                text: $query,
                isPresented: $searchPresented,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Find…"
            )
            .searchFocused($focused)
            // The search bar's own close button ends Find, so it never takes two dismissals.
            .onChange(of: searchPresented) { wasPresented, presented in
                if wasPresented, !presented { dismiss() }
            }
            .onSubmit(of: .search, selectFirst)
            #else
            // A paper field under the header; the toolbar search box would sit apart
            // from the results with the system focus ring.
            .safeAreaInset(edge: .top, spacing: 0) {
                macSearchField(colors: colors)
            }
            #endif
            .task {
                // Focus once the sheet is on screen; setting it during presentation is dropped.
                await Task.yield()
                searchPresented = true
                focused = true
            }
        }
    }

    #if os(macOS)
    private func macSearchField(colors: DayruleColors) -> some View {
        HStack(spacing: Tokens.Space.s) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(colors.textSecondary)
                .accessibilityHidden(true)
            TextField("Find", text: $query, prompt: Text("Find…").foregroundStyle(colors.textSecondary))
                .labelsHidden()
                .focused($focused)
                .onSubmit(selectFirst)
                .accessibilityIdentifier("find.field")
        }
        .dayruleField(isFocused: focused, colors: colors)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(colors.bg)
    }
    #endif

    private func selectFirst() {
        if let first = results.first {
            select(first)
        }
    }

    private func resultRow(_ row: Find.Result, colors: DayruleColors) -> some View {
        RuledRow {
            Button {
                select(row)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                        .dayruleRowTitle()
                        .foregroundStyle(colors.text)
                    Text(row.detail)
                        .font(DayruleType.meta)
                        .foregroundStyle(colors.textSecondary)
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.dayruleRow)
            .accessibilityIdentifier("find.row.\(row.id)")
        }
    }

    /// The caller holds the result until the sheet has gone, then navigates.
    private func select(_ row: Find.Result) {
        onSelect(row)
        dismiss()
    }
}
