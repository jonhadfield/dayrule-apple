import SwiftUI

struct GateView: View {
    @Bindable var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var password = ""
    @State private var confirmPassword = ""
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
            case .signup:
                signupForm(colors: colors)
            case .confirmRecovery:
                RecoveryPhraseView(words: model.pendingRecoveryWords, busy: model.signupBusy) {
                    Task { await model.finishSignup() }
                }
                .accessibilityIdentifier("gate.recovery")
            case .unlocked:
                ListsBrowserView(model: model)
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
                    .accessibilityIdentifier("gate.brand")
                Text("Sign in to pull your encrypted vault.")
                    .font(.body)
                    .foregroundStyle(colors.textSecondary)
                    .multilineTextAlignment(.center)

                field(colors: colors, label: "API", text: $model.apiBaseURLString)
                    .accessibilityIdentifier("gate.api")
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif

                field(colors: colors, label: "Email", text: $model.email)
                    .accessibilityIdentifier("gate.email")
                    .textContentType(.username)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    #endif

                SecureField("Password", text: $password)
                    .accessibilityIdentifier("gate.password")
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
                    .onChange(of: model.stayUnlocked) { _, on in
                        DeviceUnlockPrefs.stayUnlocked = on
                    }
                    .accessibilityIdentifier("gate.stayUnlocked")

                if model.biometricUnlockAvailable {
                    Button {
                        Task { await model.unlockWithBiometrics() }
                    } label: {
                        Text(busy ? "Unlocking…" : "Unlock with \(model.biometryLabel)")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .foregroundStyle(colors.accent)
                            .background(colors.sidebar)
                            .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusPopover, style: .continuous))
                    }
                    .accessibilityIdentifier("gate.biometric")
                    .disabled(busy)
                }

                if model.passkeyUnlockAvailable {
                    Button {
                        Task { await model.unlockWithPasskey() }
                    } label: {
                        Text(busy ? "Unlocking…" : "Unlock with passkey")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .foregroundStyle(colors.accent)
                            .background(colors.sidebar)
                            .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusPopover, style: .continuous))
                    }
                    .accessibilityIdentifier("gate.passkey")
                    .disabled(busy)
                }

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
                .accessibilityIdentifier("gate.signIn")
                .disabled(password.isEmpty || model.email.isEmpty || busy)

                Button("Create an account") {
                    model.beginSignup()
                }
                .accessibilityIdentifier("gate.createAccount")
                .foregroundStyle(colors.accent)
                .disabled(busy)

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
                        .accessibilityIdentifier("gate.error")
                }
                Spacer(minLength: 40)
            }
            .padding(.horizontal, 32)
        }
    }

    @ViewBuilder
    private func signupForm(colors: DayruleColors) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Create an account")
                    .font(DayruleFont.listTitle())
                    .foregroundStyle(colors.text)
                    .accessibilityIdentifier("signup.title")

                Text("Invite-only for now. We’ll email a code, then show your recovery phrase.")
                    .foregroundStyle(colors.textSecondary)

                field(colors: colors, label: "API", text: $model.apiBaseURLString)
                    .accessibilityIdentifier("signup.api")
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif

                field(colors: colors, label: "Invite code", text: $model.inviteCode)
                    .accessibilityIdentifier("signup.invite")
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif

                field(colors: colors, label: "Email", text: $model.email)
                    .accessibilityIdentifier("signup.email")
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    #endif

                Button {
                    Task { await model.signupSendCode() }
                } label: {
                    Text(model.signupBusy ? "Sending…" : "Send code")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(colors.bg)
                        .background(colors.accent)
                        .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusPopover, style: .continuous))
                }
                .accessibilityIdentifier("signup.sendCode")
                .disabled(model.email.isEmpty || model.inviteCode.isEmpty || model.signupBusy)

                field(colors: colors, label: "Code", text: $model.signupCode)
                    .accessibilityIdentifier("signup.code")
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.numberPad)
                    #endif

                Button {
                    Task { await model.signupVerifyCode() }
                } label: {
                    Text(model.signupToken == nil ? "Verify code" : "Code verified")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .accessibilityIdentifier("signup.verifyCode")
                .disabled(model.signupCode.isEmpty || model.signupBusy || model.signupToken != nil)
                .foregroundStyle(colors.accent)

                SecureField("Password", text: $password)
                    .accessibilityIdentifier("signup.password")
                    .padding(14)
                    .background(colors.sidebar)
                    .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusCard, style: .continuous))
                    .disabled(model.signupToken == nil)

                SecureField("Confirm password", text: $confirmPassword)
                    .accessibilityIdentifier("signup.confirmPassword")
                    .padding(14)
                    .background(colors.sidebar)
                    .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusCard, style: .continuous))
                    .disabled(model.signupToken == nil)

                Button {
                    Task {
                        await model.signupPrepareAccount(password: password, confirm: confirmPassword)
                        password = ""
                        confirmPassword = ""
                    }
                } label: {
                    Text(model.signupBusy ? "Working…" : "Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(colors.bg)
                        .background(colors.accent)
                        .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusPopover, style: .continuous))
                }
                .accessibilityIdentifier("signup.continue")
                .disabled(model.signupToken == nil || password.isEmpty || model.signupBusy)

                Button("Back") { model.cancelSignup() }
                    .foregroundStyle(colors.accent)
                    .accessibilityIdentifier("signup.back")

                if let errorMessage = model.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(Tokens.Light.deadline)
                        .accessibilityIdentifier("signup.error")
                }
            }
            .padding(24)
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
