import Foundation
import Testing
@testable import Dayrule

@Suite("SyncFailureMapping")
struct SyncFailureMappingTests {
    @Test("HTTP 426 / upgrade_required maps to needsUpdate")
    func upgradeRequired() {
        let byStatus = SyncFailureMapping.effect(
            for: APIError.http(status: 426, code: "", message: "")
        )
        #expect(byStatus.status == .needsUpdate)
        #expect(byStatus.errorMessage == SyncStatus.needsUpdate.label)
        #expect(!byStatus.signOut)

        let byCode = SyncFailureMapping.effect(
            for: APIError.http(status: 400, code: "upgrade_required", message: "Please update.")
        )
        #expect(byCode.status == .needsUpdate)
        #expect(byCode.errorMessage == "Please update.")
        #expect(!byCode.signOut)
    }

    @Test("401 unauthorized signs out")
    func unauthorized() {
        let effect = SyncFailureMapping.effect(
            for: APIError.http(status: 401, code: "unauthorized", message: "Sign in again.")
        )
        #expect(effect.status == nil)
        #expect(effect.errorMessage == "Sign in again")
        #expect(effect.signOut)
    }

    @Test("offline keeps a local-only message")
    func offline() {
        let effect = SyncFailureMapping.effect(for: APIError.offline)
        #expect(effect.status == .offline("Offline — changes stay on this device."))
        #expect(effect.errorMessage == "Offline — changes stay on this device.")
        #expect(!effect.signOut)
    }
}
