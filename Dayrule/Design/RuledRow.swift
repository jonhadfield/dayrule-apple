import SwiftUI

/// Paper fill + optional bottom hairline for list rows (PLAN §6.2).
/// Callers that set `listRowBackground` (e.g. selection tint) must use this so
/// they do not wipe the rule — that left only AppKit’s double grid on Mac.
struct DayrulePaperRowBackground: View {
    var fill: Color
    var hairline: Color
    var showsHairline: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            fill
            if showsHairline {
                hairline.frame(height: 1)
            }
        }
    }
}

/// Paper ruled row: one hairline under content; min height 46 phone compact /
/// 36 dense (Mac and iPad regular — PLAN §6.2).
///
/// System list separators stay hidden; we draw one paper hairline in the row
/// background. On macOS, AppKit grid lines are also cleared via
/// `MacListHideSystemSeparators` on `dayrulePaperList` (decision 74).
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
            .padding(.vertical, Tokens.Space.xs)
            .frame(
                maxWidth: .infinity,
                minHeight: Tokens.rowMinHeight(dense: denseLayout),
                alignment: .leading
            )
            .listRowInsets(
                EdgeInsets(top: 0, leading: Tokens.rowInset, bottom: 0, trailing: Tokens.rowInset)
            )
            .listRowSeparator(.hidden)
            .listRowBackground(
                DayrulePaperRowBackground(
                    fill: colors.bg,
                    hairline: colors.hairline,
                    showsHairline: style == .ruled
                )
            )
    }
}

extension View {
    /// Paper list chrome: hide system section *and* row rules so drawn hairlines
    /// stay single (decisions 53 / 71 / 73 / 74).
    func dayrulePaperList() -> some View {
        listSectionSeparator(.hidden)
            .listRowSeparator(.hidden)
            #if os(macOS)
            .background(MacListHideSystemSeparators())
            #endif
    }

    /// One drawn hairline under a non-`RuledRow` list row (Browse links).
    func dayruleDrawnRowRule(colors: DayruleColors) -> some View {
        listRowSeparator(.hidden)
            .listRowBackground(
                DayrulePaperRowBackground(
                    fill: colors.bg,
                    hairline: colors.hairline,
                    showsHairline: true
                )
            )
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
                    .font(DayruleType.meta)
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
                .padding(.vertical, Tokens.Space.xxl)
                .accessibilityElement()
                .accessibilityLabel(accessibilityLabel)
        }
    }
}
