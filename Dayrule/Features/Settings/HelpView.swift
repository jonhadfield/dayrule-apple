import SwiftUI

/// Short in-app Help with links to the public site (M5). Full Privacy / Terms
/// copy lands with M6; here we open the same URLs in Safari.
struct HelpView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL

    var body: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme)
        NavigationStack {
            List {
                Section {
                    Text("Dayrule keeps your lists encrypted on your devices. The server stores ciphertext only.")
                        .foregroundStyle(colors.textSecondary)
                }
                Section("On this device") {
                    labeled("Lists", "Inbox, Today, Scheduled, Backlog, Not now, Done, Trash.")
                    labeled("Find", "Quick Find searches unlocked data on this device.")
                    labeled("Export", "Settings → Your data. Exports are plaintext — keep them safe.")
                }
                Section("On the web") {
                    linkRow("Help articles", url: "https://dayrule.app/help")
                    linkRow("Privacy", url: "https://dayrule.app/privacy")
                    linkRow("Terms", url: "https://dayrule.app/terms")
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
