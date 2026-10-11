import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable {
        case locked
        case unlocking
        case needsSecondStep
        case needsRecovery
        case signup
        case confirmRecovery
        case unlocked
    }

    var phase: Phase = .locked
    var errorMessage: String?
    var stayUnlocked = DeviceUnlockPrefs.stayUnlocked
    var email = ""
    var apiBaseURLString = APIConfig.defaultBaseURLString
    var vault: VaultSnapshot?
    var vaultLoading = false
    var accountEmail: String?
    var syncStatus: SyncStatus = .idle
    var showSettings = false
    /// True when a biometric wrap is cached for this device.
    var biometricUnlockAvailable = false
    var biometryLabel = "Biometrics"
    /// True when a passkey PRF unlock blob is cached (PLAN §8.4).
    var passkeyUnlockAvailable = false

    /// Create-account fields (Gate signup).
    var inviteCode = ""
    var signupCode = ""
    var signupBusy = false
    private(set) var signupToken: String?
    private(set) var pendingRecoveryWords: [String] = []
    private var pendingSignup: PendingSignup?

    let crypto = CryptoActor()
    let store = EntityStore()
    /// Bumped when `store.entities` changes so Observation refreshes views.
    private(set) var entitiesEpoch = 0
    private let sessions = SessionStore()
    private var api: APIClient
    private var idleTask: Task<Void, Never>?
    private var cipherStore: CipherStore?
    private var syncEngine: SyncEngine?
    private var syncTask: Task<Void, Never>?

    private struct PendingSignup {
        var email: String
        var inviteCode: String
        var signupToken: String
        var userId: String
        var salt: [UInt8]
        var created: UnlockResult
    }

    /// Held only while the passkey second-step sheet can still finish login (PLAN §9.3).
    private struct PendingSecondStep {
        var token: String
        var kek: [UInt8]
    }

    private var pendingSecondStep: PendingSecondStep?

    var entities: Entities {
        _ = entitiesEpoch
        return store.entities
    }

    func noteEntitiesChanged() {
        entitiesEpoch += 1
        scheduleRemindersIfUnlocked()
    }

    /// Reschedule local notifications while unlocked (PLAN §11).
    func scheduleRemindersIfUnlocked() {
        guard phase == .unlocked else { return }
        let snapshot = store.entities
        Task { await ReminderScheduler.reschedule(entities: snapshot) }
        #if os(iOS)
        ReminderBackgroundRefresh.scheduleIfNeeded()
        #endif
    }

    #if os(iOS)
    /// BGAppRefresh: refresh the nearest 64 while stay-unlocked (PLAN §11).
    func handleBackgroundReminderRefresh() async {
        guard DeviceReminderPrefs.enabled, DeviceUnlockPrefs.stayUnlocked else { return }
        if phase == .unlocked {
            await ReminderScheduler.reschedule(entities: store.entities)
            ReminderBackgroundRefresh.scheduleIfNeeded()
            return
        }
        guard let cached = try? sessions.loadAccount(),
              let wrapped = cached.deviceWrappedAK
        else { return }
        do {
            try await crypto.unlockFromDeviceWrap(
                userId: cached.userId,
                wrapped: try wrapped.sealed()
            )
            try openPersistence(userId: cached.userId)
            if let cipherStore {
                let entities = try await cipherStore.load()
                await ReminderScheduler.reschedule(entities: entities)
            }
            cipherStore = nil
            syncEngine = nil
            await crypto.lock()
        } catch {
            cipherStore = nil
            syncEngine = nil
            await crypto.lock()
        }
        ReminderBackgroundRefresh.scheduleIfNeeded()
    }
    #endif

    init() {
        let defaultAPI = APIConfig.defaultBaseURLString
        apiBaseURLString = defaultAPI
        api = APIClient(
            baseURL: URL(string: defaultAPI) ?? URL(string: APIConfig.production)!
        )
        if let cached = try? sessions.loadAccount() {
            email = cached.email
            accountEmail = cached.email
        }
        if let token = try? sessions.loadToken() {
            Task { await api.setToken(token) }
        }
        if let cached = try? sessions.loadAccount() {
            biometricUnlockAvailable = cached.biometricWrappedAK != nil
            passkeyUnlockAvailable = cached.passkey != nil
        }
        store.onChanges = { [weak self] changes, source in
            await self?.persist(changes, source: source)
        }
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSSystemTimeZoneDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.scheduleRemindersIfUnlocked() }
        }
    }

    func beginSignup() {
        errorMessage = nil
        signupCode = ""
        signupToken = nil
        pendingSignup = nil
        pendingRecoveryWords = []
        phase = .signup
    }

    func cancelSignup() {
        errorMessage = nil
        signupCode = ""
        signupToken = nil
        pendingSignup = nil
        pendingRecoveryWords = []
        signupBusy = false
        phase = .locked
    }

    func signupSendCode() async {
        errorMessage = nil
        signupBusy = true
        defer { signupBusy = false }
        do {
            guard let base = URL(string: apiBaseURLString) else { throw APIError.offline }
            await api.setBaseURL(base)
            try await api.signupStart(email: email, inviteCode: inviteCode.trimmingCharacters(in: .whitespacesAndNewlines))
            signupToken = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signupVerifyCode() async {
        errorMessage = nil
        signupBusy = true
        defer { signupBusy = false }
        do {
            let verified = try await api.signupVerify(
                email: email,
                code: signupCode.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            signupToken = verified.signupToken
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Derive keys and show the recovery phrase; `finishSignup` registers after confirm.
    func signupPrepareAccount(password: String, confirm: String) async {
        errorMessage = nil
        if let problem = await PasswordValidation.newPasswordProblem(
            password: password,
            confirm: confirm
        ) {
            errorMessage = problem
            return
        }
        guard let token = signupToken else {
            errorMessage = "Verify the email code first."
            return
        }
        signupBusy = true
        defer { signupBusy = false }
        do {
            Primitives.ready()
            let userId = UUID().uuidString.lowercased()
            let salt = Primitives.randomBytes(16)
            let created = try await crypto.createLocalDemo(
                password: password,
                userId: userId,
                salt: salt
            )
            pendingSignup = PendingSignup(
                email: email.lowercased(),
                inviteCode: inviteCode.trimmingCharacters(in: .whitespacesAndNewlines),
                signupToken: token,
                userId: userId,
                salt: salt,
                created: created
            )
            pendingRecoveryWords = created.recoveryWords
            phase = .confirmRecovery
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func finishSignup() async {
        errorMessage = nil
        guard let pending = pendingSignup else {
            phase = .locked
            return
        }
        signupBusy = true
        defer { signupBusy = false }
        do {
            let registered = try await api.register(
                email: pending.email,
                signupToken: pending.signupToken,
                inviteCode: pending.inviteCode,
                userId: pending.userId,
                saltB64: Base64Std.encode(pending.salt),
                kdf: pending.created.kdf,
                authKeyB64: Base64Std.encode(pending.created.authKey),
                wrappedPassword: WrappedB64(pending.created.wrappedPassword),
                wrappedRecovery: WrappedB64(pending.created.wrappedRecovery),
                recoveryProofB64: Base64Std.encode(pending.created.recoveryProof),
                deviceLabel: ClientPlatform.deviceLabel
            )
            guard let token = registered.token else {
                throw APIError.decoding
            }
            await api.setToken(token)
            try sessions.saveToken(token)
            DeviceUnlockPrefs.stayUnlocked = stayUnlocked
            let cached = SessionStore.CachedAccount(
                userId: pending.userId,
                email: pending.email,
                saltB64: Base64Std.encode(pending.salt),
                kdf: KdfDTO(v: pending.created.kdf.v, ops: pending.created.kdf.ops, mem: pending.created.kdf.mem),
                wrappedPassword: WrappedB64(pending.created.wrappedPassword),
                deviceWrappedAK: stayUnlocked ? WrappedB64(pending.created.wrappedDevice) : nil,
                biometricWrappedAK: nil,
                passkey: nil
            )
            try sessions.saveAccount(cached)
            biometricUnlockAvailable = false
            passkeyUnlockAvailable = false
            accountEmail = pending.email
            email = pending.email
            try openPersistence(userId: pending.userId)
            pendingSignup = nil
            pendingRecoveryWords = []
            signupToken = nil
            // Pull before unlocking the list UI so hydrate can't wipe a concurrent Add.
            await openUnlockedVault()
        } catch {
            errorMessage = error.localizedDescription
            phase = .confirmRecovery
        }
    }

    private func persist(_ changes: [StoreChange], source: ChangeSource) async {
        guard let cipherStore else { return }
        do {
            switch source {
            case .local: try await cipherStore.applyLocal(changes)
            case .sync: try await cipherStore.applyRemote(changes)
            }
            noteEntitiesChanged()
            if source == .local { scheduleSync() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func openPersistence(userId: String) throws {
        let db = try AppDatabase.open(userId: userId)
        let store = CipherStore(dbQueue: db, cipher: ActorRecordCipher(crypto: crypto))
        cipherStore = store
        syncEngine = SyncEngine(store: self.store, db: store, crypto: crypto, api: api)
    }

    private func scheduleSync() {
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.runSync()
        }
    }

    private func hasBearerSession() -> Bool {
        (try? sessions.loadToken()) != nil
    }

    private func runSync() async {
        guard let syncEngine else { return }
        // No Bearer → stay local; do not hit the API (401 would bounce to the gate).
        guard hasBearerSession() else {
            syncStatus = .offline("Sign in to sync.")
            return
        }
        syncStatus = .syncing
        do {
            try await syncEngine.sync()
            noteEntitiesChanged()
            if syncEngine.sawUnknownAlg {
                syncStatus = .needsUpdate
            } else {
                syncStatus = .synced
            }
            if case .needsUpdate = syncStatus {
                errorMessage = syncStatus.label
            } else {
                errorMessage = nil
            }
        } catch let err as SyncBlockedError {
            syncStatus = .blocked(err.localizedDescription)
            errorMessage = err.localizedDescription
        } catch let APIError.http(status, code, _) where status == 401 || code == "unauthorized" {
            // Session expired/revoked (PLAN §9.2). Keep ciphertext; clear Bearer.
            // Server copy is "Sign in again." — drop the full stop for UI labels.
            errorMessage = "Sign in again"
            signOut()
        } catch let APIError.http(status, code, message) where status == 426 || code == "upgrade_required" {
            // Server MIN_IOS_BUILD / MIN_MACOS_BUILD gate (PLAN §10.4).
            syncStatus = .needsUpdate
            errorMessage = message.isEmpty ? SyncStatus.needsUpdate.label : message
        } catch APIError.offline {
            syncStatus = .offline("Offline — changes stay on this device.")
        } catch {
            syncStatus = .offline(error.localizedDescription)
            errorMessage = error.localizedDescription
        }
    }

    /// Load local ciphertext (or pull if empty + signed in), then enter the lists.
    /// Failures that leave nothing to show return to the password gate.
    private func openUnlockedVault() async {
        let ok = await refreshVault()
        if ok {
            phase = .unlocked
            bumpIdle()
            return
        }
        cipherStore = nil
        syncEngine = nil
        vault = nil
        store.hydrate(.empty())
        await crypto.lock()
        phase = .locked
        if !hasBearerSession() {
            errorMessage = "Sign in again"
        } else if errorMessage == nil {
            errorMessage = "Can’t open your vault. Try Sign in again."
        }
    }

    /// Leave the lists and show the password gate (stuck empty / session gone).
    func showSignInGate() {
        if hasBearerSession() {
            errorMessage = "Sign in again"
            signOut()
        } else {
            errorMessage = "Sign in again"
            lock()
            Task { await api.setToken(nil) }
        }
    }

    func unlock(password: String) async {
        errorMessage = nil
        guard password.count >= 10 else {
            errorMessage = "Use at least 10 characters."
            return
        }
        guard let base = URL(string: apiBaseURLString) else {
            errorMessage = "Invalid API URL."
            return
        }
        phase = .unlocking
        await api.setBaseURL(base)

        do {
            if let cached = try sessions.loadAccount(),
               cached.email.lowercased() == email.lowercased()
            {
                do {
                    try await onlineLogin(password: password)
                } catch APIError.offline {
                    try await offlineUnlock(password: password, cached: cached)
                    await openUnlockedVault()
                    return
                }
            } else {
                try await onlineLogin(password: password)
            }
            if phase == .needsRecovery || phase == .needsSecondStep { return }
            await openUnlockedVault()
        } catch {
            if phase != .needsRecovery && phase != .needsSecondStep {
                phase = .locked
            }
            errorMessage = error.localizedDescription
        }
    }

    private func onlineLogin(password: String) async throws {
        clearPendingSecondStep()
        Primitives.ready()
        let pre = try await api.prelogin(email: email)
        let kdf = pre.kdf.params
        try kdf.meetFloor()
        let salt = try Base64Std.decode(pre.salt)
        var (authKey, kek) = try await crypto.beginLogin(password: password, salt: salt, kdf: kdf)

        let passwordLogin = try await api.login(
            email: email,
            authKeyB64: Base64Std.encode(authKey),
            deviceLabel: ClientPlatform.deviceLabel
        )

        if let step = passwordLogin.secondStep {
            if step.methods.contains("passkey") {
                do {
                    let sessionLogin = try await completePasskeySecondStep(token: step.token)
                    try await finishOnlineSession(sessionLogin, kek: kek)
                    Primitives.wipe(&kek)
                } catch PasskeySignIn.Error.cancelled {
                    pendingSecondStep = PendingSecondStep(token: step.token, kek: Array(kek))
                    Primitives.wipe(&kek)
                    phase = .needsSecondStep
                    errorMessage = "Confirm with your sign-in passkey, or use your recovery phrase."
                } catch {
                    pendingSecondStep = PendingSecondStep(token: step.token, kek: Array(kek))
                    Primitives.wipe(&kek)
                    phase = .needsSecondStep
                    errorMessage = "Passkey didn’t work. Try again, or use your recovery phrase."
                }
                return
            }
            Primitives.wipe(&kek)
            phase = .needsRecovery
            errorMessage = "This account needs a second step. Sign in with your recovery phrase."
            return
        }

        try await finishOnlineSession(passwordLogin, kek: kek)
        Primitives.wipe(&kek)
    }

    /// Retry the platform assertion after cancel/fail (PLAN §9.3).
    func continuePasskeySecondStep() async {
        guard let pending = pendingSecondStep else {
            phase = .locked
            return
        }
        errorMessage = nil
        phase = .unlocking
        do {
            let sessionLogin = try await completePasskeySecondStep(token: pending.token)
            try await finishOnlineSession(sessionLogin, kek: pending.kek)
            clearPendingSecondStep()
            await openUnlockedVault()
        } catch PasskeySignIn.Error.cancelled {
            phase = .needsSecondStep
            errorMessage = "Confirm with your sign-in passkey, or use your recovery phrase."
        } catch {
            phase = .needsSecondStep
            errorMessage = error.localizedDescription
        }
    }

    func cancelSecondStep() {
        clearPendingSecondStep()
        phase = .locked
        errorMessage = nil
    }

    /// Open recovery from the second-step screen (wipes held KEK).
    func beginRecoveryFromSecondStep() {
        clearPendingSecondStep()
        phase = .needsRecovery
        errorMessage = nil
    }

    private func clearPendingSecondStep() {
        if var pending = pendingSecondStep {
            Primitives.wipe(&pending.kek)
            pendingSecondStep = nil
        }
    }

    private func finishOnlineSession(_ sessionLogin: LoginResponse, kek: [UInt8]) async throws {
        var kek = kek
        defer { Primitives.wipe(&kek) }
        guard let userId = sessionLogin.userId?.lowercased(),
              let token = sessionLogin.token,
              let wrapped = sessionLogin.wrappedPassword,
              let saltB64 = sessionLogin.salt,
              let kdfDTO = sessionLogin.kdf
        else {
            throw APIError.decoding
        }

        await api.setToken(token)
        try sessions.saveToken(token)

        let deviceWrap = try await crypto.unlockWithPasswordWrap(
            kek: kek,
            userId: userId,
            wrapped: try wrapped.sealed(),
            stayUnlocked: stayUnlocked
        )

        DeviceUnlockPrefs.stayUnlocked = stayUnlocked
        var cached = SessionStore.CachedAccount(
            userId: userId,
            email: email.lowercased(),
            saltB64: saltB64,
            kdf: kdfDTO,
            wrappedPassword: wrapped,
            deviceWrappedAK: deviceWrap.map(WrappedB64.init),
            biometricWrappedAK: (try? sessions.loadAccount())?.biometricWrappedAK,
            passkey: (try? sessions.loadAccount())?.passkey
        )
        if !stayUnlocked { cached.deviceWrappedAK = nil }
        try sessions.saveAccount(cached)
        biometricUnlockAvailable = cached.biometricWrappedAK != nil
        passkeyUnlockAvailable = cached.passkey != nil
        accountEmail = cached.email
        try openPersistence(userId: userId)
    }

    /// `POST …/login/passkey/options` + platform assertion + `POST …/login/passkey`.
    private func completePasskeySecondStep(token: String) async throws -> LoginResponse {
        let optionsData = try await api.loginPasskeyOptionsData(token: token)
        guard let root = try JSONSerialization.jsonObject(with: optionsData) as? [String: Any],
              let options = root["options"] as? [String: Any]
        else { throw APIError.decoding }
        let credential = try await PasskeySignIn.assert(options: options)
        let credentialJSON = try JSONSerialization.data(withJSONObject: credential)
        return try await api.loginPasskey(token: token, credentialJSON: credentialJSON)
    }

    private func offlineUnlock(password: String, cached: SessionStore.CachedAccount) async throws {
        Primitives.ready()
        let kdf = cached.kdf.params
        try kdf.meetFloor()
        let salt = try Base64Std.decode(cached.saltB64)
        let (_, kek) = try await crypto.beginLogin(password: password, salt: salt, kdf: kdf)
        _ = try await crypto.unlockWithPasswordWrap(
            kek: kek,
            userId: cached.userId,
            wrapped: try cached.wrappedPassword.sealed(),
            stayUnlocked: false
        )
        accountEmail = cached.email
        try openPersistence(userId: cached.userId)
    }

    func unlockWithRecovery(phrase: String) async {
        clearPendingSecondStep()
        errorMessage = nil
        // Stay on the recovery screen while working.
        do {
            guard let base = URL(string: apiBaseURLString) else { throw APIError.offline }
            await api.setBaseURL(base)
            let proof = try await crypto.recoveryProofB64(phrase: phrase)
            let start = try await api.recoverStart(email: email, recoveryProofB64: proof)
            try await crypto.unlockFromRecovery(
                phrase: phrase,
                userId: start.userId.lowercased(),
                wrappedRecovery: try start.wrappedRecovery.sealed()
            )
            if let token = try sessions.loadToken() {
                await api.setToken(token)
            }
            accountEmail = email.lowercased()
            try openPersistence(userId: start.userId.lowercased())
            await openUnlockedVault()
        } catch {
            phase = .needsRecovery
            errorMessage = error.localizedDescription
        }
    }

    func refreshBiometryLabel() async {
        biometryLabel = await crypto.biometryName()
        let cached = try? sessions.loadAccount()
        biometricUnlockAvailable = cached?.biometricWrappedAK != nil
        passkeyUnlockAvailable = cached?.passkey != nil
    }

    /// Enable Face ID / Touch ID unlock while the vault is open (PLAN §8.3).
    func setBiometricUnlock(enabled: Bool) async {
        guard phase == .unlocked else { return }
        do {
            guard var cached = try sessions.loadAccount() else { return }
            if enabled {
                let sealed = try await crypto.enableBiometricWrap()
                cached.biometricWrappedAK = WrappedB64(sealed)
                try sessions.saveAccount(cached)
                biometricUnlockAvailable = true
            } else {
                try await crypto.disableBiometricWrap(userId: cached.userId)
                cached.biometricWrappedAK = nil
                try sessions.saveAccount(cached)
                biometricUnlockAvailable = false
            }
        } catch {
            errorMessage = error.localizedDescription
            biometricUnlockAvailable = (try? sessions.loadAccount())?.biometricWrappedAK != nil
        }
    }

    /// Enable device-local passkey PRF unlock while unlocked (PLAN §8.4).
    func setPasskeyUnlock(enabled: Bool) async {
        guard phase == .unlocked else { return }
        do {
            guard var cached = try sessions.loadAccount() else { return }
            if enabled {
                let enrollment = try await PasskeyPRF.enroll(
                    userId: cached.userId,
                    email: cached.email
                )
                var prf = enrollment.prf
                let sealed = try await crypto.wrapForPrf(prf: &prf)
                cached.passkey = SessionStore.PasskeyUnlock(
                    credentialId: Base64Std.encode(enrollment.credentialId),
                    salt: Base64Std.encode(enrollment.salt),
                    wrapped: WrappedB64(sealed)
                )
                try sessions.saveAccount(cached)
                passkeyUnlockAvailable = true
            } else {
                cached.passkey = nil
                try sessions.saveAccount(cached)
                passkeyUnlockAvailable = false
            }
        } catch {
            errorMessage = error.localizedDescription
            passkeyUnlockAvailable = (try? sessions.loadAccount())?.passkey != nil
        }
    }

    func tryDeviceUnlock() async {
        await refreshBiometryLabel()
        // Prefer biometric, then passkey, then stay-unlocked device wrap.
        if let cached = try? sessions.loadAccount(), let wrapped = cached.biometricWrappedAK {
            do {
                try await crypto.unlockFromBiometricWrap(
                    userId: cached.userId,
                    wrapped: try wrapped.sealed()
                )
                try await finishConvenienceUnlock(cached: cached)
                return
            } catch {
                // User cancelled or biometry failed — stay on the password gate.
            }
        }
        guard DeviceUnlockPrefs.stayUnlocked,
              let cached = try? sessions.loadAccount(),
              let wrapped = cached.deviceWrappedAK
        else { return }
        do {
            try await crypto.unlockFromDeviceWrap(
                userId: cached.userId,
                wrapped: try wrapped.sealed()
            )
            try await finishConvenienceUnlock(cached: cached)
        } catch {
            errorMessage = error.localizedDescription
            phase = .locked
        }
    }

    func unlockWithBiometrics() async {
        errorMessage = nil
        guard let cached = try? sessions.loadAccount(),
              let wrapped = cached.biometricWrappedAK
        else { return }
        phase = .unlocking
        do {
            try await crypto.unlockFromBiometricWrap(
                userId: cached.userId,
                wrapped: try wrapped.sealed()
            )
            try await finishConvenienceUnlock(cached: cached)
        } catch {
            phase = .locked
            errorMessage = error.localizedDescription
        }
    }

    func unlockWithPasskey() async {
        errorMessage = nil
        guard let cached = try? sessions.loadAccount(),
              let passkey = cached.passkey
        else { return }
        phase = .unlocking
        do {
            let credentialId = try Base64Std.decode(passkey.credentialId)
            let salt = try Base64Std.decode(passkey.salt)
            var prf = try await PasskeyPRF.assert(credentialId: credentialId, salt: salt)
            try await crypto.unlockWithPrf(
                userId: cached.userId,
                prf: &prf,
                wrapped: try passkey.wrapped.sealed()
            )
            try await finishConvenienceUnlock(cached: cached)
        } catch {
            phase = .locked
            errorMessage = error.localizedDescription
        }
    }

    private func finishConvenienceUnlock(cached: SessionStore.CachedAccount) async throws {
        if let token = try sessions.loadToken() {
            await api.setToken(token)
        }
        accountEmail = cached.email
        email = cached.email
        try openPersistence(userId: cached.userId)
        await openUnlockedVault()
    }

    /// Returns false when there is nothing useful to show (caller should stay on the gate).
    @discardableResult
    func refreshVault() async -> Bool {
        vaultLoading = true
        defer { vaultLoading = false }
        do {
            if cipherStore == nil, let userId = await crypto.currentUserId() {
                try openPersistence(userId: userId)
            }
            guard let cipherStore else {
                errorMessage = "Sign in again"
                return false
            }
            if try await cipherStore.isEmpty() {
                guard hasBearerSession() else {
                    errorMessage = "Sign in again"
                    return false
                }
                let snap = try await VaultPull.pullAll(api: api, crypto: crypto)
                vault = snap
                let e = VaultToEntities.build(from: snap)
                try await cipherStore.replaceAll(e)
                try await cipherStore.markDirty(Incoming.allKeys(e))
                try await cipherStore.setUploaded(true)
                store.hydrate(e)
            } else {
                store.hydrate(try await cipherStore.load())
                vault = VaultSnapshot(entities: [], payloads: [], counts: [:], recordCount: 0, skippedUnknownAlg: 0)
            }
            store.generateRepeats()
            await store.awaitPendingPersist()
            noteEntitiesChanged()
            errorMessage = nil
            await runSync()
            return true
        } catch {
            if store.entities.todos.isEmpty && store.entities.projects.isEmpty {
                errorMessage = error.localizedDescription
                return false
            }
            // Local rows loaded earlier in this attempt — keep them.
            return vault != nil || !store.entities.todos.isEmpty || !store.entities.projects.isEmpty
        }
    }

    /// Lock the vault on this device. Keeps the Bearer session so sync works
    /// after biometric / stay-unlocked reopen (unlike sign-out).
    func lock() {
        clearPendingSecondStep()
        idleTask?.cancel()
        idleTask = nil
        syncTask?.cancel()
        syncTask = nil
        vault = nil
        cipherStore = nil
        syncEngine = nil
        syncStatus = .idle
        showSettings = false
        // Lock first so noteEntitiesChanged does not clear pending notifications.
        phase = .locked
        store.hydrate(.empty())
        entitiesEpoch += 1
        Task { await crypto.lock() }
    }

    /// Revoke the server session and clear the Keychain token (Settings / 401).
    func signOut() {
        let tokenStillPresent = (try? sessions.loadToken()) != nil
        lock()
        Task {
            if tokenStillPresent {
                try? await api.logout()
            }
            await api.setToken(nil)
        }
        try? sessions.deleteToken()
    }

    /// Delete the account on the server and wipe this device (PLAN §9.5).
    func deleteAccount(password: String) async -> Bool {
        errorMessage = nil
        guard phase == .unlocked else { return false }
        guard password.count >= 10 else {
            errorMessage = "Use at least 10 characters."
            return false
        }
        guard let cached = try? sessions.loadAccount() else {
            errorMessage = "No account on this device."
            return false
        }
        do {
            Primitives.ready()
            let kdf = cached.kdf.params
            try kdf.meetFloor()
            let salt = try Base64Std.decode(cached.saltB64)
            let (authKey, kek) = try await crypto.beginLogin(
                password: password,
                salt: salt,
                kdf: kdf
            )
            var wipeKek = kek
            Primitives.wipe(&wipeKek)
            try await api.deleteAccount(authKeyB64: Base64Std.encode(authKey))
            let userId = cached.userId
            try? await crypto.disableBiometricWrap(userId: userId)
            await ReminderScheduler.clearAll()
            idleTask?.cancel()
            idleTask = nil
            syncTask?.cancel()
            syncTask = nil
            showSettings = false
            vault = nil
            cipherStore = nil
            syncEngine = nil
            syncStatus = .idle
            store.hydrate(.empty())
            entitiesEpoch += 1
            phase = .locked
            await api.setToken(nil)
            await crypto.lock()
            try? sessions.clear()
            try? AppDatabase.remove(userId: userId)
            accountEmail = nil
            biometricUnlockAvailable = false
            passkeyUnlockAvailable = false
            clearPendingSecondStep()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func bumpIdle() {
        idleTask?.cancel()
        guard !stayUnlocked else { return }
        idleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15 * 60))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.lock() }
        }
    }

    func scenePhaseChanged(_ scene: ScenePhase) {
        if scene == .active {
            bumpIdle()
            scheduleRemindersIfUnlocked()
        }
    }
}
