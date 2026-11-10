import SwiftUI

/// One section header for lists and sheets: paper background (stays on paper when
/// pinned), hairline beneath, header trait. In a sidebar it keeps the sidebar's own
/// insets and surface instead.
struct DayruleSectionHeader: View {
    enum Tone {
        case muted, accent, later, deadline
    }

    enum Surface {
        /// Page lists and sheets: paper fill, hairline, full-width row.
        case page
        /// iPad / Mac sidebar: no fill or hairline, sidebar insets.
        case sidebar
    }

    enum Style {
        /// Uppercased by the view; callers pass mixed-case strings.
        case caps
        case sentence
        case serif
    }

    let title: String
    var tone: Tone = .muted
    var style: Style = .sentence
    /// Secondary text on the trailing edge (e.g. weekday on Scheduled day headers).
    var trailing: AnyView? = nil
    var surface: Surface = .page

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme)
        let row = HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
            styledTitle
                .foregroundStyle(toneColor(colors))
                .accessibilityAddTraits(.isHeader)
            if let trailing {
                Spacer(minLength: 0)
                trailing
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        switch surface {
        case .page:
            pageChrome(row, colors: colors)
        case .sidebar:
            row
        }
    }

    private func pageChrome(_ row: some View, colors: DayruleColors) -> some View {
        // Match `DayruleSheetHeader`’s 20pt horizontal inset. On macOS, Section
        // headers already get a system leading inset — extra padding here made
        // chapter titles (“Your data”, “Help”) sit further in than the rows.
        #if os(macOS)
        row
            .padding(.top, 14)
            .padding(.bottom, 6)
            .overlay(alignment: .bottom) {
                colors.hairline.frame(height: 1)
            }
            .background(colors.bg)
            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
        #else
        row
            .padding(.leading, Tokens.rowInset)
            .padding(.trailing, Tokens.rowInset)
            .padding(.top, 14)
            .padding(.bottom, 6)
            .overlay(alignment: .bottom) {
                colors.hairline.frame(height: 1)
            }
            .background(colors.bg)
            .listRowInsets(EdgeInsets())
        #endif
    }

    @ViewBuilder
    private var styledTitle: some View {
        switch style {
        case .caps:
            Text(title)
                .font(DayruleType.sectionHeader)
                .textCase(.uppercase)
                .tracking(0.6)
        case .sentence:
            Text(title)
                .font(DayruleType.sectionHeader)
                .textCase(nil)
        case .serif:
            Text(title)
                .font(DayruleType.sectionSerif)
                .textCase(nil)
        }
    }

    private func toneColor(_ colors: DayruleColors) -> Color {
        switch tone {
        case .muted: colors.textSecondary
        case .accent: colors.accent
        case .later: colors.later
        case .deadline: colors.deadline
        }
    }
}

/// Form section whose footer always shows in full. Mac grouped forms under-measure
/// multi-line footers, which then truncate or overlap the rows around them, so on
/// macOS the footer becomes the section's last, unruled row.
///
/// System list/section separators stay hidden: `DayruleSectionHeader` already draws
/// one hairline under the chapter title, and stacking both looked like double rules
/// (PLAN decision 53).
struct DayruleFormSection<Content: View, Header: View, Footer: View>: View {
    @ViewBuilder var content: Content
    @ViewBuilder var header: Header
    @ViewBuilder var footer: Footer
    private let showsFooter: Bool

    init(
        @ViewBuilder content: () -> Content,
        @ViewBuilder header: () -> Header,
        @ViewBuilder footer: () -> Footer
    ) {
        self.content = content()
        self.header = header()
        self.footer = footer()
        self.showsFooter = true
    }

    var body: some View {
        #if os(macOS)
        Section {
            content
            if showsFooter {
                footer
                    .listRowSeparator(.hidden)
                    // Helper copy, not a tappable row — match sheet title inset.
                    .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 12, trailing: 20))
            }
        } header: {
            header
        }
        .listSectionSeparator(.hidden)
        .listRowSeparator(.hidden)
        #else
        Section {
            content
        } header: {
            header
        } footer: {
            if showsFooter { footer }
        }
        .listSectionSeparator(.hidden)
        .listRowSeparator(.hidden)
        #endif
    }
}

extension DayruleFormSection where Header == EmptyView {
    init(@ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.init(content: content, header: { EmptyView() }, footer: footer)
    }
}

extension DayruleFormSection where Footer == EmptyView {
    init(@ViewBuilder content: () -> Content, @ViewBuilder header: () -> Header) {
        self.content = content()
        self.header = header()
        self.footer = EmptyView()
        self.showsFooter = false
    }
}
