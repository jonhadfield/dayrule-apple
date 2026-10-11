import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Paper nav chrome: Fraunces large titles, cream bar, no hairline shadow (PLAN §6.2).
struct DayruleListNavChrome: ViewModifier {
    var colors: DayruleColors

    func body(content: Content) -> some View {
        content
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(colors.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .onAppear { Self.apply(colors: colors) }
            #endif
    }

    #if canImport(UIKit)
    private static func apply(colors: DayruleColors) {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(colors.bg)
        appearance.shadowColor = .clear
        let large =
            UIFont(name: DayruleFont.serifFamily, size: 34)
            ?? .systemFont(ofSize: 34, weight: .semibold)
        let inline =
            UIFont(name: DayruleFont.serifFamily, size: 17)
            ?? .systemFont(ofSize: 17, weight: .semibold)
        let ink = UIColor(colors.text)
        appearance.largeTitleTextAttributes = [.font: large, .foregroundColor: ink]
        appearance.titleTextAttributes = [.font: inline, .foregroundColor: ink]
        let nav = UINavigationBar.appearance()
        nav.standardAppearance = appearance
        nav.scrollEdgeAppearance = appearance
        nav.compactAppearance = appearance
    }
    #endif
}

extension View {
    func dayruleListNavChrome(colors: DayruleColors) -> some View {
        modifier(DayruleListNavChrome(colors: colors))
    }
}
