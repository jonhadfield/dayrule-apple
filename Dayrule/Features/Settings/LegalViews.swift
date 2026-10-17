import SwiftUI

/// In-app Privacy and Terms (same plain English as web legal pages, M6).
enum LegalDocument: String, Identifiable {
    case privacy
    case terms

    var id: String { rawValue }

    var title: String {
        switch self {
        case .privacy: "Privacy"
        case .terms: "Terms"
        }
    }
}

struct LegalDocumentView: View {
    let document: LegalDocument
    /// Pushed inside Settings' stack: no own NavigationStack or Done.
    var embedded = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL

    /// Last material change to both documents (matches the web legal pages).
    private static let lastUpdated: Date = {
        var parts = DateComponents(year: 2026, month: 10, day: 17, hour: 12)
        parts.calendar = Calendar(identifier: .gregorian)
        return parts.date ?? Date(timeIntervalSince1970: 0)
    }()

    var body: some View {
        if embedded {
            content
                .settingsPushedPage(title: document.title)
        } else {
            DayruleSheet(
                title: document.title,
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
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Last updated \(Self.lastUpdated.formatted(.dateTime.day().month(.wide).year()))")
                    .font(.footnote)
                    .foregroundStyle(colors.textSecondary)
                switch document {
                case .privacy: privacyBody(colors: colors)
                case .terms: termsBody(colors: colors)
                }
            }
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(20)
        }
        .background(colors.bg)
    }

    @ViewBuilder
    private func privacyBody(colors: DayruleColors) -> some View {
        para("Dayrule is built so that we can’t read your to-dos. They’re encrypted on your devices with a key made from your password before anything is sent, and only your devices can decrypt them. This notice explains the little we can see, why, and who else is involved.")

        heading("Who we are")
        para("Dayrule is a to-do app operated from the United Kingdom. For privacy questions, contact privacy@dayrule.app.")
        Button("privacy@dayrule.app") {
            if let u = URL(string: "mailto:privacy@dayrule.app") { openURL(u) }
        }
        .buttonStyle(.dayruleLink)

        heading("What we can’t see")
        para("Everything you write in Dayrule — titles, notes, checklists, tags, projects, areas, dates, repeats and settings — is end-to-end encrypted. We store it, but only as ciphertext, and we don’t have the key. We also never receive your password or your recovery phrase.")

        heading("What we can see, and why")
        bullet("Your email address — to sign you in and send you sign-up and email-change codes, and reminder emails if you turn those on.")
        bullet("Account records — a hash that lets us check your password without knowing it, your encryption key in a form only your password or recovery phrase can unlock, and your settings for reminders.")
        bullet("Signed-in devices — a label such as “Safari on iOS” or “Dayrule on iPhone”, when each was last used, and its IP address in our hosting provider’s logs, so you can see and sign out your devices and so we can keep the service secure.")
        bullet("How much you store and when you sync — the number and size of your encrypted records (to apply storage limits) and when your devices sync.")
        bullet("Reminder times on the web, only if you turn web reminders on — when each reminder is due, never what it’s for. The native app schedules local notifications on your device instead and does not send reminder contents to the server.")
        para("We use this to provide the service you’ve asked for (the contract between us) and, for security records like IP addresses and rate limits, our legitimate interest in keeping Dayrule safe from abuse. We don’t sell data, show ads, or use analytics or tracking.")

        heading("Who else is involved")
        bullet("Vercel hosts the app and the API. The API runs in London. Vercel, Inc. is a US company and its request logs (including IP addresses) are kept for a limited time under its data processing agreement.")
        bullet("Neon runs the database, on AWS in London.")
        bullet("Resend sends our emails, from its EU region. It sees your email address and the emails’ contents, which never include your to-dos.")
        bullet("On the web only: your browser’s push service if you turn on notifications. It delivers a message containing a random id and a time.")

        heading("How long we keep it")
        bullet("Your account and encrypted data: until you delete your account.")
        bullet("Deleting your account removes everything we hold about you straight away, including your email address. Our database provider keeps a rolling six hours of history for recovery, after which it is gone from there too.")
        bullet("Signed-in sessions: 30 days from last use.")
        bullet("Email codes: deleted within a day. Web reminder times: deleted two days after they’re due.")
        bullet("Records of deleted items, kept so your devices stay in step: 90 days, encrypted.")

        heading("On this device")
        para("This app keeps a session token and device unlock material in the Keychain, and your encrypted vault in local storage so Dayrule works offline. Local reminder notifications, if you turn them on, are scheduled by the OS on this device. Showing to-do titles in those notifications is optional — when on, the OS stores that text. There are no analytics, advertising or third-party trackers.")

        heading("Your rights")
        para("You can export your data in the app (Settings → Your data) and delete your account there (Settings → Delete account), which removes it on our servers and on this device. Because we can’t decrypt your to-dos, the export in the app is the only way to get them in readable form. You can also ask us about anything we hold, ask us to correct or delete it, or object to how we use it, by writing to the address above. If you’re unhappy with our answer, you can complain to the UK Information Commissioner’s Office at ico.org.uk.")
        Button("ico.org.uk") {
            if let u = URL(string: "https://ico.org.uk") { openURL(u) }
        }
        .buttonStyle(.dayruleLink)

        heading("Children")
        para("Dayrule isn’t meant for children under 13.")

        heading("Changes")
        para("If this notice changes in a way that matters, we’ll tell you in the app before it takes effect. The date at the top shows the last change.")
    }

