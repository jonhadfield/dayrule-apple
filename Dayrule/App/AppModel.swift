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
    /// Gate and auth outcomes, plus the last sync problem (gate and vault-missing row).
    /// Other unlocked-phase errors go to `notices`.
    var errorMessage: String? {
        didSet { gateMessageIsInfo = false }
    }
    /// True when `errorMessage` is guidance rather than a failure (gate shows it muted).
    private(set) var gateMessageIsInfo = false
    /// A gate action (unlock, recovery, passkey, signup step) is running.
    private(set) var gateBusy = false
    /// True until the launch-time device / biometric unlock attempt has finished.
    private(set) var isRestoringSession = true
    /// Set after the first successful sync since unlock (empty lists stop saying "Syncing…").
    private(set) var hasCompletedInitialSync = false
    var stayUnlocked = DeviceUnlockPrefs.stayUnlocked
    /// Bumped on sign-out / account delete so the Gate clears password fields.
    private(set) var gateResetEpoch = 0
    var email = ""
    /// Debug Gate override. Blank means `APIConfig.defaultBaseURLString`.
    var apiBaseURLString = ""
    var vault: VaultSnapshot?
    var vaultLoading = false
    var accountEmail: String?
    var syncStatus: SyncStatus = .idle
    var showSettings = false
    /// Quick Find overlay (toolbar, Mac menu ⌘F).
    var showFind = false
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
    let linger = LingerStore()
    let notices = NoticeCenter()
    /// Bumped when `store.entities` changes so Observation refreshes views.
    private(set) var entitiesEpoch = 0
    private let sessions = SessionStore()
    private var api: APIClient
    private var idleTask: Task<Void, Never>?
    private var cipherStore: CipherStore?
    private var syncEngine: SyncEngine?
    private var syncTask: Task<Void, Never>?
    private var syncPollTask: Task<Void, Never>?
    /// Sync now / pull-to-refresh callers waiting on the running pass.
    private var syncWaiters: [CheckedContinuation<Void, Never>] = []
    private var syncInFlight = false
    /// Set while a sync is running so a concurrent request re-runs after.
    private var syncAgain = false
    private var sceneIsActive = true
    private var lastIdleBump: ContinuousClock.Instant?

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

    /// A user edit changed `store.entities`: refresh views and count it as activity.
    /// Any Undo notice on screen now refers to an older entry, so it goes; callers that
    /// want one post it after this.
    func noteEntitiesChanged(animation: Animation? = Motion.list) {
        notices.dismissUndo()
        entitiesDidChange(animation: animation)
        noteUserActivity()
    }

    /// Sync, persist and hydrate paths: refresh views without resetting the idle lock.
    private func entitiesDidChange(animation: Animation?) {
        if let animation {
            withAnimation(Motion.system(animation)) { entitiesEpoch += 1 }
        } else {
            entitiesEpoch += 1
        }
        scheduleRemindersIfUnlocked()
    }

    /// Real user activity keeps the vault open; throttled so typing doesn't churn tasks.
    func noteUserActivity() {
        guard phase == .unlocked else { return }
        if let lastIdleBump, ContinuousClock.now - lastIdleBump < .seconds(10) { return }
        bumpIdle()
    }

    func undoLast() {
        guard store.undo() != nil else { return }
        noteEntitiesChanged()
    }

    /// Show `message` with an Undo action for the last store change. Undo only acts while
    /// that change is still the newest history entry.
    func undoNotice(_ message: String) {
        let depth = store.past.count
        notices.post(.undo(message) { [weak self] in
            guard let self, self.store.past.count == depth else { return }
            self.undoLast()
        })
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
    /// Holds `gateBusy` for the silent device-wrap path so a concurrent
    /// convenience unlock cannot finish during `await crypto.lock()` and leave
    /// unlocked UI with a zeroed AK (audit run-2 post-phase-check TOCTOU).
    func handleBackgroundReminderRefresh() async {
        guard DeviceReminderPrefs.enabled, DeviceUnlockPrefs.stayUnlocked else { return }
        if phase == .unlocked {
            await ReminderScheduler.reschedule(entities: store.entities)
            ReminderBackgroundRefresh.scheduleIfNeeded()
            return
        }
        guard !gateBusy else {
            ReminderBackgroundRefresh.scheduleIfNeeded()
            return
        }
        guard let cached = try? sessions.loadAccount(),
              let wrapped = cached.deviceWrappedAK
        else { return }
        gateBusy = true
        defer { gateBusy = false }
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
            // Defense in depth: a path that bypassed gateBusy should not be torn down.
            if phase == .unlocked { return }
            #if DEBUG
            if let hook = testingBeforeBackgroundEpilogueLock {
                await hook()
                if phase == .unlocked { return }
            }
            #endif
            cipherStore = nil
            syncEngine = nil
            await crypto.lock()
        } catch {
            if phase == .unlocked { return }
            cipherStore = nil
            syncEngine = nil
            await crypto.lock()
        }
        ReminderBackgroundRefresh.scheduleIfNeeded()
    }
    #endif

    init() {
        let defaultAPI = APIConfig.defaultBaseURLString
        apiBaseURLString = APIConfig.hasLaunchOverride ? defaultAPI : ""
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
        guard !gateBusy else { return }
        errorMessage = nil
        gateBusy = true
        signupBusy = true
        defer {
            signupBusy = false
            gateBusy = false
        }
        do {
            guard let base = APIConfig.resolvedBaseURL(apiBaseURLString) else { throw APIError.offline }
            await api.setBaseURL(base)
            try await api.signupStart(email: email, inviteCode: inviteCode.trimmingCharacters(in: .whitespacesAndNewlines))
            signupToken = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signupVerifyCode() async {
        guard !gateBusy else { return }
        errorMessage = nil
        gateBusy = true
        signupBusy = true
        defer {
            signupBusy = false
            gateBusy = false
        }
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
            #if os(iOS)
            ReminderBackgroundRefresh.scheduleIfNeeded()
            #endif
            if !stayUnlocked {
                try? await crypto.forgetDeviceWrapOnly(userId: pending.userId)
            }
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
            entitiesDidChange(animation: source == .sync ? Motion.fade : nil)
            if source == .local { scheduleSync() }
        } catch {
            notices.post(Notice(kind: .error, message: error.localizedDescription))
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
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await self?.runSync()
        }
    }

    /// Local changes still waiting in the outbox (Settings sign-out warning).
    func hasPendingChanges() async -> Bool {
        await store.awaitPendingPersist()
        let pending = (try? await cipherStore?.pendingKeys()) ?? []
        return !pending.isEmpty
    }

    /// Settings → Sync now: flush local writes, then pull/push (do not re-hydrate).
    /// If a pass is already running, waits for it so `.refreshable` tracks real work.
    func syncNow() async {
        guard syncInFlight else {
            await runSync()
            return
        }
        await withCheckedContinuation { syncWaiters.append($0) }
    }

    /// While unlocked and the AK is in memory (PLAN §10.3). Mac `scenePhase` is
    /// unreliable, so poll regardless of active/inactive — only lock stops it.
    private func startSyncPoll() {
        syncPollTask?.cancel()
        guard phase == .unlocked else { return }
        syncPollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { return }
                guard let self, self.phase == .unlocked else { continue }
                await self.runSync()
            }
        }
    }

    private func stopSyncPoll() {
        syncPollTask?.cancel()
        syncPollTask = nil
    }

    private func hasBearerSession() -> Bool {
        (try? sessions.loadToken()) != nil
    }

    /// Unlocked locally but no Bearer — Adds stay on device until password sign-in.
    var needsServerSignIn: Bool {
        phase == .unlocked && !hasBearerSession()
    }

    private func runSync() async {
        guard syncEngine != nil else { return }
        if syncInFlight {
            syncAgain = true
            return
        }
        // Prefer Keychain over a stale in-memory token (actor may lag after unlock).
        guard let token = try? sessions.loadToken() else {
            syncStatus = .offline("Sign in to sync.")
            return
        }
        await api.setToken(token)

        syncInFlight = true
        syncStatus = .syncing
        defer {
            syncInFlight = false
            let waiters = syncWaiters
            syncWaiters = []
            waiters.forEach { $0.resume() }
            if syncAgain {
                syncAgain = false
                Task { await self.runSync() }
            }
        }
        // Local Add must hit the outbox before we read it.
        await store.awaitPendingPersist()
        guard let syncEngine else { return }
        do {
            try await syncEngine.sync()
            entitiesDidChange(animation: Motion.fade)
            hasCompletedInitialSync = true
            let pending = (try? await cipherStore?.pendingKeys()) ?? []
            if syncEngine.sawUnknownAlg {
                syncStatus = .needsUpdate
            } else if !pending.isEmpty {
                // Push ran but rows remain — surface it instead of a false "Up to date".
                let waiting = AttributedString(
                    localized: "Sync incomplete — ^[\(pending.count) change](inflect: true) still waiting."
                )
                syncStatus = .offline(String(waiting.characters))
            } else {
                syncStatus = .synced
            }
            if case .needsUpdate = syncStatus {
                errorMessage = syncStatus.label
            } else if case .offline = syncStatus {
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
            startSyncPoll()
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

    /// Leave the lists and show the password gate (session missing / sync blocked).
    func showSignInGate() {
        errorMessage = "Sign in with your password to sync."
        gateMessageIsInfo = true
        if hasBearerSession() {
            signOut()
        } else {
            Task {
                await lock()
                await api.setToken(nil)
            }
        }
    }

    func unlock(password: String) async {
        guard !gateBusy else { return }
        gateBusy = true
        defer { gateBusy = false }
        errorMessage = nil
        guard password.count >= 10 else {
            errorMessage = "Use at least 10 characters."
            return
        }
        guard let base = APIConfig.resolvedBaseURL(apiBaseURLString) else {
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
        guard !gateBusy else { return }
        guard let pending = pendingSecondStep else {
            phase = .locked
            return
        }
        gateBusy = true
        defer { gateBusy = false }
        errorMessage = nil
        // Stay on the second-step screen while working.
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

        let previous = try? sessions.loadAccount()
        let deviceWrap = try await crypto.unlockWithPasswordWrap(
            kek: kek,
            userId: userId,
            wrapped: try wrapped.sealed(),
            stayUnlocked: stayUnlocked
        )
        if !stayUnlocked {
            // Drop any prior stay-unlocked Keychain key for this user.
            try? await crypto.forgetDeviceWrapOnly(userId: userId)
        }

        DeviceUnlockPrefs.stayUnlocked = stayUnlocked
        #if os(iOS)
        ReminderBackgroundRefresh.scheduleIfNeeded()
        #endif
        var cached = SessionStore.CachedAccount(
            userId: userId,
            email: email.lowercased(),
            saltB64: saltB64,
            kdf: kdfDTO,
            wrappedPassword: wrapped,
            deviceWrappedAK: deviceWrap.map(WrappedB64.init),
            biometricWrappedAK: previous?.userId == userId ? previous?.biometricWrappedAK : nil,
            passkey: previous?.userId == userId ? previous?.passkey : nil
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
        guard !gateBusy else { return }
        gateBusy = true
        defer { gateBusy = false }
        clearPendingSecondStep()
        errorMessage = nil
        // Stay on the recovery screen while working.
        do {
            guard let base = APIConfig.resolvedBaseURL(apiBaseURLString) else { throw APIError.offline }
            await api.setBaseURL(base)
            let proof = try await crypto.recoveryProofB64(phrase: phrase)
            let start = try await api.recoverStart(email: email, recoveryProofB64: proof)
            let recoveredId = start.userId.lowercased()
            try await crypto.unlockFromRecovery(
                phrase: phrase,
                userId: recoveredId,
                wrappedRecovery: try start.wrappedRecovery.sealed()
            )
            let cachedUserId = try sessions.loadAccount()?.userId
            if SessionBinding.canReuseBearer(
                unlockedUserId: recoveredId,
                cachedUserId: cachedUserId
            ),
               let token = try sessions.loadToken()
            {
                await api.setToken(token)
            } else {
                try? sessions.deleteToken()
                await api.setToken(nil)
            }
            accountEmail = email.lowercased()
            try openPersistence(userId: recoveredId)
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
    /// Returns the failure message, if any, for the caller (Settings) to show inline.
    @discardableResult
    func setBiometricUnlock(enabled: Bool) async -> String? {
        guard phase == .unlocked else { return nil }
        do {
            guard var cached = try sessions.loadAccount() else { return nil }
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
            biometricUnlockAvailable = (try? sessions.loadAccount())?.biometricWrappedAK != nil
            return error.localizedDescription
        }
        return nil
    }

    /// Enable device-local passkey PRF unlock while unlocked (PLAN §8.4).
    /// Returns the failure message, if any, for the caller (Settings) to show inline.
    @discardableResult
    func setPasskeyUnlock(enabled: Bool) async -> String? {
        guard phase == .unlocked else { return nil }
        do {
            guard var cached = try sessions.loadAccount() else { return nil }
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
            passkeyUnlockAvailable = (try? sessions.loadAccount())?.passkey != nil
            return error.localizedDescription
        }
        return nil
    }

    func tryDeviceUnlock() async {
        defer { isRestoringSession = false }
        guard !gateBusy else { return }
        gateBusy = true
        defer { gateBusy = false }
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
        guard !gateBusy else { return }
        errorMessage = nil
        guard let cached = try? sessions.loadAccount(),
              let wrapped = cached.biometricWrappedAK
        else { return }
        gateBusy = true
        defer { gateBusy = false }
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
        guard !gateBusy else { return }
        errorMessage = nil
        guard let cached = try? sessions.loadAccount(),
              let passkey = cached.passkey
        else { return }
        gateBusy = true
        defer { gateBusy = false }
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
        linger.clear()
        notices.clear()
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
            entitiesDidChange(animation: nil)
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
    /// after biometric / stay-unlocked reopen (unlike sign-out). Awaits AK wipe
    /// so callers that `await lock()` do not proceed while the key is still held.
    func lock() async {
        applyLockedUI()
        await crypto.lock()
    }

    /// Clear unlocked UI synchronously (phase, store, sync). Does not wipe the AK.
    private func applyLockedUI() {
        showFind = false
        clearPendingSecondStep()
        idleTask?.cancel()
        idleTask = nil
        lastIdleBump = nil
        syncTask?.cancel()
        syncTask = nil
        stopSyncPoll()
        vault = nil
        cipherStore = nil
        syncEngine = nil
        syncStatus = .idle
        hasCompletedInitialSync = false
        showSettings = false
        linger.clear()
        notices.clear()
        // Lock UI first so noteEntitiesChanged does not clear pending notifications.
        phase = .locked
        store.hydrate(.empty())
        entitiesEpoch += 1
    }

    /// User chose Lock: drop any stale gate message (lock() keeps it for signOut / 401).
    func lockNow() {
        errorMessage = nil
        Task { await lock() }
    }

    /// Revoke the server session and forget this device's account identity
    /// (email, password wrap, stay-unlocked / biometrics / passkey). Ciphertext
    /// stays on disk until the same account signs in again — matches web
    /// `signOut` → `forgetDevice` + `profiles.clear()` (session.ts).
    func signOut() {
        let tokenStillPresent = (try? sessions.loadToken()) != nil
        let userId = (try? sessions.loadAccount())?.userId

        // Drop Keychain identity first so a relaunch cannot tryDeviceUnlock
        // or prefill email before the async Keychain wipe finishes.
        try? sessions.clear()
        stayUnlocked = false
        DeviceUnlockPrefs.stayUnlocked = false
        biometricUnlockAvailable = false
        passkeyUnlockAvailable = false
        accountEmail = nil
        email = ""
        inviteCode = ""
        signupCode = ""
        signupToken = nil
        pendingRecoveryWords = []
        pendingSignup = nil
        clearPendingSecondStep()
        gateResetEpoch += 1

        applyLockedUI()
        Task {
            await crypto.lock()
            if let userId {
                try? await crypto.forgetDevice(userId: userId)
            }
            await ReminderScheduler.clearAll()
            if tokenStillPresent {
                try? await api.logout()
            }
            await api.setToken(nil)
        }
    }

    #if DEBUG
    /// Test hook: hold or release `gateBusy` without starting a gate action.
    func testingSetGateBusy(_ busy: Bool) {
        gateBusy = busy
    }

    /// Invoked after the unlocked-phase check on the BG success path, before
    /// tearing down the silent device-wrap session (concurrency tests).
    var testingBeforeBackgroundEpilogueLock: (@MainActor () async -> Void)?

    /// Seed Keychain-cached account material for lock / BG tests.
    func testingSaveCachedAccount(_ account: SessionStore.CachedAccount) throws {
        try sessions.saveAccount(account)
    }
    #endif

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
            try? await crypto.forgetDevice(userId: userId)
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
            hasCompletedInitialSync = false
            linger.clear()
            notices.clear()
            store.hydrate(.empty())
            entitiesEpoch += 1
            phase = .locked
            await api.setToken(nil)
            await crypto.lock()
            try? sessions.clear()
            try? AppDatabase.remove(userId: userId)
            accountEmail = nil
            email = ""
            inviteCode = ""
            signupCode = ""
            signupToken = nil
            pendingRecoveryWords = []
            pendingSignup = nil
            stayUnlocked = false
            DeviceUnlockPrefs.stayUnlocked = false
            biometricUnlockAvailable = false
            passkeyUnlockAvailable = false
            clearPendingSecondStep()
            gateResetEpoch += 1
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func bumpIdle() {
        idleTask?.cancel()
        lastIdleBump = .now
        guard !stayUnlocked else { return }
        idleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15 * 60))
            guard !Task.isCancelled else { return }
            await self?.lock()
        }
    }

    func scenePhaseChanged(_ scene: ScenePhase) {
        sceneIsActive = scene == .active
        if scene == .active {
            bumpIdle()
            scheduleRemindersIfUnlocked()
            if phase == .unlocked {
                // Pull peer writes when returning to the foreground (PLAN §10.3).
                startSyncPoll()
                Task { await runSync() }
            }
        } else if scene == .background {
            // Keep polling through brief macOS inactive blips; only flush+pause
            // when the scene is actually backgrounded.
            if phase == .unlocked, hasBearerSession() {
                Task { await runSync() }
            }
        }
    }

    /// macOS: `scenePhase` often stays `.inactive` while the window is usable.
    func applicationBecameActive() {
        sceneIsActive = true
        bumpIdle()
        guard phase == .unlocked else { return }
        startSyncPoll()
        Task { await runSync() }
    }
}
