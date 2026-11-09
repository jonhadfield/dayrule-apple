import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

/// Device Settings: sync (M4), Done mode + data export/import + Help (M5).
struct SettingsView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var importError: String?
    @State private var importSummary: String?
    @State private var showImporter = false
    #if os(iOS)
    @State private var shareURL: URL?
    @State private var showShare = false
    #endif
    @State private var remindersOn = DeviceReminderPrefs.enabled
    @State private var showReminderTitles = DeviceReminderPrefs.showTitles
    @State private var reminderError: String?
    @State private var unlockBusy: UnlockMethod?
    @State private var unlockError: UnlockError?
    @State private var confirmingSignOut = false
    @State private var signOutHasPending = false
    @AppStorage("dayrule.appearance") private var appearanceRaw = AppearancePreference.system.rawValue

    private enum UnlockMethod: Equatable {
        case biometric, passkey
    }

    private struct UnlockError: Equatable {
        var method: UnlockMethod
        var message: String
    }

    private var appearanceBinding: Binding<AppearancePreference> {
        Binding(
            get: { AppearancePreference(rawValue: appearanceRaw) ?? .system },
            set: { appearanceRaw = $0.rawValue }
        )
    }

    var body: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme)
        DayruleSheet(
            title: "Settings",
            dismissTitle: "Done",
            dismissPlacement: .confirmationAction,
            size: .reading
        ) {
            List {
                // Paper chrome + quieter chapters (decisions 42, 49, 53) — keep
                // row accessibilityIdentifiers stable for UI tests.
                generalChapter(colors: colors)
                syncUnlockChapter(colors: colors)
                remindersSection(colors: colors)
                dataSection(colors: colors)
                helpChapter(colors: colors)
                if let email = model.accountEmail {
                    accountChapter(email: email, colors: colors)
                }
            }
            .listStyle(.plain)
            #if os(iOS)
            // Chapter breathing room once system double rules are gone (decision 53).
            .listSectionSpacing(Tokens.Space.m)
            #endif
            // Keep Toggle / Picker terracotta, not system blue, on paper.
            .tint(colors.accent)
            .dayruleAnimation(Motion.standard, value: model.entities.settings.moveToDone)
            .dayruleAnimation(Motion.standard, value: unlockError)
            .dayruleAnimation(Motion.standard, value: reminderError)
            .dayruleAnimation(Motion.standard, value: importSummary)
            .dayruleAnimation(Motion.standard, value: importError)
            #if os(iOS)
            .sheet(isPresented: $showShare) {
                if let shareURL {
                    ShareSheet(items: [shareURL])
                }
            }
            #endif
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.json, .plainText],
                allowsMultipleSelection: false
            ) { result in
                importFile(result)
            }
            .confirmationDialog(
                "Sign out of Dayrule?",
                isPresented: $confirmingSignOut,
                titleVisibility: .visible
            ) {
                Button("Sign Out", role: .destructive) { model.signOut() }
                    .accessibilityIdentifier("settings.signOut.confirm")
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(signOutMessage)
            }
        }
    }

    // MARK: - Chapters

    private func generalChapter(colors: DayruleColors) -> some View {
        DayruleFormSection {
            VStack(alignment: .leading, spacing: Tokens.Space.s) {
                Text("Appearance")
                    .foregroundStyle(colors.text)
                AppearanceChips(selection: appearanceBinding, colors: colors)
                    .accessibilityIdentifier("settings.appearance")
            }
            .accessibilityElement(children: .contain)
            Picker(selection: doneModeBinding) {
                Text("Immediately").tag(DoneMode.immediately)
                Text("End of day").tag(DoneMode.daily)
                Text("Manually").tag(DoneMode.manually)
            } label: {
                Text("Move to Done").foregroundStyle(colors.text)
            }
            .accessibilityIdentifier("settings.doneMode")
            if model.entities.settings.moveToDone == .manually {
                Button("Move to Done now") {
                    model.store.run("Move to Done") { d, env in
                        Commands.moveToDoneNow(d, env)
                    }
                    model.noteEntitiesChanged()
                }
                .buttonStyle(.dayruleLink)
                .accessibilityIdentifier("settings.logCompleted")
            }
        } header: {
            DayruleSectionHeader(title: "General")
        } footer: {
            footerText(doneModeFooter, colors: colors)
        }
        .dayruleSheetRow(colors: colors)
    }

    private func syncUnlockChapter(colors: DayruleColors) -> some View {
        DayruleFormSection {
            HStack(spacing: Tokens.Space.s) {
                Text("Sync")
                    .foregroundStyle(colors.text)
                Spacer(minLength: 0)
                SyncStatusView(status: model.syncStatus, needsServerSignIn: model.needsServerSignIn)
            }
            .accessibilityElement(children: .combine)
            if model.needsServerSignIn {
                Button("Sign in to sync") {
                    model.showSignInGate()
                }
                .buttonStyle(.dayruleLink)
                .accessibilityIdentifier("settings.signInToSync")
            }
            Button {
                Task { await model.syncNow() }
            } label: {
                DayruleBusyLabel(title: "Sync now", busyTitle: "Syncing…", busy: model.syncStatus == .syncing)
            }
            .buttonStyle(.dayruleLink)
            .disabled(model.syncStatus == .syncing || model.needsServerSignIn)
            .accessibilityIdentifier("settings.syncNow")
            unlockToggle(
                .biometric,
                title: "Unlock with \(model.biometryLabel)",
                isOn: biometricBinding,
                identifier: "settings.biometric",
                colors: colors
            )
            unlockToggle(
                .passkey,
                title: "Unlock with passkey",
                isOn: passkeyBinding,
                identifier: "settings.passkey",
                colors: colors
            )
        } header: {
            DayruleSectionHeader(title: "Sync & unlock")
        } footer: {
            syncUnlockFooter(colors: colors)
        }
        .dayruleSheetRow(colors: colors)
    }

    @ViewBuilder
    private func syncUnlockFooter(colors: DayruleColors) -> some View {
        let status = model.syncStatus
        let showDetail = status.label != status.shortLabel
        FooterStack {
            if showDetail {
                Text(status.label)
                    .font(DayruleType.helper)
                    .foregroundStyle(status.tone == .deadline ? colors.deadline : colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
            }
            if model.needsServerSignIn {
                footerText(
                    "Unlocked offline — edits stay here until you sign in.",
                    colors: colors
                )
            } else {
                footerText("Unlock methods stay on this device.", colors: colors)
            }
        }
    }

    @ViewBuilder
    private func unlockToggle(
        _ method: UnlockMethod,
        title: String,
        isOn: Binding<Bool>,
        identifier: String,
        colors: DayruleColors
    ) -> some View {
        HStack(spacing: Tokens.Space.s) {
            Toggle(isOn: isOn) {
                Text(title).foregroundStyle(colors.text)
            }
            .accessibilityIdentifier(identifier)
            .disabled(model.phase != .unlocked || unlockBusy != nil)
            if unlockBusy == method {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Working")
            }
        }
        if let unlockError, unlockError.method == method {
            inlineError(unlockError.message, colors: colors)
        }
    }

    private func remindersSection(colors: DayruleColors) -> some View {
        DayruleFormSection {
            Toggle(isOn: $remindersOn) {
                Text("Local reminders").foregroundStyle(colors.text)
            }
            .accessibilityIdentifier("settings.remindersEnabled")
            .onChange(of: remindersOn) { _, on in
                Task { await setRemindersEnabled(on) }
            }
            if let reminderError {
                inlineError(reminderError, colors: colors)
            }
            if remindersOn {
                Toggle(isOn: $showReminderTitles) {
                    Text("Show titles in notifications").foregroundStyle(colors.text)
                }
                .accessibilityIdentifier("settings.reminderTitles")
                .onChange(of: showReminderTitles) { _, on in
                    DeviceReminderPrefs.showTitles = on
                    model.scheduleRemindersIfUnlocked()
                }
            }
        } header: {
            DayruleSectionHeader(title: "Reminders")
        } footer: {
            footerText(
                remindersOn
                    ? "Local to this device. Titles in notifications are stored by the OS."
                    : "Local to this device — not email or browser push.",
                colors: colors
            )
        }
        .dayruleSheetRow(colors: colors)
    }

    private func dataSection(colors: DayruleColors) -> some View {
        DayruleFormSection {
            Button { beginExport(json: true) } label: {
                Label("Export JSON", systemImage: "curlybraces")
            }
            .buttonStyle(.dayruleLink)
            .accessibilityIdentifier("settings.exportJson")
            Button { beginExport(json: false) } label: {
                Label("Export Markdown", systemImage: "doc.plaintext")
            }
            .buttonStyle(.dayruleLink)
            .accessibilityIdentifier("settings.exportMarkdown")
            Button { showImporter = true } label: {
                Label("Import…", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.dayruleLink)
            .accessibilityIdentifier("settings.import")
            if let importSummary {
                Text(importSummary)
                    .font(DayruleType.helper)
                    .foregroundStyle(colors.textSecondary)
                    .transition(.opacity)
            }
            if let importError {
                inlineError(importError, colors: colors)
            }
        } header: {
            DayruleSectionHeader(title: "Your data")
        } footer: {
            footerText(
                "Exports aren’t encrypted. Unlock keys stay on this device.",
                colors: colors
            )
            .accessibilityIdentifier("settings.backupNote")
        }
        .dayruleSheetRow(colors: colors)
    }

    private func helpChapter(colors: DayruleColors) -> some View {
        DayruleFormSection {
            NavigationLink {
                HelpView(embedded: true)
            } label: {
                Text("Help")
            }
            .accessibilityIdentifier("settings.help")
            Text(aboutVersionLine)
                .font(DayruleType.helper)
                .foregroundStyle(colors.textSecondary)
                .accessibilityIdentifier("settings.about")
        } header: {
            DayruleSectionHeader(title: "Help")
        } footer: {
            EmptyView()
        }
        .dayruleSheetRow(colors: colors)
    }

    private func accountChapter(email: String, colors: DayruleColors) -> some View {
        DayruleFormSection {
            Text(email)
                .foregroundStyle(colors.textSecondary)
            Button("Sign out", role: .destructive) {
                Task {
                    signOutHasPending = await model.hasPendingChanges()
                    confirmingSignOut = true
                }
            }
            .buttonStyle(.dayruleDestructive)
            .accessibilityIdentifier("settings.signOut")
            NavigationLink {
                DeleteAccountView(model: model, onDeleted: { dismiss() })
            } label: {
                Text("Delete account…")
                    .foregroundStyle(colors.deadline)
            }
            .accessibilityIdentifier("settings.delete")
        } header: {
            DayruleSectionHeader(title: "Account")
        } footer: {
            footerText("Sign out keeps lists encrypted on this device.", colors: colors)
        }
        .dayruleSheetRow(colors: colors)
    }

    private var aboutVersionLine: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "Dayrule \(version) (\(build))"
    }

    // MARK: - Pieces

    private var doneModeFooter: String {
        let done: String = switch model.entities.settings.moveToDone {
        case .immediately:
            "Completed items go to Done straight away."
        case .daily:
            "Completed items stay on open lists until the next day, then move to Done."
        case .manually:
            "Completed items stay on open lists until you press Move to Done now."
        }
        return "Appearance stays on this device. \(done)"
    }

    private func footerText(_ text: String, colors: DayruleColors) -> some View {
        Text(text)
            .font(DayruleType.helper)
            .foregroundStyle(colors.textSecondary)
            .lineLimit(nil)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func inlineError(_ text: String, colors: DayruleColors) -> some View {
        Text(text)
            .font(DayruleType.error)
            .foregroundStyle(colors.deadline)
            .fixedSize(horizontal: false, vertical: true)
            .transition(.dayruleInlineError)
    }

    /// Warns about unsent changes only when the outbox (read as the dialog opens) has any.
    private var signOutMessage: String {
        if signOutHasPending {
            return "Changes that haven’t synced stay encrypted on this device and sync after your next sign-in."
        }
        return "Your lists stay encrypted on this device. Sign-in details are cleared — use your email and password to open them again."
    }

    // MARK: - Actions

    private func beginExport(json: Bool) {
        do {
            let text: String
            let name: String
            if json {
                text = try Exchange.exportJson(model.entities, now: Date())
                name = "dayrule-export.json"
            } else {
                text = Exchange.exportMarkdown(model.entities, now: Date())
                name = "dayrule-export.md"
            }
            importError = nil
            #if os(iOS)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try Data(text.utf8).write(to: url, options: .atomic)
            shareURL = url
            showShare = true
            #else
            let panel = NSSavePanel()
            panel.nameFieldStringValue = name
            panel.allowedContentTypes = [json ? .json : .plainText]
            panel.begin { response in
                guard response == .OK, let url = panel.url else { return }
                do {
                    try Data(text.utf8).write(to: url, options: .atomic)
                } catch {
                    importError = error.localizedDescription
                }
            }
            #endif
        } catch {
            importError = error.localizedDescription
        }
    }

    private func importFile(_ result: Result<[URL], Error>) {
        importError = nil
        importSummary = nil
        do {
            let urls = try result.get()
            guard let url = urls.first else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let text = try String(contentsOf: url, encoding: .utf8)
            let data = try Exchange.parseImport(text)
            let counts = model.store.run("Import") { d, env in
                Commands.importData(d, env, data)
            }
            model.noteEntitiesChanged()
            importSummary =
                "Imported \(counts.todos) to-dos, \(counts.projects) projects, \(counts.areas) areas."
        } catch let err as Exchange.ImportError {
            importError = err.message
        } catch {
            importError = error.localizedDescription
        }
    }

    private var doneModeBinding: Binding<DoneMode> {
        Binding(
            get: { model.entities.settings.moveToDone },
            set: { mode in
                model.store.run("Done mode") { d, _ in
                    Commands.setDoneMode(d, mode: mode)
                }
                model.noteEntitiesChanged()
            }
        )
    }

    private var biometricBinding: Binding<Bool> {
        Binding(
            get: { model.biometricUnlockAvailable },
            set: { on in
                Task {
                    await changeUnlock(.biometric, enabled: on) {
                        let error = await model.setBiometricUnlock(enabled: on)
                        return (model.biometricUnlockAvailable, error)
                    }
                }
            }
        )
    }

    private var passkeyBinding: Binding<Bool> {
        Binding(
            get: { model.passkeyUnlockAvailable },
            set: { on in
                Task {
                    await changeUnlock(.passkey, enabled: on) {
                        let error = await model.setPasskeyUnlock(enabled: on)
                        return (model.passkeyUnlockAvailable, error)
                    }
                }
            }
        )
    }

    /// Runs one unlock change with an in-flight spinner. `apply` returns the resulting
    /// state and AppModel's failure message, shown under the toggle.
    private func changeUnlock(
        _ method: UnlockMethod,
        enabled: Bool,
        apply: () async -> (isOn: Bool, error: String?)
    ) async {
        guard unlockBusy == nil else { return }
        unlockError = nil
        unlockBusy = method
        let result = await apply()
        unlockBusy = nil
        if result.isOn != enabled {
            let fallback = enabled ? "Couldn’t turn this on." : "Couldn’t turn this off."
            unlockError = UnlockError(method: method, message: result.error ?? fallback)
        }
    }

    private func setRemindersEnabled(_ on: Bool) async {
        if on {
            // Cleared here only: a refusal flips the toggle back off, which re-enters
            // with `on == false` and must not wipe the message.
            reminderError = nil
            let ok = await ReminderScheduler.requestAuthorization()
            DeviceReminderPrefs.enabled = ok
            remindersOn = ok
            if !ok {
                reminderError = "Notifications aren’t allowed for Dayrule."
            } else {
                model.scheduleRemindersIfUnlocked()
            }
        } else {
            DeviceReminderPrefs.enabled = false
            await ReminderScheduler.clearAll()
        }
        #if os(iOS)
        ReminderBackgroundRefresh.scheduleIfNeeded()
        #endif
    }
}

/// Several footer paragraphs. Reports its full height so Mac grouped forms don't
/// under-measure it and overlap the row above.
private struct FooterStack<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Paper chips for System / Light / Dark (PLAN decision 49) — not a system
/// segmented control.
private struct AppearanceChips: View {
    @Binding var selection: AppearancePreference
    var colors: DayruleColors

    var body: some View {
        HStack(spacing: Tokens.Space.s) {
            ForEach(AppearancePreference.allCases) { pref in
                let selected = selection == pref
                Button {
                    selection = pref
                } label: {
                    Text(pref.title)
                        .dayruleRowTitle(.medium)
                        .foregroundStyle(selected ? colors.accent : colors.text)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Tokens.Space.s)
                        .background(
                            RoundedRectangle(cornerRadius: Tokens.radiusCard, style: .continuous)
                                .fill(selected ? colors.selectedRow : colors.sidebar.opacity(0.6))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Tokens.radiusCard, style: .continuous)
                                .strokeBorder(selected ? colors.accent.opacity(0.45) : colors.hairline, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("settings.appearance.\(pref.rawValue)")
            }
        }
    }
}

/// Delete lives one step off Account so the chapter stays calm (decision 49).
private struct DeleteAccountView: View {
    @Bindable var model: AppModel
    var onDeleted: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var password = ""
    @State private var confirm = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme)
        List {
            DayruleFormSection {
                SecureField(
                    "Password",
                    text: $password,
                    prompt: Text("Password").foregroundStyle(colors.textSecondary)
                )
                .dayruleBareField(colors: colors)
                .textContentType(.password)
                .accessibilityIdentifier("settings.delete.password")
                TextField(
                    "Type DELETE to confirm",
                    text: $confirm,
                    prompt: Text("Type DELETE to confirm").foregroundStyle(colors.textSecondary)
                )
                .dayruleBareField(colors: colors)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .accessibilityIdentifier("settings.delete.confirm")
                if let error {
                    Text(error)
                        .font(DayruleType.error)
                        .foregroundStyle(colors.deadline)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.dayruleInlineError)
                }
                Button(role: .destructive) {
                    Task { await runDelete() }
                } label: {
                    DayruleBusyLabel(title: "Delete account", busyTitle: "Deleting…", busy: busy)
                }
                .buttonStyle(.dayruleDestructive)
                .disabled(busy || password.isEmpty || confirm != "DELETE")
                .accessibilityIdentifier("settings.delete.confirmButton")
            } header: {
                DayruleSectionHeader(title: "Delete account")
            } footer: {
                Text("Removes your account and to-dos on the server and this device. It can’t be undone.")
                    .font(DayruleType.helper)
                    .foregroundStyle(colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .dayruleSheetRow(colors: colors)
        }
        .listStyle(.plain)
        .tint(colors.accent)
        .navigationTitle("Delete account")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .background(colors.bg)
    }

    private func runDelete() async {
        error = nil
        guard confirm == "DELETE" else {
            error = "Type DELETE to confirm."
            return
        }
        busy = true
        let ok = await model.deleteAccount(password: password)
        busy = false
        if ok {
            password = ""
            confirm = ""
            onDeleted()
        } else {
            error = model.errorMessage ?? "Couldn’t delete the account."
        }
    }
}