    @ViewBuilder
    private func termsBody(colors: DayruleColors) -> some View {
        para("These are the terms for using Dayrule, a to-do app operated from the United Kingdom (contact: privacy@dayrule.app). By creating an account you agree to them.")
        Button("privacy@dayrule.app") {
            if let u = URL(string: "mailto:privacy@dayrule.app") { openURL(u) }
        }
        .buttonStyle(.dayruleLink)

        heading("The service")
        para("Dayrule is free. It’s provided as it is, without guarantees that it will always be available or free of faults, though we’ll do our best to keep it running and your data safe. We may change or stop the service; if we plan to stop it, we’ll give you notice and time to export your data.")

        heading("Your password and recovery phrase")
        para("Your to-dos are encrypted with a key made from your password, and we don’t have it. If you forget your password, only your 24-word recovery phrase can get you back in. If you lose both, nobody — including us — can recover your data. Keep the recovery phrase somewhere safe, and keep your devices secure.")

        heading("Using Dayrule fairly")
        bullet("Use it for lawful purposes, and only with an account that’s yours.")
        bullet("Don’t try to break, overload or get around its security or limits, or access other people’s accounts.")
        bullet("Accounts have storage limits (currently 50 MB and 100,000 items).")
        para("We can suspend or close an account that’s being used to abuse the service, and will tell you why where we can.")

        heading("Your data")
        para("What you write is yours. You can export it or delete your account at any time. The privacy notice explains what we can and can’t see.")

        heading("Liability")
        para("As far as the law allows, we’re not liable for indirect losses, or for losses caused by data you can’t decrypt because the password and recovery phrase were lost. Nothing in these terms limits liability that can’t be limited by law, or your statutory rights as a consumer.")

        heading("Changes and law")
        para("If these terms change in a way that matters, we’ll tell you in the app before it takes effect. These terms are governed by the law of England and Wales.")
    }

    private func heading(_ text: String) -> some View {
        Text(text)
            .font(DayruleType.sectionSerif)
            .foregroundStyle(DayruleColors.resolve(colorScheme: colorScheme).text)
            .accessibilityAddTraits(.isHeader)
            .padding(.top, 8)
    }

    private func para(_ text: String) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(DayruleColors.resolve(colorScheme: colorScheme).text)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.body)
        .foregroundStyle(DayruleColors.resolve(colorScheme: colorScheme).text)
    }
}
