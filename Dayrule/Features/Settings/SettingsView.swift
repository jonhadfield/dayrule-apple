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
    @State private var showHelp = false
    @State private var importError: String?
    @State private var importSummary: String?
    @State private var showImporter = false
    #if os(iOS)
    @State private var shareURL: URL?
    @State private var showShare = false
    #endif
    @State private var remindersOn = DeviceReminderPrefs.enabled
    @State private var showReminderTitles = DeviceReminderPrefs.showTitles
    @State private var deletePassword = ""
    @State private var deleteConfirm = ""
    @State private var deleteBusy = false
    @State private var deleteError: String?

    var body: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme)
        NavigationStack {
            List {
                Section("Sync") {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(model.syncStatus.label)
                            .foregroundStyle(
                                model.syncStatus == .needsUpdate || model.syncStatus.isBlocked
                                    ? Tokens.Light.deadline
                                    : colors.textSecondary
                            )
                            .multilineTextAlignment(.trailing)
                    }
                    Button("Sync now") {
                        Task { await model.refreshVault() }
                    }
                    .foregroundStyle(colors.accent)
                    .disabled(model.syncStatus == .syncing)
                }
                Section("Completed") {
                    Picker("Move to Done", selection: doneModeBinding) {
                        Text("Immediately").tag(DoneMode.immediately)
                        Text("Daily").tag(DoneMode.daily)
                        Text("Manually").tag(DoneMode.manually)
                    }
                    .accessibilityIdentifier("settings.doneMode")
                    if model.entities.settings.moveToDone == .manually {
                        Button("Log Completed") {
                            model.store.run("Move to Done") { d, env in
                                Commands.moveToDoneNow(d, env)
                            }
                            model.noteEntitiesChanged()
                        }
                        .foregroundStyle(colors.accent)
                        .accessibilityIdentifier("settings.logCompleted")
                    }
                }
                Section("Unlock") {
                    Toggle("Unlock with \(model.biometryLabel)", isOn: biometricBinding)
                        .accessibilityIdentifier("settings.biometric")
                        .disabled(model.phase != .unlocked)
                    Text("Uses this device’s biometrics to open the Keychain item that unwraps your account key. Password and recovery stay authoritative.")
                        .font(.footnote)
                        .foregroundStyle(colors.textSecondary)
                    Toggle("Unlock with passkey", isOn: passkeyBinding)
                        .accessibilityIdentifier("settings.passkey")
                        .disabled(model.phase != .unlocked)
                    Text("Creates a passkey on this device that derives a wrap key (PRF). Separate from a sign-in passkey on the account (second step after password). Password stays the fallback.")
                        .font(.footnote)
                        .foregroundStyle(colors.textSecondary)
                    Text("Stay unlocked keeps a device wrap key without biometrics — anyone who can unlock the phone can open Dayrule.")
                        .font(.footnote)
                        .foregroundStyle(colors.textSecondary)
                }
                Section("Reminders") {
                    Toggle("Local reminders", isOn: $remindersOn)
                        .accessibilityIdentifier("settings.remindersEnabled")
                        .onChange(of: remindersOn) { _, on in
                            Task { await setRemindersEnabled(on) }
                        }
                    if remindersOn {
                        Toggle("Show titles in notifications", isOn: $showReminderTitles)
                            .accessibilityIdentifier("settings.reminderTitles")
                            .onChange(of: showReminderTitles) { _, on in
                                DeviceReminderPrefs.showTitles = on
                                model.scheduleRemindersIfUnlocked()
                            }
                        Text("Titles are stored by the OS on this device. Leave off to keep only the time.")
                            .font(.footnote)
                            .foregroundStyle(colors.textSecondary)
                    }
                    Text("Reminders stay on this device. The account reminder channel on the web still drives email / browser push only.")
                        .font(.footnote)
                        .foregroundStyle(colors.textSecondary)
                }
                Section("Your data") {
                    Text("Exports are made on this device and are not encrypted. Keep the files safe.")
                        .font(.footnote)
                        .foregroundStyle(colors.textSecondary)
                    Text("Device backups may include your encrypted vault. Unlock keys stay on this device only, so a backup alone can’t open Dayrule on another phone or Mac.")
                        .font(.footnote)
                        .foregroundStyle(colors.textSecondary)
                        .accessibilityIdentifier("settings.backupNote")
                    Button("Export JSON") { beginExport(json: true) }
                        .foregroundStyle(colors.accent)
                        .accessibilityIdentifier("settings.exportJson")
                    Button("Export Markdown") { beginExport(json: false) }
                        .foregroundStyle(colors.accent)
                        .accessibilityIdentifier("settings.exportMarkdown")
                    Button("Import…") { showImporter = true }
                        .foregroundStyle(colors.accent)
                        .accessibilityIdentifier("settings.import")
                    if let importSummary {
                        Text(importSummary)
                            .font(.footnote)
                            .foregroundStyle(colors.textSecondary)
                    }
                    if let importError {
                        Text(importError)
                            .font(.footnote)
                            .foregroundStyle(Tokens.Light.deadline)
                    }
                }
                if let email = model.accountEmail {
                    Section("Account") {
                        Text(email)
                            .foregroundStyle(colors.textSecondary)
                    }
                    Section {
                        Text("Deletes your account and all your to-dos on our servers and on this device. This can’t be undone.")
                            .font(.footnote)
                            .foregroundStyle(colors.textSecondary)
                        SecureField("Password", text: $deletePassword)
                            .textContentType(.password)
                            .accessibilityIdentifier("settings.delete.password")
                        TextField("Type DELETE to confirm", text: $deleteConfirm)
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                            .accessibilityIdentifier("settings.delete.confirm")
                        if let deleteError {
                            Text(deleteError)
                                .font(.footnote)
                                .foregroundStyle(Tokens.Light.deadline)
                        }
                        Button(deleteBusy ? "Deleting…" : "Delete account", role: .destructive) {
                            Task { await runDeleteAccount() }
                        }
                        .disabled(
                            deleteBusy
                                || deletePassword.isEmpty
                                || deleteConfirm != "DELETE"
                        )
                        .accessibilityIdentifier("settings.delete")
                    } header: {
                        Text("Delete account")
                    }
                }
                Section {
                    Button("Help") { showHelp = true }
                        .foregroundStyle(colors.accent)
                        .accessibilityIdentifier("settings.help")
                }
            }
            .scrollContentBackground(.hidden)
            .background(colors.bg)
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(colors.accent)
                }
            }
            .sheet(isPresented: $showHelp) {
                HelpView()
            }
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
        }
    }

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
                Task { await model.setBiometricUnlock(enabled: on) }
            }
        )
    }

    private var passkeyBinding: Binding<Bool> {
        Binding(
            get: { model.passkeyUnlockAvailable },
            set: { on in
                Task { await model.setPasskeyUnlock(enabled: on) }
            }
        )
    }

    private func setRemindersEnabled(_ on: Bool) async {
        if on {
            let ok = await ReminderScheduler.requestAuthorization()
            DeviceReminderPrefs.enabled = ok
            remindersOn = ok
            if !ok {
                importError = "Notifications aren’t allowed for Dayrule."
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

private extension SyncStatus {
    var isBlocked: Bool {
        if case .blocked = self { return true }
        return false
    }
}
