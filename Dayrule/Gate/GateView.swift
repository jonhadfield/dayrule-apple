import SwiftUI

struct GateView: View {
    @Bindable var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var password = ""
    @State private var recoveryPhrase = ""

    var body: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme)
        ZStack {
            colors.bg.ignoresSafeArea()
            switch model.phase {
            case .locked:
                lockedForm(colors: colors, busy: false)
            case .unlocking:
                lockedForm(colors: colors, busy: true)
            case .needsRecovery:
                recoveryForm(colors: colors)
            case .unlocked:
                VaultBrowserView(model: model)
            }
        }
        .task { await model.tryDeviceUnlock() }
    }

    @ViewBuilder
    private func lockedForm(colors: DayruleColors, busy: Bool) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer(minLength: 40)
                Text("Dayrule")
                    .font(DayruleFont.brand())
                    .foregroundStyle(colors.text)
                Text("Sign in to pull your encrypted vault.")
                    .font(.body)
                    .foregroundStyle(colors.textSecondary)
                    .multilineTextAlignment(.center)

                field(colors: colors, label: "API", text: $model.apiBaseURLString)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif

                field(colors: colors, label: "Email", text: $model.email)
                    .textContentType(.username)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    #endif

                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .padding(14)
                    .background(colors.sidebar)
                    .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusCard, style: .continuous))
                    .disabled(busy)

                Toggle("Stay unlocked on this device", isOn: $model.stayUnlocked)
                    .foregroundStyle(colors.textSecondary)

                Button {
                    Task {
                        await model.unlock(password: password)
                        password = ""
                    }
                } label: {
                    Text(busy ? "Unlocking…" : "Sign in")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(colors.bg)
                        .background(colors.accent)
                        .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusPopover, style: .continuous))
                }
                .disabled(password.isEmpty || model.email.isEmpty || busy)

                Button("Use recovery phrase") {
                    model.phase = .needsRecovery
                    model.errorMessage = nil
                }
                .foregroundStyle(colors.accent)

                if let errorMessage = model.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(Tokens.Light.deadline)
                        .multilineTextAlignment(.center)
                }
                Spacer(minLength: 40)
            }
            .padding(.horizontal, 32)
        }
    }

    @ViewBuilder
    private func recoveryForm(colors: DayruleColors) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Recovery sign-in")
                    .font(DayruleFont.listTitle())
                    .foregroundStyle(colors.text)
                Text("Enter your 24-word recovery phrase. This counts as both factors when a second step is required.")
                    .foregroundStyle(colors.textSecondary)

                field(colors: colors, label: "Email", text: $model.email)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif

                TextField("twenty four words…", text: $recoveryPhrase, axis: .vertical)
                    .lineLimit(4...8)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .padding(14)
                    .background(colors.sidebar)
                    .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusCard, style: .continuous))

                Button {
                    Task {
                        await model.unlockWithRecovery(phrase: recoveryPhrase)
                        recoveryPhrase = ""
                    }
                } label: {
                    Text(model.phase == .unlocking ? "Unlocking…" : "Unlock with phrase")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(colors.bg)
                        .background(colors.accent)
                        .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusPopover, style: .continuous))
                }

                Button("Back") {
                    model.phase = .locked
                    model.errorMessage = nil
                }
                .foregroundStyle(colors.accent)

                if let errorMessage = model.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(Tokens.Light.deadline)
                }
            }
            .padding(24)
        }
    }

    private func field(colors: DayruleColors, label: String, text: Binding<String>) -> some View {
        TextField(label, text: text)
            .padding(14)
            .background(colors.sidebar)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusCard, style: .continuous))
    }
}

struct VaultBrowserView: View {
    @Bindable var model: AppModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme)
        NavigationStack {
            List {
                if model.vaultLoading && model.vault == nil {
                    Text("Pulling vault…")
                        .foregroundStyle(colors.textSecondary)
                }
                if let vault = model.vault {
                    Section("Counts") {
                        ForEach(vault.counts.keys.sorted(), id: \.self) { key in
                            HStack {
                                Text(key)
                                Spacer()
                                Text("\(vault.counts[key] ?? 0)")
                                    .foregroundStyle(colors.textSecondary)
                            }
                        }
                        Text("\(vault.recordCount) wire records · \(vault.skippedUnknownAlg) skipped")
                            .font(.footnote)
                            .foregroundStyle(colors.textSecondary)
                    }
                    Section("Titles") {
                        ForEach(vault.entities) { entity in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entity.title)
                                    .foregroundStyle(colors.text)
                                Text("\(entity.type) · \(entity.key)")
                                    .font(.caption)
                                    .foregroundStyle(colors.textSecondary)
                            }
                        }
                    }
                } else if let errorMessage = model.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(Tokens.Light.deadline)
                }
            }
            .scrollContentBackground(.hidden)
            .background(colors.bg)
            .navigationTitle("Dayrule")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Lock") { model.lock() }
                        .foregroundStyle(colors.accent)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Refresh") {
                        Task { await model.refreshVault() }
                    }
                    .foregroundStyle(colors.accent)
                }
            }
        }
        #if os(iOS)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0).onChanged { _ in model.bumpIdle() }
        )
        #endif
    }
}
