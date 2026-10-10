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

    var entities: Entities {
        _ = entitiesEpoch
        return store.entities
    }

    func noteEntitiesChanged() {
        entitiesEpoch += 1
    }

    init() {
        api = APIClient(baseURL: URL(string: "http://127.0.0.1:8080")!)
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
        do {
            try await syncEngine.sync()
            noteEntitiesChanged()
            errorMessage = nil
        } catch {
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
                    return
                }
            } else {
                try await onlineLogin(password: password)
            }
            if phase == .needsRecovery { return }
            bumpIdle()
            await refreshVault()
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
        phase = .unlocked
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
        phase = .unlocked
        bumpIdle()
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
            phase = .unlocked
            bumpIdle()
            await refreshVault()
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
            phase = .unlocked
            bumpIdle()
            await refreshVault()
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
