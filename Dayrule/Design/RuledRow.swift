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

/// Paper ruled row: one hairline under content; min height from
/// `Tokens.rowMinHeight` (phone compact / dense Mac and iPad — PLAN §6.2).
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
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dayruleDenseLayout) private var denseLayout

    init(style: Style = .ruled, @ViewBuilder content: @escaping () -> Content) {
        self.style = style
        self.content = content
    }

    var body: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme, contrast: colorSchemeContrast, reduceTransparency: reduceTransparency)
        // Padding sits inside the min height, so a single-line row is exactly `rowHeight`.
        // Reading-column margin is applied outside the List on Mac (padding) /
        // via `contentMargins` on iOS — keep row insets at `rowInset` only.
        content()
            .padding(.vertical, Tokens.rowVerticalPadding)
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
    /// stay single (decisions 53 / 71 / 73 / 74). Scheduled day headers are
    /// flat rows (not `Section`s) so a top section rule cannot stack under the
    /// page-title hairline.
    /// - Parameter macScrollFill: When non-`nil` on macOS, install warm
    ///   paper-tinted scrollers (light brown on dark paper). Pass `sidebar`
    ///   for split detail so knobs match the left rail; omit for `.sidebar`
    ///   lists (native taupe). Ignored on iOS.
    func dayrulePaperList(macScrollFill: Color? = nil) -> some View {
        modifier(DayrulePaperListModifier(macScrollFill: macScrollFill))
    }

    /// One drawn hairline under a non-`RuledRow` list row (Browse links).
    /// Zero vertical insets so NavigationLink does not pad past the dense row height.
    func dayruleDrawnRowRule(colors: DayruleColors) -> some View {
        listRowSeparator(.hidden)
            .listRowInsets(
                EdgeInsets(top: 0, leading: Tokens.rowInset, bottom: 0, trailing: Tokens.rowInset)
            )
            .listRowBackground(
                DayrulePaperRowBackground(
                    fill: colors.bg,
                    hairline: colors.hairline,
                    showsHairline: true
                )
            )
    }
}

private struct DayrulePaperListModifier: ViewModifier {
    var macScrollFill: Color?
    @Environment(\.dayruleDenseLayout) private var denseLayout

    func body(content: Content) -> some View {
        // iOS List defaults to ~44pt min rows; without this, RuledRow’s shorter
        // minHeight still looks airy (empty space above/below the title).
        content
            .environment(\.defaultMinListRowHeight, Tokens.rowMinHeight(dense: denseLayout))
            .listSectionSeparator(.hidden)
            .listRowSeparator(.hidden)
            #if os(macOS)
            .background(MacListHideSystemSeparators(scrollFill: macScrollFill))
            #endif
    }
}

/// Muted one-line note in the list ("Syncing…", "Pulling vault…").
struct DayruleNoteRow: View {
    var text: String
    var showsProgress: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme, contrast: colorSchemeContrast, reduceTransparency: reduceTransparency)
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
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ScaledMetric(relativeTo: .largeTitle) private var glyphSize: CGFloat = 96

    var body: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme, contrast: colorSchemeContrast, reduceTransparency: reduceTransparency)
        RuledRow(style: .note) {
            Image(systemName: systemImage)
                .font(.system(size: glyphSize))
                .foregroundStyle(
                    colors.textSecondary.opacity(colors.increasedContrast ? 0.28 : 0.15)
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, Tokens.Space.xxl)
                .accessibilityElement()
                .accessibilityLabel(accessibilityLabel)
        }
    }
}
