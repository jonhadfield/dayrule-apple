import SwiftUI

/// Help plus in-app Privacy / Terms (M6).
struct HelpView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @State private var legal: LegalDocument?

    var body: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme)
        NavigationStack {
            List {
                Section {
                    Text("Dayrule keeps your lists encrypted on your devices. The server stores ciphertext only.")
                        .foregroundStyle(colors.textSecondary)
                }
                Section("On this device") {
                    labeled("Lists", "Inbox (unsorted), Today, Scheduled, Backlog (anytime) with Not now, Done, Trash. On phone: Inbox · Today · Scheduled · Browse.")
                    labeled("When", "Today, a date, Backlog, Not now, Inbox, or Clear.")
                    labeled("Find", "Quick Find searches unlocked data on this device.")
                    labeled("Export", "Settings → Your data. Exports are plaintext — keep them safe.")
                    labeled("Reminders", "Settings → Reminders. Local notifications; the server never sees what they’re for.")
                    labeled("Unlock", "Password, biometrics, or a device passkey (PRF). A sign-in passkey on the account is a second step after password — different from device unlock. Stay unlocked is less locked.")
                    labeled("Delete account", "Settings → Delete account. Removes the account on the server and wipes this device.")
                }
                Section("Legal") {
                    Button("Privacy") { legal = .privacy }
                        .foregroundStyle(colors.accent)
                        .accessibilityIdentifier("help.privacy")
                    Button("Terms") { legal = .terms }
                        .foregroundStyle(colors.accent)
                        .accessibilityIdentifier("help.terms")
                }
                Section("On the web") {
                    linkRow("Help articles", url: "https://dayrule.app/help")
                }
            }
            .scrollContentBackground(.hidden)
            .background(colors.bg)
            .navigationTitle("Help")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(colors.accent)
                }
            }
            .sheet(item: $legal) { doc in
                LegalDocumentView(document: doc)
            }
        }
    }

    private func labeled(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
            Text(body)
                .font(.footnote)
                .foregroundStyle(DayruleColors.resolve(colorScheme: colorScheme).textSecondary)
        }
    }

    private func linkRow(_ title: String, url: String) -> some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme)
        return Button(title) {
            if let u = URL(string: url) { openURL(u) }
        }
        .foregroundStyle(colors.accent)
        .accessibilityIdentifier("help.link.\(title)")
    }
}
