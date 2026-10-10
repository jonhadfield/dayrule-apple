import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable {
        case locked
        case unlocking
        case needsRecovery
        case signup
        case confirmRecovery
        case unlocked
    }

    var phase: Phase = .locked
    var errorMessage: String?
    var stayUnlocked = false
    var email = ""
    var apiBaseURLString = "http://127.0.0.1:8080"
    var vault: VaultSnapshot?
    var vaultLoading = false
    var accountEmail: String?
    var syncStatus: SyncStatus = .idle
    var showSettings = false

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

    var entities: Entities {
        _ = entitiesEpoch
        return store.entities
    }

    func noteEntitiesChanged() {
        entitiesEpoch += 1
    }

    init() {
        let env = ProcessInfo.processInfo.environment
        let defaultAPI = env["DAYRULE_API"] ?? "http://127.0.0.1:8080"
        apiBaseURLString = defaultAPI
        api = APIClient(baseURL: URL(string: defaultAPI) ?? URL(string: "http://127.0.0.1:8080")!)
        if let cached = try? sessions.loadAccount() {
            email = cached.email
            accountEmail = cached.email
        }
        if let token = try? sessions.loadToken() {
            Task { await api.setToken(token) }
        }
        store.onChanges = { [weak self] changes, source in
            await self?.persist(changes, source: source)
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
        guard password.count >= 10 else {
            errorMessage = "Use at least 10 characters."
            return
        }
        guard password == confirm else {
            errorMessage = "Passwords don’t match."
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
            let cached = SessionStore.CachedAccount(
                userId: pending.userId,
                email: pending.email,
                saltB64: Base64Std.encode(pending.salt),
                kdf: KdfDTO(v: pending.created.kdf.v, ops: pending.created.kdf.ops, mem: pending.created.kdf.mem),
                wrappedPassword: WrappedB64(pending.created.wrappedPassword),
                deviceWrappedAK: stayUnlocked ? WrappedB64(pending.created.wrappedDevice) : nil
            )
            try sessions.saveAccount(cached)
            accountEmail = pending.email
            email = pending.email
            try openPersistence(userId: pending.userId)
            pendingSignup = nil
            pendingRecoveryWords = []
            signupToken = nil
            // Pull before unlocking the list UI so hydrate can't wipe a concurrent Add.
            await refreshVault()
            phase = .unlocked
            bumpIdle()
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

    private func runSync() async {
        guard let syncEngine else { return }
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
        } catch APIError.offline {
            syncStatus = .offline("Offline — changes stay on this device.")
        } catch {
            syncStatus = .offline(error.localizedDescription)
            errorMessage = error.localizedDescription
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
                    await refreshVault()
                    phase = .unlocked
                    bumpIdle()
                    return
                }
            } else {
                try await onlineLogin(password: password)
            }
            if phase == .needsRecovery { return }
            await refreshVault()
            phase = .unlocked
            bumpIdle()
        } catch {
            if phase != .needsRecovery {
                phase = .locked
            }
            errorMessage = error.localizedDescription
        }
    }

    private func onlineLogin(password: String) async throws {
        let pre = try await api.prelogin(email: email)
        let kdf = pre.kdf.params
        try kdf.meetFloor()
        let salt = try Base64Std.decode(pre.salt)
        let (authKey, kek) = try await crypto.beginLogin(password: password, salt: salt, kdf: kdf)

        let login = try await api.login(
            email: email,
            authKeyB64: Base64Std.encode(authKey),
            deviceLabel: ClientPlatform.deviceLabel
        )

        if login.secondStep != nil {
            phase = .needsRecovery
            errorMessage = "This account needs a second step. Sign in with your recovery phrase."
            return
        }

        guard let userId = login.userId?.lowercased(),
              let token = login.token,
              let wrapped = login.wrappedPassword,
              let saltB64 = login.salt,
              let kdfDTO = login.kdf
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

        var cached = SessionStore.CachedAccount(
            userId: userId,
            email: email.lowercased(),
            saltB64: saltB64,
            kdf: kdfDTO,
            wrappedPassword: wrapped,
            deviceWrappedAK: deviceWrap.map(WrappedB64.init)
        )
        if !stayUnlocked { cached.deviceWrappedAK = nil }
        try sessions.saveAccount(cached)
        accountEmail = cached.email
        try openPersistence(userId: userId)
    }

    private func offlineUnlock(password: String, cached: SessionStore.CachedAccount) async throws {
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
            await refreshVault()
            phase = .unlocked
            bumpIdle()
        } catch {
            phase = .needsRecovery
            errorMessage = error.localizedDescription
        }
    }

    func tryDeviceUnlock() async {
        guard stayUnlocked,
              let cached = try? sessions.loadAccount(),
              let wrapped = cached.deviceWrappedAK
        else { return }
        do {
            try await crypto.unlockFromDeviceWrap(
                userId: cached.userId,
                wrapped: try wrapped.sealed()
            )
            if let token = try sessions.loadToken() {
                await api.setToken(token)
            }
            accountEmail = cached.email
            email = cached.email
            try openPersistence(userId: cached.userId)
            await refreshVault()
            phase = .unlocked
            bumpIdle()
        } catch {
            errorMessage = error.localizedDescription
            phase = .locked
        }
    }

    func refreshVault() async {
        vaultLoading = true
        defer { vaultLoading = false }
        do {
            if cipherStore == nil, let userId = await crypto.currentUserId() {
                try openPersistence(userId: userId)
            }
            guard let cipherStore else {
                throw APIError.offline
            }
            if try await cipherStore.isEmpty() {
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
        } catch {
            if store.entities.todos.isEmpty && store.entities.projects.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }

    func lock() {
        idleTask?.cancel()
        idleTask = nil
        syncTask?.cancel()
        syncTask = nil
        vault = nil
        cipherStore = nil
        syncEngine = nil
        syncStatus = .idle
        showSettings = false
        store.hydrate(.empty())
        noteEntitiesChanged()
        Task {
            try? await api.logout()
            await api.setToken(nil)
            await crypto.lock()
        }
        try? sessions.deleteToken()
        phase = .locked
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
        if scene == .active { bumpIdle() }
    }
}
