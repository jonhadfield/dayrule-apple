import SwiftUI

/// Help plus in-app Privacy / Terms (M6).
struct HelpView: View {
    /// Pushed inside Settings' stack: no own NavigationStack or Done.
    var embedded = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL

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
                Text("Dayrule keeps your lists encrypted on your devices. The server stores ciphertext only.")
                    .foregroundStyle(colors.textSecondary)
            }
            .dayruleSheetRow(colors: colors)
            Section {
                labeled("Lists", "Inbox (unsorted), Today, Scheduled, Backlog with Not now, Done, Trash. On phone: Inbox · Today · Scheduled · Browse.")
                labeled("When", "Today, a date, Backlog, Not now, Inbox, or Clear.")
                labeled("Find", "Quick Find searches unlocked data on this device.")
                labeled("Export", "Settings → Your data. Exports are plaintext — keep them safe.")
                labeled("Reminders", "Settings → Reminders. Local notifications; the server never sees what they’re for.")
                labeled("Unlock", "Password, biometrics, or a device passkey (PRF). A sign-in passkey on the account is a second step after password — different from device unlock. Stay unlocked is less locked.")
                labeled("Delete account", "Settings → Delete account. Removes the account on the server and wipes this device.")
            } header: {
                DayruleSectionHeader(title: "On this device")
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
                DayruleSectionHeader(title: "Legal")
            }
            .dayruleSheetRow(colors: colors)
            Section {
                linkRow("Help articles", url: "https://dayrule.app/help")
            } header: {
                DayruleSectionHeader(title: "On the web")
            }
            .dayruleSheetRow(colors: colors)
        }
        .listStyle(.plain)
    }

    private func labeled(_ title: String, _ body: String) -> some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme)
        return VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .foregroundStyle(colors.text)
            Text(body)
                .font(.footnote)
                .foregroundStyle(colors.textSecondary)
        }
    }

    private func linkRow(_ title: String, url: String) -> some View {
        Button(title) {
            if let u = URL(string: url) { openURL(u) }
        }
        .buttonStyle(.dayruleLink)
        .accessibilityIdentifier("help.link.\(title)")
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
