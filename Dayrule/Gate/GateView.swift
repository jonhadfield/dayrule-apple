import SwiftUI

struct GateView: View {
    @Bindable var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var recoveryPhrase = ""
    @State private var codeSent = false
    /// The button that started the in-flight action; only it shows a busy title.
    @State private var pending: GateAction?
    /// Debug Advanced options. UI tests with `DAYRULE_API` start open so
    /// `gate.api` / `signup.api` stay in the tree.
    #if DEBUG
    @State private var showAdvancedOptions = APIConfig.hasLaunchOverride
    #endif
    @FocusState private var focus: Field?
    @AccessibilityFocusState private var titleFocused: Bool

    private enum Field: Hashable {
        case api, email, password
        case invite, signupEmail, code, signupPassword, confirmPassword
        case recoveryEmail, phrase
    }

    private enum GateAction {
        case signIn, biometric, passkey
        case sendCode, verifyCode, signupContinue
        case secondStepPasskey, recoveryUnlock
    }

    /// One key per screen: locked and unlocking share the sign-in form, so they don't cut.
    private enum Screen: Hashable {
        case restoring, signIn, secondStep, recovery, signup, confirmRecovery, unlocked
    }

    private var screen: Screen {
        switch model.phase {
        case .locked, .unlocking: model.isRestoringSession ? .restoring : .signIn
        case .needsSecondStep: .secondStep
        case .needsRecovery: .recovery
        case .signup: .signup
        case .confirmRecovery: .confirmRecovery
        case .unlocked: .unlocked
        }
    }

