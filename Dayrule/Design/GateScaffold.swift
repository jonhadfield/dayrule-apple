import SwiftUI

/// Gate screen layout: readable column, vertically centred, scrolls under the keyboard.
/// Content receives the scroll proxy so a screen can scroll its error into view.
struct GateScaffold<Content: View>: View {
    var alignment: HorizontalAlignment = .leading
    var title: String?
    var subtitle: String?
    var titleFont: Font = DayruleType.pageTitle
    var content: (ScrollViewProxy) -> Content

    @Environment(\.colorScheme) private var colorScheme
    /// Visible scroll height; the column is at least this tall so short forms centre
    /// and long ones (signup, recovery words, keyboard up, large type) still scroll.
    @State private var viewportHeight: CGFloat = 0

    init(
        alignment: HorizontalAlignment = .leading,
        title: String? = nil,
        subtitle: String? = nil,
        titleFont: Font = DayruleType.pageTitle,
        @ViewBuilder content: @escaping (ScrollViewProxy) -> Content
    ) {
        self.alignment = alignment
        self.title = title
        self.subtitle = subtitle
        self.titleFont = titleFont
        self.content = content
    }

    private var textAlignment: TextAlignment {
        switch alignment {
        case .center: .center
        case .trailing: .trailing
        default: .leading
        }
    }

    var body: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme)
        FoldSafeContainer {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: alignment, spacing: Tokens.Space.l) {
                        if title != nil || subtitle != nil {
                            VStack(alignment: alignment, spacing: Tokens.Space.s) {
                                if let title {
                                    Text(title)
                                        .font(titleFont)
                                        .tracking(DayruleType.titleTracking)
                                        .multilineTextAlignment(textAlignment)
                                        .accessibilityAddTraits(.isHeader)
                                }
                                if let subtitle {
                                    Text(subtitle)
                                        .font(.body)
                                        .foregroundStyle(colors.textSecondary)
                                        .multilineTextAlignment(textAlignment)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        content(proxy)
                    }
                    .frame(maxWidth: Tokens.formMaxWidth)
                    .padding(.horizontal, Tokens.Space.xl)
                    .padding(.vertical, Tokens.Space.xxl)
                    .frame(maxWidth: .infinity, minHeight: viewportHeight, alignment: .center)
                }
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    viewportHeight = height
                }
                .scrollDismissesKeyboard(.interactively)
                .background(colors.bg)
                .foregroundStyle(colors.text)
            }
        }
    }
}

/// Inline gate message under the form. Its id is `gate.message` for `proxy.scrollTo`.
struct GateInlineMessage: View {
    enum Kind {
        case error, info
    }

    var text: String
    var kind: Kind = .error
    var identifier: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme)
        Text(text)
            .font(kind == .error ? DayruleType.error : DayruleType.helper)
            .foregroundStyle(kind == .error ? colors.deadline : colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .transition(.dayruleInlineError)
            .id("gate.message")
            .accessibilityIdentifier(identifier)
    }
}
