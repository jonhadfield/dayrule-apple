import Foundation
import Testing
@testable import Dayrule

@Suite("AppModel Settings list refresh hold")
struct AppModelSettingsHoldTests {
    @MainActor
    @Test("Settings hold defers entitiesEpoch until flush")
    func holdDefersEpochBump() {
        let model = AppModel()
        model.testingSetPhase(.unlocked)
        let epoch = model.entitiesEpoch

        model.beginSettingsPresentation()
        #expect(model.testingSettingsHoldsListRefresh)

        model.noteEntitiesChanged(animation: nil)
        #expect(model.entitiesEpoch == epoch)
        #expect(model.testingListRefreshPending)

        model.testingFlushPendingListRefresh()
        #expect(model.entitiesEpoch == epoch + 1)
        #expect(!model.testingListRefreshPending)
        #expect(!model.testingSettingsHoldsListRefresh)
    }

    @MainActor
    @Test("without Settings hold, sync refresh bumps epoch immediately")
    func noHoldBumpsImmediately() {
        let model = AppModel()
        model.testingSetPhase(.unlocked)
        let epoch = model.entitiesEpoch

        model.testingEntitiesDidChangeFromSync()
        #expect(model.entitiesEpoch == epoch + 1)
        #expect(!model.testingListRefreshPending)
    }

    @MainActor
    @Test("endSettingsPresentation flushes after the dismiss delay")
    func endSettingsFlushesAfterDelay() async {
        let model = AppModel()
        model.testingSetPhase(.unlocked)
        let epoch = model.entitiesEpoch

        model.beginSettingsPresentation()
        model.noteEntitiesChanged(animation: nil)
        #expect(model.testingListRefreshPending)

        model.endSettingsPresentation()
        #expect(model.entitiesEpoch == epoch)

        try? await Task.sleep(for: .milliseconds(250))
        #expect(model.entitiesEpoch == epoch + 1)
        #expect(!model.testingListRefreshPending)
        #expect(!model.testingSettingsHoldsListRefresh)
    }
}
