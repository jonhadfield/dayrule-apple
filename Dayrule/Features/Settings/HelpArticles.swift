import SwiftUI

/// Offline help articles — plain English from web `features/help/articles.tsx`,
/// adapted where native chrome differs (Settings paths, Add row, Mac menus).
struct HelpArticleView: View {
    let topic: HelpTopic
    var embedded = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if embedded {
            article
                .settingsPushedPage(title: topic.title)
        } else {
            DayruleSheet(
                title: topic.title,
                dismissTitle: "Done",
                dismissPlacement: .confirmationAction,
                size: .reading
            ) {
                article
            }
        }
    }

    private var article: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme)
        return ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.l) {
                switch topic {
                case .start: start(colors)
                case .lists: lists(colors)
                case .scheduling: scheduling(colors)
                case .projects: projects(colors)
                case .devices: devices(colors)
                case .privacy: privacy(colors)
                case .shortcuts: shortcuts(colors)
                case .data: data(colors)
                }
            }
            .frame(maxWidth: Tokens.readingMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(20)
        }
        .background(colors.bg)
        .accessibilityIdentifier("help.article.\(topic.rawValue)")
    }

    // MARK: - Topics

    @ViewBuilder
    private func start(_ colors: DayruleColors) -> some View {
        para(
            "Dayrule keeps your to-dos in a few lists. You write things down as they come to you, then decide when to do them. Each day, Today shows what’s on.",
            colors
        )
        diagram(
            caption: "The life of a to-do.",
            description: "A new to-do goes into the Inbox. From there you send it to Today, Scheduled for a date, or the Backlog. When you complete it, it goes to Done.",
            colors: colors
        ) {
            flowRow([
                ("Add", colors.accent, colors.bg),
                ("Inbox", colors.text, colors.bg),
            ], colors: colors)
            flowRow([
                ("Today", colors.today, colors.bg),
                ("Scheduled", colors.scheduled, colors.bg),
                ("Backlog", colors.ready, colors.bg),
                ("Done", colors.done, colors.bg),
            ], colors: colors)
        }
        heading("Add a to-do", colors)
        numbered([
            "Press Add at the bottom of a list (the paper + row).",
            "Type what needs doing. Add notes underneath if you like.",
            "Press Return or leave the field. An empty new to-do is thrown away.",
        ], colors)
        para("A to-do lands in the list you added it from: add it in Today and it’s for today. On Scheduled, Add files for tomorrow.", colors)
        heading("Sort your Inbox", colors)
        para(
            "To-dos you add in the Inbox wait there until you decide. Open one and choose When: Today, a date, Backlog or Not now. Or Move it into a project.",
            colors
        )
        heading("Get it done", colors)
        para("Tick the circle to complete a to-do. It stays in its list for a moment, then moves to Done.", colors)
        tip("Not sure where something belongs? Leave it in the Inbox and sort it later.", colors)
    }

    @ViewBuilder
    private func lists(_ colors: DayruleColors) -> some View {
        para(
            "Every to-do shows in one list at a time. Which one depends on what you’ve told Dayrule about it.",
            colors
        )
        diagram(
            caption: "Which list a to-do shows in, checked from top to bottom.",
            description: "Completed to-dos are in Done. Otherwise, if you set it to Not now, it's in the Not now section of the Backlog. If it's for today or due today, it's in Today. If it has a later date, it's in Scheduled. If it's sorted but has no date, it's in the Backlog. If you haven't sorted it yet, it's in the Inbox.",
            colors: colors
        ) {
            decisionRow("Completed?", "Done", colors.done, colors)
            decisionRow("Set to Not now?", "Not now", colors.later, colors)
            decisionRow("For today, or due today?", "Today", colors.today, colors)
            decisionRow("Has a later date?", "Scheduled", colors.scheduled, colors)
            decisionRow("Sorted, no date?", "Backlog", colors.ready, colors)
            Text("no to all → Inbox")
                .font(DayruleType.meta)
                .foregroundStyle(colors.textSecondary)
                .padding(.top, Tokens.Space.xs)
        }
        heading("The lists", colors)
        definitionList([
            ("Inbox", "New to-dos you haven’t sorted yet."),
            ("Today", "Anything for today: started today or earlier, or due today."),
            ("Scheduled", "To-dos with a date in the future, by day for the next week, then by month."),
            ("Backlog", "To-dos you could do any time, grouped by project and area. At the end, Not now holds ideas and maybes you don’t want to think about yet."),
            ("Done", "Everything you’ve completed, newest first."),
            ("Trash", "Deleted to-dos and projects, until you empty it."),
        ], colors)
        para(
            "On a phone the tabs are Inbox · Today · Scheduled · Browse. Browse holds Backlog, Done, Trash, projects and areas. New List creates a project or an area. On iPad and Mac the same lists sit in the sidebar.",
            colors
        )
        para(
            "Your projects and areas appear there too. Their to-dos also show in Today, Scheduled and Backlog when they fit there.",
            colors
        )
        heading("Tags", colors)
        para(
            "Give to-dos tags such as “Errand” or “Phone”. Open a to-do and choose Tags…",
            colors
        )
    }

    @ViewBuilder
    private func scheduling(_ colors: DayruleColors) -> some View {
        para(
            "A to-do can have a start date (when to do it), a deadline (when it must be done), or both.",
            colors
        )
        diagram(
            caption: "Start dates move a to-do into Today on the day. Deadlines warn you.",
            description: "A to-do with today's date is in Today. One with a later date waits in Scheduled and moves to Today on that day. A deadline is shown with a flag, and the to-do appears in Today on its deadline even if you didn't schedule it.",
            colors: colors
        ) {
            flowRow([
                ("Today", colors.today, colors.bg),
                ("Scheduled", colors.scheduled, colors.bg),
                ("Deadline", colors.deadline, colors.bg),
            ], colors: colors)
        }
        heading("When", colors)
        para("Open a to-do and choose When:", colors)
        bullets([
            ("Today", "it shows in Today now."),
            ("A date", "it waits in Scheduled and appears in Today on that date."),
            ("Backlog", "no date, do it when you can."),
            ("Not now", "at the end of the Backlog, out of the way until you choose otherwise."),
        ], colors)
        para(
            "You can also type in the When sheet: tom, fri, next week, in 3 days or a date such as 10/20. Dates are shown year first, like 2026/10/20.",
            colors
        )
        heading("Deadlines", colors)
        para(
            "A deadline puts a flag on the to-do. On the day it’s due, it appears in Today even if you didn’t schedule it, and it turns red if it’s late.",
            colors
        )
        heading("Repeating to-dos", colors)
        para(
            "Choose Repeat in a to-do: daily, weekly on the days you pick, monthly or yearly, every so many days, weeks, months or years.",
            colors
        )
        bullets([
            ("On a schedule", "a new copy appears on each date, like “every Monday”."),
            ("After I complete the last one", "the next copy is due a set time after you finish the last, like “3 weeks after my last haircut”."),
        ], colors)
        para(
            "The repeating to-do itself lives in Scheduled at its next date. Open it there to change it, or to stop it repeating. If you’re away for a while, you get one copy for the latest date, not one for every day you missed.",
            colors
        )
        heading("Reminders", colors)
        para(
            "Choose Reminder in a to-do to be reminded at a time: on the hour, or at quarter past, half past or quarter to. Turn reminders on first in Settings → Reminders. Reminders are local notifications on this device; the server never sees what they’re for.",
            colors
        )
    }

    @ViewBuilder
    private func projects(_ colors: DayruleColors) -> some View {
        para(
            "A project is a piece of work made of several to-dos, with an end, like “Paint the kitchen”. An area is a part of your life with no end, like “Home” or “Work”, that holds projects and to-dos.",
            colors
        )
        diagram(
            caption: "Areas hold projects. Projects can be split with headings.",
            description: "An area called Home contains a project called Paint the kitchen and a loose to-do. The project is split into headings with their own to-dos.",
            colors: colors
        ) {
            VStack(alignment: .leading, spacing: Tokens.Space.s) {
                Text("Area: Home")
                    .font(DayruleType.sectionSerif)
                    .foregroundStyle(colors.text)
                Text("Project: Paint the kitchen")
                    .font(DayruleType.meta.weight(.semibold))
                    .foregroundStyle(colors.text)
                    .padding(.leading, Tokens.Space.m)
                Text("Headings · Buy / Do — with to-dos under each")
                    .font(DayruleType.meta)
                    .foregroundStyle(colors.textSecondary)
                    .padding(.leading, Tokens.Space.l)
                Text("Loose to-do in the area (no project)")
                    .font(DayruleType.meta)
                    .foregroundStyle(colors.textSecondary)
                    .padding(.leading, Tokens.Space.m)
            }
        }
        heading("Make one", colors)
        para(
            "Create projects and areas from Browse (or the sidebar on iPad and Mac). Open a project or area and use Add for to-dos inside it.",
            colors
        )
        heading("Headings", colors)
        para(
            "In a project, add headings to split it into stages. Move to-dos under the heading they belong to.",
            colors
        )
        heading("Finishing", colors)
        para(
            "The progress next to a project fills in as you complete its to-dos. Complete the project itself and everything left in it is completed too.",
            colors
        )
        tip(
            "Move a to-do into a project with Move… on the to-do. Or Convert to Project from the to-do menu — checklist steps become to-dos in the new project. A project’s ··· menu can Convert to To-Do the other way.",
            colors
        )
    }

    @ViewBuilder
    private func devices(_ colors: DayruleColors) -> some View {
        para(
            "Use Dayrule on as many phones and computers as you like. Sign in with the same email and password and your to-dos follow you.",
            colors
        )
        diagram(
            caption: "Changes are locked on your device, passed through the server, and unlocked on your other devices.",
            description: "Your phone and your computer each lock your to-dos with your key before sending them. The Dayrule server stores and passes on the locked copies, but cannot open them. Each device unlocks them with your key.",
            colors: colors
        ) {
            flowRow([
                ("Your devices", colors.text, colors.bg),
                ("Server", colors.textSecondary, colors.sidebar),
                ("Your other devices", colors.text, colors.bg),
            ], colors: colors)
            Text("only locked copies · no key on the server")
                .font(DayruleType.meta)
                .foregroundStyle(colors.textSecondary)
        }
        heading("Sync", colors)
        para(
            "Changes sync on their own when you’re online. Settings shows when it last synced, and if you need to sign in again to sync.",
            colors
        )
        heading("Offline", colors)
        para(
            "Dayrule works without a connection. Everything you change is saved on your device and sent when you’re back online. If you change the same to-do on two devices while offline, each change is kept where it doesn’t clash; where it does, the most recent wins.",
            colors
        )
        heading("This app and the website", colors)
        para(
            "You’re using the native Dayrule app. The website at dayrule.app works the same lists and encryption, and syncs with this app. Help on the website also works offline once you’ve opened it there.",
            colors
        )
        heading("Locking", colors)
        para(
            "Dayrule locks itself after 15 minutes without use, and when you leave the app, unless you chose Stay unlocked on this device. Only do that on a device that’s yours alone.",
            colors
        )
    }

    @ViewBuilder
    private func privacy(_ colors: DayruleColors) -> some View {
        para(
            "Your to-dos are encrypted on your device before they’re sent. Your password makes the key that opens them. We never have your password or your key, so we can’t read your to-dos — and we can’t open them for you either.",
            colors
        )
        diagram(
            caption: "Two ways in: your password, or your recovery phrase. Keep at least one.",
            description: "Your password opens your account key. Your 24-word recovery phrase also opens your account key. The account key opens your to-dos. If you lose both the password and the recovery phrase, nobody can open them.",
            colors: colors
        ) {
            flowRow([
                ("Password", colors.text, colors.bg),
                ("Account key", colors.accent, colors.bg),
                ("Your to-dos", colors.ready, colors.bg),
            ], colors: colors)
            Text("Recovery phrase (24 words) also opens the account key")
                .font(DayruleType.meta)
                .foregroundStyle(colors.textSecondary)
        }
        heading("Your recovery phrase", colors)
        para(
            "When you create your account, Dayrule shows 24 words. They’re the only way back in if you forget your password. Write them down and keep them somewhere safe, away from your devices.",
            colors
        )
        tip(
            "If you lose your password and your recovery phrase, your to-dos can’t be recovered — by you, by us, or by anyone.",
            colors
        )
        heading("Forgot your password?", colors)
        para(
            "On the sign-in screen, choose Forgot password?, enter your 24 words, and set a new password.",
            colors
        )
        heading("Unlock on this device", colors)
        para(
            "Settings lets you unlock with biometrics or a device passkey instead of typing your password every time. Your password still works. A sign-in passkey on the account is a second step after password — different from unlock on this device.",
            colors
        )
        heading("What we can see", colors)
        para(
            "Your email address, how much you store, when your devices sync, and — only if you turn reminders on — that a reminder is due. Never what you’ve written. Privacy under Help → Legal has the details.",
            colors
        )
    }

    @ViewBuilder
    private func shortcuts(_ colors: DayruleColors) -> some View {
        heading("On a phone", colors)
        diagram(
            caption: "Swipes on a phone.",
            description: "Swipe a to-do to the right to choose When. Swipe it to the left to start selecting several to-dos.",
            colors: colors
        ) {
            VStack(alignment: .leading, spacing: Tokens.Space.s) {
                Text("Swipe right → When")
                    .font(DayruleType.meta)
                    .foregroundStyle(colors.text)
                Text("Swipe left → Select")
                    .font(DayruleType.meta)
                    .foregroundStyle(colors.text)
                Text("While selecting, tap more to-dos, then use the bar at the bottom.")
                    .font(DayruleType.meta)
                    .foregroundStyle(colors.textSecondary)
            }
        }
        numbered([
            "Tap a to-do to open it. Save or Cancel to close it.",
            "Swipe right to choose When; swipe left to select. While selecting, tap more to-dos, then use the bar.",
            "Press and hold a to-do for the menu (When, Move, Complete, Trash, and more).",
        ], colors)
        heading("On a Mac", colors)
        para(
            "Click a to-do to open it. Right-click (or Control-click) for the same menu as a long-press on a phone. Select from the menu or swipe to select several, then use the selection bar. Right-click a project or area in the sidebar to Complete or Move to Trash without opening it.",
            colors
        )
        definitionList([
            ("Settings…", "⌘,"),
            ("Lock", "⇧⌘L"),
            ("Find…", "⌘F"),
            ("Undo / Redo", "⌘Z / ⇧⌘Z"),
            ("Move to Trash", "⌫"),
            ("New Project", "⌥⌘N"),
            ("New Area", "⌥⌘A"),
        ], colors)
        tip(
            "Select one or more to-dos first for Move to Trash. New Project opens under the area you’re viewing when you’re in one.",
            colors
        )
    }

    @ViewBuilder
    private func data(_ colors: DayruleColors) -> some View {
        diagram(
            caption: "From Done to gone.",
            description: "A completed to-do goes to Done. From Done you can move it to Trash. Emptying the Trash deletes it for good. You can restore things from Trash until then.",
            colors: colors
        ) {
            flowRow([
                ("Done", colors.done, colors.bg),
                ("Trash", colors.textSecondary, colors.bg),
                ("Gone", colors.text, colors.bg),
            ], colors: colors)
        }
        heading("Done", colors)
        para(
            "Completed to-dos move to Done. Choose when in Settings → Move completed items to Done: immediately, at the end of the day, or when you press Move to Done now in Done.",
            colors
        )
        heading("Deleting", colors)
        numbered([
            "Open a to-do and choose Trash, or use Trash on the context menu / selection bar.",
            "To remove a project, open it and choose Move to Trash from the ··· menu, or right-click / long-press it in the sidebar or Browse. Areas have Trash in the toolbar or the same sidebar menu.",
            "This works anywhere, including in Done.",
            "Anything in Trash can be restored. In Trash, Empty Trash deletes them for good.",
        ], colors)
        heading("Export and import", colors)
        para(
            "Settings → Your data. Export JSON saves everything in a file you can import again; Export Markdown saves a readable outline. Exports aren’t encrypted, so keep them safe. Import adds a copy of a Dayrule export (or a Things 3 file from things-export) and never replaces what’s there.",
            colors
        )
        heading("Import from Things 3", colors)
        para(
            "On a Mac with Things 3, run the read-only exporter in the Dayrule web repo (tools/things-export) to write a JSON file, then Import… here. Mapping happens on this device; day / week / month / year repeats come across when Things encoded them.",
            colors
        )
        heading("Delete your account", colors)
        para(
            "Settings → Delete account. It deletes everything we hold, straight away, and can’t be undone. Export first if you want a copy. This device is wiped too.",
            colors
        )
    }

    // MARK: - Prose helpers

    private func para(_ text: String, _ colors: DayruleColors) -> some View {
        Text(text)
            .font(DayruleType.rowTitle)
            .foregroundStyle(colors.text)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func heading(_ text: String, _ colors: DayruleColors) -> some View {
        Text(text)
            .font(DayruleType.sectionSerif)
            .foregroundStyle(colors.text)
            .padding(.top, Tokens.Space.s)
            .accessibilityAddTraits(.isHeader)
    }

    private func tip(_ text: String, _ colors: DayruleColors) -> some View {
        Text(text)
            .font(DayruleType.meta)
            .foregroundStyle(colors.text)
            .padding(Tokens.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(colors.sidebar.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusCard, style: .continuous))
            .overlay(alignment: .leading) {
                colors.accent.frame(width: 3)
            }
            .accessibilityLabel("Tip. \(text)")
    }

    private func numbered(_ items: [String], _ colors: DayruleColors) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                HStack(alignment: .top, spacing: Tokens.Space.s) {
                    Text("\(i + 1).")
                        .font(DayruleType.meta.monospacedDigit())
                        .foregroundStyle(colors.textSecondary)
                        .frame(width: 20, alignment: .trailing)
                    Text(item)
                        .font(DayruleType.rowTitle)
                        .foregroundStyle(colors.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func bullets(_ items: [(String, String)], _ colors: DayruleColors) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                (Text(item.0).fontWeight(.semibold) + Text(" — \(item.1)"))
                    .font(DayruleType.rowTitle)
                    .foregroundStyle(colors.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func definitionList(_ items: [(String, String)], _ colors: DayruleColors) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                HStack(alignment: .top, spacing: Tokens.Space.m) {
                    Text(item.0)
                        .font(DayruleType.meta.weight(.semibold))
                        .foregroundStyle(colors.text)
                        .frame(width: 88, alignment: .leading)
                    Text(item.1)
                        .font(DayruleType.meta)
                        .foregroundStyle(colors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, Tokens.Space.s)
                if i < items.count - 1 {
                    colors.hairline.frame(height: 1)
                }
            }
        }
        .overlay(alignment: .top) { colors.hairline.frame(height: 1) }
        .overlay(alignment: .bottom) { colors.hairline.frame(height: 1) }
    }

    private func diagram<Content: View>(
        caption: String,
        description: String,
        colors: DayruleColors,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            content()
                .padding(Tokens.Space.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(colors.sidebar.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusCard, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Tokens.radiusCard, style: .continuous)
                        .strokeBorder(colors.hairline, lineWidth: 1)
                )
                .accessibilityElement(children: .combine)
                .accessibilityLabel(description)
            Text(caption)
                .font(DayruleType.meta)
                .foregroundStyle(colors.textSecondary)
        }
    }

    private func flowRow(_ items: [(String, Color, Color)], colors: DayruleColors) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Tokens.Space.s) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    if i > 0 {
                        Image(systemName: "arrow.right")
                            .font(.caption)
                            .foregroundStyle(colors.textSecondary)
                    }
                    chip(item.0, stroke: item.1, fill: item.2, colors: colors)
                }
            }
            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    chip(item.0, stroke: item.1, fill: item.2, colors: colors)
                }
            }
        }
    }

    private func decisionRow(_ question: String, _ answer: String, _ tone: Color, _ colors: DayruleColors) -> some View {
        HStack(spacing: Tokens.Space.s) {
            Text(question)
                .font(DayruleType.meta)
                .foregroundStyle(colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "arrow.right")
                .font(.caption2)
                .foregroundStyle(colors.textSecondary)
            chip(answer, stroke: tone, fill: colors.bg, colors: colors)
        }
    }

    private func chip(_ label: String, stroke: Color, fill: Color, colors: DayruleColors) -> some View {
        Text(label)
            .font(DayruleType.meta.weight(.semibold))
            .foregroundStyle(stroke)
            .padding(.horizontal, Tokens.Space.s)
            .padding(.vertical, Tokens.Space.xs)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusRow, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.radiusRow, style: .continuous)
                    .strokeBorder(stroke, lineWidth: 1.5)
            )
    }
}
