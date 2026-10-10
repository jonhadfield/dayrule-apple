import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable {
        case locked
        case unlocking
        case showRecovery([String])
        case unlocked
    }

    var phase: Phase = .locked
    var errorMessage: String?
    var stayUnlocked = false
    /// Device-wrapped AK for stay-unlocked (M1 local only).
    private(set) var deviceWrappedAK: Primitives.Sealed?
    private(set) var localUserId: String?

    let crypto = CryptoActor()
    private var idleTask: Task<Void, Never>?

    func unlock(password: String) async {
        errorMessage = nil
        guard password.count >= 10 else {
            errorMessage = "Use at least 10 characters."
            return
        }
        phase = .unlocking
        do {
            let userId = (localUserId ?? UUID().uuidString).lowercased()
            localUserId = userId
            let salt = Primitives.randomBytes(CryptoConstants.saltBytes)
            let result = try await crypto.unlockWithPassword(
                password: password,
                userId: userId,
                salt: salt
            )
            deviceWrappedAK = result.wrappedDevice
            phase = .showRecovery(result.recoveryWords)
            bumpIdle()
        } catch {
            phase = .locked
            errorMessage = error.localizedDescription
        }
    }

    func confirmRecoverySaved() {
        phase = .unlocked
        bumpIdle()
    }

    func tryDeviceUnlock() async {
        guard stayUnlocked,
              let userId = localUserId,
              let wrapped = deviceWrappedAK
        else { return }
        do {
            try await crypto.unlockFromDeviceWrap(userId: userId, wrapped: wrapped)
            phase = .unlocked
            bumpIdle()
        } catch {
            errorMessage = error.localizedDescription
            phase = .locked
        }
    }

    func lock() {
        idleTask?.cancel()
        idleTask = nil
        Task { await crypto.lock() }
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
        if scene == .active {
            bumpIdle()
        }
    }
}
