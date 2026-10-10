import SwiftUI

/// Device Settings: sync status (M4) + Done logging mode (M5).
struct SettingsView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

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
                if let email = model.accountEmail {
                    Section("Account") {
                        Text(email)
                            .foregroundStyle(colors.textSecondary)
                    }
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
}

private extension SyncStatus {
    var isBlocked: Bool {
        if case .blocked = self { return true }
        return false
    }
}