    var body: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme)
        Group {
            switch model.phase {
            case .locked, .unlocking:
                if model.isRestoringSession {
                    // Cold launch: hold the cover until device unlock has had its go,
                    // so the password form doesn't flash before the lists.
                    PrivacyCover(showsProgress: true)
                        .transition(.dayruleScreen)
                } else {
                    lockedForm(colors: colors, busy: model.phase == .unlocking || model.gateBusy)
                        .transition(.dayruleScreen)
                }
            case .needsSecondStep:
                secondStepForm(colors: colors)
                    .transition(.dayruleScreen)
            case .needsRecovery:
                recoveryForm(colors: colors)
                    .transition(.dayruleScreen)
            case .signup:
                signupForm(colors: colors)
                    .transition(.dayruleScreen)
            case .confirmRecovery:
                RecoveryPhraseView(words: model.pendingRecoveryWords, busy: model.signupBusy) {
                    Task { await model.finishSignup() }
                }
                .accessibilityIdentifier("gate.recovery")
                .transition(.dayruleScreen)
            case .unlocked:
                ListsBrowserView(model: model)
                    .transition(.dayruleScreen)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            colors.bg.ignoresSafeArea()
        }
        .dayruleAnimation(Motion.screen, value: screen)
        .task { await model.tryDeviceUnlock() }
        .onChange(of: screen) { _, next in
            focus = nil
            guard next != .restoring, next != .unlocked else { return }
            // Let the screen transition land before moving VoiceOver to the new title.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                titleFocused = true
            }
        }
        .onChange(of: model.gateResetEpoch) { _, _ in
            clearSensitiveGateFields()
        }
    }

    private func clearSensitiveGateFields() {
        password = ""
        confirmPassword = ""
        recoveryPhrase = ""
        codeSent = false
        pending = nil
    }

    // MARK: - Sign in

    @ViewBuilder
    private func lockedForm(colors: DayruleColors, busy: Bool) -> some View {
        let canSignIn = !password.isEmpty && !model.email.isEmpty && !busy
        GateScaffold(alignment: .center) { proxy in
            form(alignment: .center, proxy: proxy) {
                header(
                    "Dayrule",
                    intro: "Sign in to open your lists.",
                    font: DayruleType.brand,
                    alignment: .center,
                    identifier: "gate.brand",
                    colors: colors
                )

                TextField("Email", text: $model.email, prompt: prompt("Email", colors))
                    .focused($focus, equals: .email)
                    .accessibilityIdentifier("gate.email")
                    .textContentType(.username)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    #endif
                    .submitLabel(.next)
                    .onSubmit { focus = .password }
                    .dayruleField(isFocused: focus == .email, colors: colors)
                    .disabled(busy)

                SecureField("Password", text: $password, prompt: prompt("Password", colors))
                    .focused($focus, equals: .password)
                    .accessibilityIdentifier("gate.password")
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .submitLabel(.go)
                    .onSubmit {
                        guard canSignIn else { return }
                        signIn()
                    }
                    .dayruleField(isFocused: focus == .password, colors: colors)
                    .disabled(busy)

                #if DEBUG
                advancedOptions(identifier: "gate.api", next: .email, busy: busy, colors: colors)
                #endif

                // Preference is written only after a successful unlock
                // (`finishOnlineSession`); do not persist the toggle alone.
                Toggle(isOn: $model.stayUnlocked) {
                    Text("Stay unlocked on this device")
                        .foregroundStyle(colors.text)
                }
                .accessibilityIdentifier("gate.stayUnlocked")
                .disabled(busy)

                if model.biometricUnlockAvailable {
                    Button {
                        run(.biometric) { await model.unlockWithBiometrics() }
                    } label: {
                        DayruleBusyLabel(
                            title: "Unlock with \(model.biometryLabel)",
                            busyTitle: "Unlocking…",
                            busy: busy && pending == .biometric
                        )
                    }
                    .buttonStyle(.dayruleSecondary)
                    .accessibilityIdentifier("gate.biometric")
                    .disabled(busy)
                }

                if model.passkeyUnlockAvailable {
                    Button {
                        run(.passkey) { await model.unlockWithPasskey() }
                    } label: {
                        DayruleBusyLabel(
                            title: "Unlock with passkey",
                            busyTitle: "Unlocking…",
                            busy: busy && pending == .passkey
                        )
                    }
                    .buttonStyle(.dayruleSecondary)
                    .accessibilityIdentifier("gate.passkey")
                    .disabled(busy)
                }

                Button {
                    signIn()
                } label: {
                    DayruleBusyLabel(title: "Sign in", busyTitle: "Unlocking…", busy: busy && pending == .signIn)
                }
                .buttonStyle(.dayrulePrimary)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("gate.signIn")
                .disabled(!canSignIn)

                message("gate.error", alignment: .center)

                Button("Create an account") {
                    model.beginSignup()
                }
                .buttonStyle(.dayruleLink)
                .accessibilityIdentifier("gate.createAccount")
                .disabled(busy)

                Button("Use recovery phrase") {
                    model.phase = .needsRecovery
                    model.errorMessage = nil
                }
                .buttonStyle(.dayruleLink)
                .disabled(busy)
            }
        }
        #if os(macOS)
        // Mac: ready to type. iOS keeps the keyboard down until a field is tapped,
        // so the sign-in screen isn't half covered at launch.
        .task {
            focus = model.email.isEmpty ? .email : .password
        }
        #endif
    }

    private func signIn() {
        run(.signIn) {
            await model.unlock(password: password)
            password = ""
        }
    }

    // MARK: - Sign up

    @ViewBuilder
    private func signupForm(colors: DayruleColors) -> some View {
        let busy = model.signupBusy || model.gateBusy
        let canContinue = model.signupToken != nil && !password.isEmpty && !busy
        GateScaffold { proxy in
            form(alignment: .leading, proxy: proxy) {
                header(
                    "Create an account",
                    intro: "Invite-only for now. We’ll email a code, then show your recovery phrase.",
                    identifier: "signup.title",
                    colors: colors
                )

                TextField("Invite code", text: $model.inviteCode, prompt: prompt("Invite code", colors))
                    .focused($focus, equals: .invite)
                    .accessibilityIdentifier("signup.invite")
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .submitLabel(.next)
                    .onSubmit { focus = .signupEmail }
                    .dayruleField(isFocused: focus == .invite, colors: colors)
                    .disabled(busy)

                TextField("Email", text: $model.email, prompt: prompt("Email", colors))
                    .focused($focus, equals: .signupEmail)
                    .accessibilityIdentifier("signup.email")
                    .textContentType(.username)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    #endif
                    .dayruleField(isFocused: focus == .signupEmail, colors: colors)
                    .disabled(busy)
                    .onChange(of: model.email) { codeSent = false }

                #if DEBUG
                advancedOptions(identifier: "signup.api", next: .invite, busy: busy, colors: colors)
                #endif

                Button {
                    run(.sendCode) {
                        await model.signupSendCode()
                        if model.errorMessage == nil {
                            codeSent = true
                            focus = .code
                        }
                    }
                } label: {
                    DayruleBusyLabel(title: "Send code", busyTitle: "Sending…", busy: busy && pending == .sendCode)
                }
                .buttonStyle(.dayruleStep(isCurrent: !codeSent))
                .accessibilityIdentifier("signup.sendCode")
                .disabled(model.email.isEmpty || model.inviteCode.isEmpty || busy)

                if codeSent && model.errorMessage == nil {
                    GateInlineMessage(text: "Code sent to \(model.email)", kind: .info, identifier: "signup.codeSent")
                }

                TextField("Code", text: $model.signupCode, prompt: prompt("Code", colors))
                    .focused($focus, equals: .code)
                    .accessibilityIdentifier("signup.code")
                    .textContentType(.oneTimeCode)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.numberPad)
                    #endif
                    .onSubmit {
                        guard !model.signupCode.isEmpty, !busy, model.signupToken == nil else { return }
                        verifyCode()
                    }
                    .dayruleField(isFocused: focus == .code, colors: colors)
                    .disabled(busy)

                Button {
                    verifyCode()
                } label: {
                    DayruleBusyLabel(
                        title: model.signupToken == nil ? "Verify code" : "Code verified",
                        busyTitle: "Verifying…",
                        busy: busy && pending == .verifyCode
                    )
                }
                .buttonStyle(.dayruleStep(isCurrent: codeSent && model.signupToken == nil))
                .accessibilityIdentifier("signup.verifyCode")
                .disabled(model.signupCode.isEmpty || busy || model.signupToken != nil)

                SecureField("Password", text: $password, prompt: prompt("Password", colors))
                    .focused($focus, equals: .signupPassword)
                    .accessibilityIdentifier("signup.password")
                    .textContentType(.newPassword)
                    .submitLabel(.next)
                    .onSubmit { focus = .confirmPassword }
                    .dayruleField(isFocused: focus == .signupPassword, colors: colors)
                    .disabled(model.signupToken == nil || busy)

                SecureField("Confirm password", text: $confirmPassword, prompt: prompt("Confirm password", colors))
                    .focused($focus, equals: .confirmPassword)
                    .accessibilityIdentifier("signup.confirmPassword")
                    .textContentType(.newPassword)
                    .submitLabel(.go)
                    .onSubmit {
                        guard canContinue else { return }
                        continueSignup()
                    }
                    .dayruleField(isFocused: focus == .confirmPassword, colors: colors)
                    .disabled(model.signupToken == nil || busy)

                Button {
                    continueSignup()
                } label: {
                    DayruleBusyLabel(
                        title: "Continue",
                        busyTitle: "Working…",
                        busy: busy && pending == .signupContinue
                    )
                }
                .buttonStyle(.dayrulePrimary)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("signup.continue")
                .disabled(!canContinue)

                message("signup.error")

                Button("Back") {
                    codeSent = false
                    model.cancelSignup()
                }
                .buttonStyle(.dayruleLink)
                .accessibilityIdentifier("signup.back")
            }
        }
    }

    private func verifyCode() {
        run(.verifyCode) { await model.signupVerifyCode() }
    }

    private func continueSignup() {
        run(.signupContinue) {
            await model.signupPrepareAccount(password: password, confirm: confirmPassword)
            password = ""
            confirmPassword = ""
        }
    }

    // MARK: - Second step

    @ViewBuilder
    private func secondStepForm(colors: DayruleColors) -> some View {
        let busy = model.gateBusy
        GateScaffold { proxy in
            form(alignment: .leading, proxy: proxy) {
                header(
                    "Confirm it’s you",
                    intro: "This account has a sign-in passkey. Confirm with it, or use your recovery phrase (that counts as both factors). This is separate from Unlock with passkey on a device.",
                    identifier: "gate.secondStep",
                    colors: colors
                )

                Button {
                    run(.secondStepPasskey) { await model.continuePasskeySecondStep() }
                } label: {
                    DayruleBusyLabel(
                        title: "Continue with passkey",
                        busyTitle: "Confirming…",
                        busy: busy && pending == .secondStepPasskey
                    )
                }
                .buttonStyle(.dayrulePrimary)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("gate.secondStep.passkey")
                .disabled(busy)

                message("gate.secondStep.error")

                Button("Use recovery phrase") {
                    model.beginRecoveryFromSecondStep()
                }
                .buttonStyle(.dayruleLink)
                .accessibilityIdentifier("gate.secondStep.recovery")
                .disabled(busy)

                Button("Cancel") {
                    model.cancelSecondStep()
                }
                .buttonStyle(.dayruleLink)
                .disabled(busy)
            }
        }
    }

    // MARK: - Recovery sign-in

    @ViewBuilder
    private func recoveryForm(colors: DayruleColors) -> some View {
        let busy = model.gateBusy || model.phase == .unlocking
        GateScaffold { proxy in
            form(alignment: .leading, proxy: proxy) {
                header(
                    "Recovery sign-in",
                    intro: "Enter your 24-word recovery phrase. This counts as both factors when a second step is required.",
                    colors: colors
                )

                TextField("Email", text: $model.email, prompt: prompt("Email", colors))
                    .focused($focus, equals: .recoveryEmail)
                    .textContentType(.username)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    #endif
                    .submitLabel(.next)
                    .onSubmit { focus = .phrase }
                    .dayruleField(isFocused: focus == .recoveryEmail, colors: colors)
                    .disabled(busy)

                TextField(
                    "Recovery phrase",
                    text: $recoveryPhrase,
                    prompt: prompt("twenty four words…", colors),
                    axis: .vertical
                )
                .focused($focus, equals: .phrase)
                .lineLimit(4...8)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .dayruleField(isFocused: focus == .phrase, colors: colors)
                .disabled(busy)

                #if DEBUG
                advancedOptions(identifier: "gate.recovery.api", next: .phrase, busy: busy, colors: colors)
                #endif

                Button {
                    run(.recoveryUnlock) {
                        await model.unlockWithRecovery(phrase: recoveryPhrase)
                        recoveryPhrase = ""
                    }
                } label: {
                    DayruleBusyLabel(
                        title: "Unlock with phrase",
                        busyTitle: "Unlocking…",
                        busy: busy && pending == .recoveryUnlock
                    )
                }
                .buttonStyle(.dayrulePrimary)
                .keyboardShortcut(.defaultAction)
                .disabled(model.email.isEmpty || recoveryPhrase.isEmpty || busy)

                message("gate.recoverySignIn.error")

                Button("Back") {
                    model.phase = .locked
                    model.errorMessage = nil
                }
                .buttonStyle(.dayruleLink)
                .disabled(busy)
            }
        }
    }

    // MARK: - Shared pieces

    /// Runs a gate action and remembers which button started it until it returns.
    private func run(_ action: GateAction, _ work: @escaping @MainActor () async -> Void) {
        pending = action
        Task { @MainActor in
            await work()
            if pending == action { pending = nil }
        }
    }

    #if DEBUG
    /// Shown when Advanced is closed but the field is not the launch default.
    private var customAPICaption: String? {
        let current = APIConfig.resolvedBaseURLString(model.apiBaseURLString)
        guard current != APIConfig.defaultBaseURLString else { return nil }
        return "Using \(current)"
    }

    /// Disclosure only. Blank stays blank; a typed override stays typed.
    private func advancedOptions(identifier: String, next: Field, busy: Bool, colors: DayruleColors) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            Button {
                withAnimation(Motion.standard) {
                    showAdvancedOptions.toggle()
                }
            } label: {
                HStack(spacing: Tokens.Space.s) {
                    Text("Advanced options")
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(showAdvancedOptions ? 90 : 0))
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(.plain)
            .dayruleLink()
            .foregroundStyle(colors.textSecondary)
            .frame(minHeight: Tokens.minHit)
            .accessibilityIdentifier("\(identifier).advanced")
            .accessibilityLabel("Advanced options")
            .accessibilityValue(showAdvancedOptions ? "Open" : "Closed")
            .disabled(busy)

            if showAdvancedOptions {
                HStack(alignment: .center, spacing: Tokens.Space.m) {
                    Text("Server")
                        .foregroundStyle(colors.text)
                        .accessibilityHidden(true)
                    TextField(
                        "Server",
                        text: $model.apiBaseURLString,
                        prompt: prompt(APIConfig.defaultBaseURLString, colors),
                        axis: .vertical
                    )
                    .labelsHidden()
                    .lineLimit(1...3)
                    .focused($focus, equals: .api)
                    .accessibilityIdentifier(identifier)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
                    .submitLabel(.next)
                    .onSubmit { focus = next }
                    .onChange(of: model.apiBaseURLString) { _, value in
                        let single = value.filter { !$0.isNewline }
                        if single != value { model.apiBaseURLString = single }
                    }
                    .dayruleField(isFocused: focus == .api, colors: colors)
                    .disabled(busy)
                }
            } else if let using = customAPICaption {
                Text(using)
                    .font(.footnote)
                    .foregroundStyle(colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("\(identifier).using")
            }
        }
        .dayruleAnimation(Motion.standard, value: showAdvancedOptions)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    #endif

    private func prompt(_ text: String, _ colors: DayruleColors) -> Text {
        Text(text).foregroundStyle(colors.textSecondary)
    }

    /// Screen title (a VoiceOver heading that takes focus on arrival) and intro.
    @ViewBuilder
    private func header(
        _ title: String,
        intro: String,
        font: Font = DayruleType.pageTitle,
        alignment: TextAlignment = .leading,
        identifier: String? = nil,
        colors: DayruleColors
    ) -> some View {
        Text(title)
            .font(font)
            .tracking(DayruleType.titleTracking)
            .foregroundStyle(colors.text)
            .multilineTextAlignment(alignment)
            .accessibilityAddTraits(.isHeader)
            .accessibilityFocused($titleFocused)
            .accessibilityIdentifier(identifier ?? "")
        Text(intro)
            .font(.body)
            .foregroundStyle(colors.textSecondary)
            .multilineTextAlignment(alignment)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Inline error or info under the primary button.
    @ViewBuilder
    private func message(_ identifier: String, alignment: TextAlignment = .leading) -> some View {
        if let errorMessage = model.errorMessage {
            GateInlineMessage(
                text: errorMessage,
                kind: model.gateMessageIsInfo ? .info : .error,
                identifier: identifier
            )
            .multilineTextAlignment(alignment)
        }
    }

    /// Form column: scrolls a new message into view and announces it.
    private func form<Content: View>(
        alignment: HorizontalAlignment,
        proxy: ScrollViewProxy,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: alignment, spacing: Tokens.Space.l) {
            content()
        }
        .dayruleAnimation(Motion.standard, value: model.errorMessage)
        .dayruleAnimation(Motion.standard, value: codeSent)
        .onChange(of: model.errorMessage) { _, message in
            guard let message else { return }
            withAnimation(Motion.system(Motion.standard)) {
                proxy.scrollTo("gate.message", anchor: .center)
            }
            AccessibilityNotification.Announcement(message).post()
        }
    }
}
