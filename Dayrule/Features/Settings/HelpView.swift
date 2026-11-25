import SwiftUI

/// Help index: bundled articles (offline) plus Privacy / Terms.
struct HelpView: View {
    /// Pushed inside Settings' stack: no own NavigationStack or Done.
    var embedded = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if embedded {
            content
                .settingsPushedPage(title: "Help")
        } else {
            DayruleSheet(
                title: "Help",
                dismissTitle: "Done",
                dismissPlacement: .confirmationAction,
                size: .reading
            ) {
                content
            }
        }
    }

    private var content: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme)
        return List {
            Section {
                Text("Dayrule keeps your lists encrypted on your devices. The server stores ciphertext only. These articles work offline.")
                    .foregroundStyle(colors.textSecondary)
            }
            .dayruleSheetRow(colors: colors)

            Section {
                ForEach(HelpTopic.allCases) { topic in
                    NavigationLink {
                        HelpArticleView(topic: topic, embedded: true)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(topic.title)
                                .foregroundStyle(colors.text)
                            Text(topic.summary)
                                .font(.footnote)
                                .foregroundStyle(colors.textSecondary)
                        }
                    }
                    .accessibilityIdentifier("help.topic.\(topic.rawValue)")
                }
            } header: {
                DayruleSectionHeader(title: "Articles", surface: .sheet)
            }
            .dayruleSheetRow(colors: colors)

            Section {
                NavigationLink {
                    LegalDocumentView(document: .privacy, embedded: true)
                } label: {
                    Text("Privacy")
                }
                .accessibilityIdentifier("help.privacy")
                NavigationLink {
                    LegalDocumentView(document: .terms, embedded: true)
                } label: {
                    Text("Terms")
                }
                .accessibilityIdentifier("help.terms")
            } header: {
                DayruleSectionHeader(title: "Legal", surface: .sheet)
            }
            .dayruleSheetRow(colors: colors)
        }
        .listStyle(.plain)
        .dayrulePaperList(macScrollFill: colors.bg)
        #if os(iOS)
        .listSectionSpacing(Tokens.Space.m)
        #endif
    }
}

extension View {
    /// Chrome for a page pushed inside a `DayruleSheet` stack (Help, Legal): paper
    /// background, inline title on iOS, the Fraunces sheet header on macOS.
    func settingsPushedPage(title: String) -> some View {
        modifier(SettingsPushedPage(title: title))
    }
}

private struct SettingsPushedPage: ViewModifier {
    let title: String
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme)
        content
            .scrollContentBackground(.hidden)
            .background(colors.bg)
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(colors.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            #elseif os(macOS)
            .safeAreaInset(edge: .top, spacing: 0) {
                DayruleSheetHeader(title: title)
            }
            #endif
    }
}
