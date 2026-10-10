import SwiftUI

/// Minimal device Settings: sync status (M4).
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
}

private extension SyncStatus {
    var isBlocked: Bool {
        if case .blocked = self { return true }
        return false
    }
}
