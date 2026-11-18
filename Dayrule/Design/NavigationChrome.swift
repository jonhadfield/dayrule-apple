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
            // Clear the unified toolbar so the sidebar’s containerBackground can
            // reach the traffic lights; detail paper fills via ignoresSafeArea.
            .toolbarBackground(.hidden, for: .windowToolbar)
            .background(colors.bg.ignoresSafeArea())
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

/// Page title: Fraunces over one paper hairline, optional list icon (web ListShell).
struct DayrulePageTitle: View {
    let title: String
    var systemImage: String? = nil
    var iconTint: Color? = nil
    @Environment(\.colorScheme) private var colorScheme

    init(_ title: String, systemImage: String? = nil, iconTint: Color? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.iconTint = iconTint
    }

    var body: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme)
        DayrulePageTitleChrome {
            HStack(alignment: .center, spacing: Tokens.Space.m) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 26))
                        .foregroundStyle(iconTint ?? colors.text)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(DayruleType.pageTitle)
                    .tracking(DayruleType.titleTracking)
                    .foregroundStyle(colors.text)
                    .accessibilityAddTraits(.isHeader)
            }
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

    var body: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme)
        // One paper hairline under the title. Hosted via overlay (not
        // `safeAreaInset`) so AppKit does not paint a second rule under the
        // chrome — that stack was the Mac double underline.
        VStack(alignment: .leading, spacing: 0) {
            content
                .padding(.bottom, Tokens.Space.s)
            colors.hairline.frame(height: 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Leading edge of the title = left edge of the checkbox circles below.
        // Overlay chrome sits in the list’s bounds; Mac plain Lists already
        // include the system leading in that origin.
        #if os(macOS)
        .padding(.horizontal, Tokens.Space.m)
        // Dense sidebar rows pad glyphs below the selection wash; match that
        // inset so Fraunces caps line up with Inbox/Today *text*, not the bar.
        .padding(.top, Tokens.Space.s - Tokens.Space.xxs)
        #else
        .padding(.horizontal, Tokens.listChromeInset + Tokens.listMarkCircleLeading)
        .padding(.top, Tokens.Space.m)
        #endif
        .background(colors.bg)
    }
}

/// Mac page title above the list without `safeAreaInset` (avoids the system
/// rule that stacked under our paper hairline).
private struct DayruleMacPageTitleOverlay<Title: View>: ViewModifier {
    @ViewBuilder var title: () -> Title
    @Environment(\.colorScheme) private var colorScheme
    @State private var titleHeight: CGFloat = 56
    func body(content: Content) -> some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme)
        content
            // No lift into the toolbar — cap-height should match sidebar *label*
            // ink (Inbox), not the row wash / window chrome above it.
            .padding(.top, titleHeight)
            // Padding alone is clear — the translucent Mac toolbar then reads as
            // a white bar. Paint paper through the reserved title band.
            .background(colors.bg)
            .overlay(alignment: .top) {
                title()
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { height in
                        if height > 0, abs(height - titleHeight) > 0.5 {
                            titleHeight = height
                        }
                    }
            }
    }
}

/// Toolbar glyph on paper: sidebar fill + secondary ring (not white Liquid Glass).
struct DayruleToolbarGlyph: View {
    let systemImage: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme)
        Image(systemName: systemImage)
            .font(.body.weight(.medium))
            .foregroundStyle(colors.text)
            .frame(width: 30, height: 30)
            // `sidebar` is a step darker than page `bg`; ring uses secondary ink
            // so the outline stays visible on cream (hairline was too quiet).
            .background(colors.sidebar, in: Circle())
            .overlay {
                Circle().strokeBorder(colors.textSecondary.opacity(0.45), lineWidth: 1)
            }
            .accessibilityHidden(true)
    }
}

private struct DayrulePageTitleModifier: ViewModifier {
    let title: String
    var systemImage: String?
    var iconTint: Color?

    func body(content: Content) -> some View {
        #if os(macOS)
        content.modifier(DayruleMacPageTitleOverlay {
            DayrulePageTitle(title, systemImage: systemImage, iconTint: iconTint)
        })
        #elseif os(iOS)
        // Match web ListShell (icon + Fraunces); replace the system large title.
        content
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(removing: .title)
            .safeAreaInset(edge: .top, spacing: 0) {
                DayrulePageTitle(title, systemImage: systemImage, iconTint: iconTint)
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

    func body(content: Content) -> some View {
        content
            #if os(iOS)
            // List chrome sets large titles; the editable heading replaces that slot.
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(removing: .title)
            .safeAreaInset(edge: .top, spacing: 0) {
                DayruleEditablePageTitle(
                    text: $text,
                    prompt: prompt,
                    accessibilityLabel: accessibilityLabel,
                    identifier: identifier,
                    focused: focused
                )
            }
            #elseif os(macOS)
            .modifier(DayruleMacPageTitleOverlay {
                DayruleEditablePageTitle(
                    text: $text,
                    prompt: prompt,
                    accessibilityLabel: accessibilityLabel,
                    identifier: identifier,
                    focused: focused
                )
            })
            #endif
    }
}

extension ToolbarContent {
    /// Drops the Liquid Glass shared pill behind a toolbar item (macOS 26+ / iOS 26+).
    @ToolbarContentBuilder
    func dayruleHideToolbarGlass() -> some ToolbarContent {
        if #available(macOS 26.0, iOS 26.0, *) {
            self.sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}

extension View {
    func dayruleListNavChrome(colors: DayruleColors) -> some View {
        modifier(DayruleListNavChrome(colors: colors))
    }

    /// Fraunces page title (Mac overlay / iOS top inset). Optional list icon matches web.
    func dayrulePageTitle(
        _ title: String,
        systemImage: String? = nil,
        iconTint: Color? = nil
    ) -> some View {
        modifier(DayrulePageTitleModifier(title: title, systemImage: systemImage, iconTint: iconTint))
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
