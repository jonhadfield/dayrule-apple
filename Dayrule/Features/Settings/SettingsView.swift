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
    @State private var deletePassword = ""
    @State private var deleteConfirm = ""
    @State private var deleteBusy = false
    @State private var deleteError: String?

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
                appearanceSection(colors: colors)
                syncSection(colors: colors)
                doneSection(colors: colors)
                biometricSection(colors: colors)
                passkeySection(colors: colors)
                remindersSection(colors: colors)
                dataSection(colors: colors)
                if let email = model.accountEmail {
                    accountSection(email: email, colors: colors)
                    deleteSection(colors: colors)
                }
                Section {
                    NavigationLink {
                        HelpView(embedded: true)
                    } label: {
                        Text("Help")
                    }
                    .accessibilityIdentifier("settings.help")
                }
                .dayruleSheetRow(colors: colors)
            }
            .listStyle(.plain)
            .dayruleAnimation(Motion.standard, value: model.entities.settings.moveToDone)
            .dayruleAnimation(Motion.standard, value: unlockError)
            .dayruleAnimation(Motion.standard, value: reminderError)
            .dayruleAnimation(Motion.standard, value: importSummary)
            .dayruleAnimation(Motion.standard, value: importError)
            .dayruleAnimation(Motion.standard, value: deleteError)
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

    // MARK: - Sections

    private func appearanceSection(colors: DayruleColors) -> some View {
        DayruleFormSection {
            Picker(selection: appearanceBinding) {
                ForEach(AppearancePreference.allCases) { pref in
                    Text(pref.title).tag(pref)
                }
            } label: {
                Text("Appearance").foregroundStyle(colors.text)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("settings.appearance")
        } header: {
            DayruleSectionHeader(title: "Appearance")
        } footer: {
            footerText("Light keeps the paper palette. System follows the device. This preference stays on this device only.", colors: colors)
        }
        .dayruleSheetRow(colors: colors)
    }

    private func syncSection(colors: DayruleColors) -> some View {
        DayruleFormSection {
            LabeledContent {
                SyncStatusView(status: model.syncStatus, needsServerSignIn: model.needsServerSignIn)
            } label: {
                Text("Status").foregroundStyle(colors.text)
            }
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
        } header: {
            DayruleSectionHeader(title: "Sync")
        } footer: {
            syncFooter(colors: colors)
        }
        .dayruleSheetRow(colors: colors)
    }

    @ViewBuilder
    private func syncFooter(colors: DayruleColors) -> some View {
        let status = model.syncStatus
        let showLabel = status.label != status.shortLabel
        if showLabel || model.needsServerSignIn {
            FooterStack {
                if showLabel {
                    Text(status.label)
                        .font(DayruleType.helper)
                        .foregroundStyle(status.tone == .deadline ? colors.deadline : colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.opacity)
                }
                if model.needsServerSignIn {
                    footerText(
                        "Unlocked offline — edits stay on this device. \(model.biometryLabel) does not create a server session.",
                        colors: colors
                    )
                }
            }
        }
    }

    private func doneSection(colors: DayruleColors) -> some View {
        Section {
            Picker(selection: doneModeBinding) {
                Text("Immediately").tag(DoneMode.immediately)
                Text("Daily").tag(DoneMode.daily)
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
            DayruleSectionHeader(title: "Done")
        }
        .dayruleSheetRow(colors: colors)
    }

    private func biometricSection(colors: DayruleColors) -> some View {
        DayruleFormSection {
            unlockToggle(
                .biometric,
                title: "Unlock with \(model.biometryLabel)",
                isOn: biometricBinding,
                identifier: "settings.biometric",
                colors: colors
            )
        } header: {
            DayruleSectionHeader(title: "Biometrics")
        } footer: {
            footerText("Uses this device’s biometrics to open the Keychain item that unwraps your account key. Password and recovery stay authoritative.", colors: colors)
        }
        .dayruleSheetRow(colors: colors)
    }

    private func passkeySection(colors: DayruleColors) -> some View {
        DayruleFormSection {
            unlockToggle(
                .passkey,
                title: "Unlock with passkey",
                isOn: passkeyBinding,
                identifier: "settings.passkey",
                colors: colors
            )
        } header: {
            DayruleSectionHeader(title: "Passkey")
        } footer: {
            FooterStack {
                footerText("Creates a passkey on this device that derives a wrap key (PRF). Separate from a sign-in passkey on the account (second step after password). Password stays the fallback.", colors: colors)
                footerText("Stay unlocked is chosen when you sign in. It keeps a device wrap key without biometrics — anyone who can unlock this device can open Dayrule.", colors: colors)
            }
        }
        .dayruleSheetRow(colors: colors)
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
            FooterStack {
                if remindersOn {
                    footerText("Titles are stored by the OS on this device. Leave off to keep only the time.", colors: colors)
                }
                footerText("Reminders stay on this device. The account reminder channel on the web still drives email / browser push only.", colors: colors)
            }
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
            FooterStack {
                footerText("Exports are made on this device and are not encrypted. Keep the files safe.", colors: colors)
                footerText("Device backups may include your encrypted vault. Unlock keys stay on this device only, so a backup alone can’t open Dayrule on another phone or Mac.", colors: colors)
                    .accessibilityIdentifier("settings.backupNote")
            }
        }
        .dayruleSheetRow(colors: colors)
    }

    private func accountSection(email: String, colors: DayruleColors) -> some View {
        Section {
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
        } header: {
            DayruleSectionHeader(title: "Account")
        }
        .dayruleSheetRow(colors: colors)
    }

    private func deleteSection(colors: DayruleColors) -> some View {
        DayruleFormSection {
            SecureField(
                "Password",
                text: $deletePassword,
                prompt: Text("Password").foregroundStyle(colors.textSecondary)
            )
            .dayruleBareField(colors: colors)
            .textContentType(.password)
            .accessibilityIdentifier("settings.delete.password")
            TextField(
                "Type DELETE to confirm",
                text: $deleteConfirm,
                prompt: Text("Type DELETE to confirm").foregroundStyle(colors.textSecondary)
            )
            .dayruleBareField(colors: colors)
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
            .accessibilityIdentifier("settings.delete.confirm")
            if let deleteError {
                inlineError(deleteError, colors: colors)
            }
            Button(role: .destructive) {
                Task { await runDeleteAccount() }
            } label: {
                DayruleBusyLabel(title: "Delete account", busyTitle: "Deleting…", busy: deleteBusy)
            }
            .buttonStyle(.dayruleDestructive)
            .disabled(
                deleteBusy
                    || deletePassword.isEmpty
                    || deleteConfirm != "DELETE"
            )
            .accessibilityIdentifier("settings.delete")
        } header: {
            DayruleSectionHeader(title: "Delete account")
        } footer: {
            footerText("Deletes your account and all your to-dos on our servers and on this device. This can’t be undone.", colors: colors)
        }
        .dayruleSheetRow(colors: colors)
    }

    // MARK: - Pieces

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

    private func runDeleteAccount() async {
        deleteError = nil
        guard deleteConfirm == "DELETE" else {
            deleteError = "Type DELETE to confirm."
            return
        }
        deleteBusy = true
        let ok = await model.deleteAccount(password: deletePassword)
        deleteBusy = false
        if ok {
            deletePassword = ""
            deleteConfirm = ""
            dismiss()
        } else {
            deleteError = model.errorMessage ?? "Couldn’t delete the account."
        }
    }

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
