import SwiftUI

/// Paper ruled row: hairline under content; min height 46 phone compact /
/// 36 dense (Mac and iPad regular — PLAN §6.2).
///
/// On macOS, SwiftUI `List` still draws a system row separator even when a custom
/// hairline is overlaid — the two stack as a double rule. Mac therefore uses one
/// tinted system separator; iOS keeps the drawn hairline (decision 71).
struct RuledRow<Content: View>: View {
    enum Style {
        /// Hairline under the row.
        case ruled
        /// No hairline (empty states, notes between rows).
        case note
    }

    var style: Style
    var content: () -> Content

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dayruleDenseLayout) private var denseLayout

    init(style: Style = .ruled, @ViewBuilder content: @escaping () -> Content) {
        self.style = style
        self.content = content
    }

    var body: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme)
        // Padding sits inside the min height, so a single-line row is exactly `rowHeight`.
        content()
            .padding(.vertical, 4)
            .frame(
                maxWidth: .infinity,
                minHeight: Tokens.rowMinHeight(dense: denseLayout),
                alignment: .leading
            )
            #if os(iOS)
            .overlay(alignment: .bottom) {
                if style == .ruled {
                    colors.hairline.frame(height: 1)
                }
            }
            .listRowSeparator(.hidden)
            #else
            .listRowSeparator(style == .ruled ? .visible : .hidden)
            .listRowSeparatorTint(colors.hairline)
            #endif
            .listRowInsets(
                EdgeInsets(top: 0, leading: Tokens.rowInset, bottom: 0, trailing: Tokens.rowInset)
            )
            .listRowBackground(colors.bg)
    }
}

extension View {
    /// Paper list chrome: hide system *section* rules so `DayruleSectionHeader`
    /// hairlines stay single (decision 53 / 71).
    func dayrulePaperList() -> some View {
        listSectionSeparator(.hidden)
    }
}

/// Muted one-line note in the list ("Syncing…", "Pulling vault…").
struct DayruleNoteRow: View {
    var text: String
    var showsProgress: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme)
        RuledRow(style: .ruled) {
            HStack(spacing: Tokens.Space.s) {
                if showsProgress {
                    ProgressView().controlSize(.small)
                }
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(colors.textSecondary)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// Quiet empty list: a large faint glyph, no copy on the page (mirrors web ListShell).
struct DayruleEmptyState: View {
    var systemImage: String
    var accessibilityLabel: String

    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .largeTitle) private var glyphSize: CGFloat = 96

    var body: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme)
        RuledRow(style: .note) {
            Image(systemName: systemImage)
                .font(.system(size: glyphSize))
                .foregroundStyle(colors.textSecondary.opacity(0.15))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .accessibilityElement()
                .accessibilityLabel(accessibilityLabel)
        }
    }
}
