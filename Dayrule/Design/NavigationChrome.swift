import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

#if os(iOS)
/// One-time nav bar appearance: Fraunces titles, cream bar, no hairline shadow (PLAN §6.2).
/// Colours are dynamic `UIColor`s, so a light/dark switch never leaves stale ink.
enum DayruleNavAppearance {
    @MainActor
    static func configure() {
        let appearance = UINavigationBarAppearance()
        if #available(iOS 26, *) {
            // An opaque bar paints over the large title on iOS 26; the paper
            // behind the list shows through and the system draws the scroll edge.
            appearance.configureWithTransparentBackground()
        } else {
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor {
                $0.userInterfaceStyle == .dark ? UIColor(Tokens.Dark.bg) : UIColor(Tokens.Light.bg)
            }
        }
        appearance.shadowColor = .clear
        let ink = UIColor {
            $0.userInterfaceStyle == .dark ? UIColor(Tokens.Dark.text) : UIColor(Tokens.Light.text)
        }
        appearance.largeTitleTextAttributes = [
            .font: DayruleFont.uiFont(.largeTitle, size: 34),
            .foregroundColor: ink,
        ]
        appearance.titleTextAttributes = [
            .font: DayruleFont.uiFont(.headline, size: 17),
            .foregroundColor: ink,
        ]
        let nav = UINavigationBar.appearance()
        nav.standardAppearance = appearance
        nav.scrollEdgeAppearance = appearance
        nav.compactAppearance = appearance
    }
}
#endif

/// Paper nav chrome for list screens. The bar appearance itself is set once via
/// `DayruleNavAppearance.configure()`; on macOS the title is drawn by `dayrulePageTitle`.
struct DayruleListNavChrome: ViewModifier {
    var colors: DayruleColors

    func body(content: Content) -> some View {
        content
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            .modifier(PaperBarBackground(colors: colors))
            #elseif os(macOS)
            .toolbar(removing: .title)
            #endif
    }
}

#if os(iOS)
/// iOS 18 keeps the opaque paper bar. On iOS 26 a forced bar background hides
/// the large title, so the bar stays clear there.
private struct PaperBarBackground: ViewModifier {
    var colors: DayruleColors

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
        } else {
            content
                .toolbarBackground(colors.bg, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}
#endif

/// Mac page title: Fraunces over a 2pt ink rule (the toolbar title is removed).
struct DayrulePageTitle: View {
    let title: String
    @Environment(\.colorScheme) private var colorScheme

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme)
        DayrulePageTitleChrome {
            Text(title)
                .font(DayruleType.pageTitle)
                .tracking(DayruleType.titleTracking)
                .foregroundStyle(colors.text)
                .accessibilityAddTraits(.isHeader)
        }
    }
}

/// Area / project heading: the page title *is* the rename field (web ListShell).
struct DayruleEditablePageTitle: View {
    @Binding var text: String
    var prompt: String
    var accessibilityLabel: String
    var identifier: String
    var focused: FocusState<Bool>.Binding
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme)
        DayrulePageTitleChrome {
            TextField(
                "",
                text: $text,
                prompt: Text(prompt).foregroundStyle(colors.textSecondary)
            )
            .font(DayruleType.pageTitle)
            .tracking(DayruleType.titleTracking)
            .dayruleBareField(colors: colors)
            .focused(focused)
            .dayruleClearFieldEditor(isFocused: focused.wrappedValue)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier(identifier)
        }
    }
}

private struct DayrulePageTitleChrome<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dayruleReadingMargin) private var readingMargin

    var body: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme)
        VStack(alignment: .leading, spacing: 0) {
            content
                .padding(.bottom, Tokens.Space.s)
            colors.text.frame(height: Tokens.Space.xxs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Tokens.rowInset + readingMargin)
        .padding(.top, Tokens.Space.m)
        .padding(.bottom, Tokens.Space.s)
    }
}

private struct DayrulePageTitleModifier: ViewModifier {
    let title: String
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        #if os(macOS)
        content.safeAreaInset(edge: .top, spacing: 0) {
            DayrulePageTitle(title)
                .background(DayruleColors.resolve(colorScheme: colorScheme).bg)
        }
        #else
        content
        #endif
    }
}

private struct DayruleEditablePageTitleModifier: ViewModifier {
    @Binding var text: String
    var prompt: String
    var accessibilityLabel: String
    var identifier: String
    var focused: FocusState<Bool>.Binding
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            #if os(iOS)
            // List chrome sets large titles; the editable heading replaces that slot.
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(removing: .title)
            #endif
            .safeAreaInset(edge: .top, spacing: 0) {
                DayruleEditablePageTitle(
                    text: $text,
                    prompt: prompt,
                    accessibilityLabel: accessibilityLabel,
                    identifier: identifier,
                    focused: focused
                )
                .background(DayruleColors.resolve(colorScheme: colorScheme).bg)
            }
    }
}

extension View {
    func dayruleListNavChrome(colors: DayruleColors) -> some View {
        modifier(DayruleListNavChrome(colors: colors))
    }

    /// macOS: Fraunces page title inset above the content. iOS: no-op (nav bar shows it).
    func dayrulePageTitle(_ title: String) -> some View {
        modifier(DayrulePageTitleModifier(title: title))
    }

    /// Fraunces page title is the rename field (web ListShell). Suppresses the
    /// large nav title on iOS so the name is not drawn twice.
    func dayruleEditablePageTitle(
        text: Binding<String>,
        prompt: String,
        accessibilityLabel: String,
        identifier: String,
        focused: FocusState<Bool>.Binding
    ) -> some View {
        modifier(
            DayruleEditablePageTitleModifier(
                text: text,
                prompt: prompt,
                accessibilityLabel: accessibilityLabel,
                identifier: identifier,
                focused: focused
            )
        )
    }
}
