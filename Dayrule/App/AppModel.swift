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
    var entities = Entities.empty()
    var vaultLoading = false
    var accountEmail: String?

    let crypto = CryptoActor()
    private let sessions = SessionStore()
    private var api: APIClient
    private var idleTask: Task<Void, Never>?

    init() {
        api = APIClient(baseURL: URL(string: "http://127.0.0.1:8080")!)
        if let cached = try? sessions.loadAccount() {
            email = cached.email
            accountEmail = cached.email
        }
        if let token = try? sessions.loadToken() {
            Task { await api.setToken(token) }
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
            let snap = try await VaultPull.pullAll(api: api, crypto: crypto)
            vault = snap
            entities = VaultToEntities.build(from: snap)
            errorMessage = nil
        } catch {
            if vault == nil {
                errorMessage = error.localizedDescription
            }
        }
    }

    func lock() {
        idleTask?.cancel()
        idleTask = nil
        vault = nil
        entities = .empty()
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
