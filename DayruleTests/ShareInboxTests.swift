import CryptoKit
import Foundation
import Testing
@testable import Dayrule

@Suite("ShareInbox")
struct ShareInboxTests {
    private let testKey = [UInt8](repeating: 0x42, count: 32)

    private func withTempQueue<T>(_ body: (URL) throws -> T) throws -> T {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dayrule-share-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let queue = dir.appendingPathComponent("queue.json")
        ShareInboxSupport.queueURLOverride = queue
        ShareInboxSupport.keyOverride = testKey
        defer {
            ShareInboxSupport.queueURLOverride = nil
            ShareInboxSupport.keyOverride = nil
            try? FileManager.default.removeItem(at: dir)
        }
        return try body(queue)
    }

    @Test func enqueueAndDrainRoundTrip() throws {
        try withTempQueue { _ in
            try ShareInboxQueue.enqueue(title: " Buy milk ")
            try ShareInboxQueue.enqueue(title: "https://example.com")
            let titles = try ShareInboxQueue.drainTitles()
            #expect(titles == ["Buy milk", "https://example.com"])
            #expect(try ShareInboxQueue.drainTitles().isEmpty)
        }
    }

    @Test func enqueueIgnoresEmptyAndWhitespaceTitles() throws {
        try withTempQueue { queue in
            try ShareInboxQueue.enqueue(title: "")
            try ShareInboxQueue.enqueue(title: "   \n\t  ")
            #expect(!FileManager.default.fileExists(atPath: queue.path))
            #expect(try ShareInboxQueue.drainTitles().isEmpty)
        }
    }

    @Test func drainThrowsOnCorruptEnvelopeAndLeavesQueue() throws {
        try withTempQueue { queue in
            let junk = Data("""
            [{"v":1,"id":"bad","createdAt":"t","nonceB64":"!!!","ciphertextB64":"!!!"}]
            """.utf8)
            try junk.write(to: queue)

            #expect(throws: ShareInboxError.corruptQueue) {
                try ShareInboxQueue.drainTitles()
            }
            #expect(FileManager.default.fileExists(atPath: queue.path))
            let left = try Data(contentsOf: queue)
            #expect(left == junk)
        }
    }

    @Test func drainThrowsOnUnknownFormatVersion() throws {
        try withTempQueue { queue in
            let junk = Data("""
            [{"v":99,"id":"old","createdAt":"t","nonceB64":"AAAAAAAAAAAA","ciphertextB64":"AAAA"}]
            """.utf8)
            try junk.write(to: queue)

            #expect(throws: ShareInboxError.corruptQueue) {
                try ShareInboxQueue.drainTitles()
            }
        }
    }

    @Test func pickedTitlePrefersURLOverPlainText() {
        let title = ShareInboxPickedTitle.resolve(
            urlString: "https://dayrule.app",
            plainText: "ignored body",
            attributedText: "ignored attr"
        )
        #expect(title == "https://dayrule.app")
    }

    @Test func pickedTitleUsesPlainTextWhenNoURL() {
        #expect(
            ShareInboxPickedTitle.resolve(plainText: " Buy milk ") == " Buy milk "
        )
    }

    @Test func pickedTitleFallsBackToAttributedThenEmpty() {
        #expect(
            ShareInboxPickedTitle.resolve(attributedText: "From preview") == "From preview"
        )
        #expect(ShareInboxPickedTitle.resolve(urlString: "  ", plainText: "\n") == "")
        #expect(ShareInboxPickedTitle.resolve() == "")
    }

    #if os(iOS)
    @MainActor
    @Test func ingestAddsInboxTodosWhenUnlocked() throws {
        try withTempQueue { _ in
            try ShareInboxQueue.enqueue(title: " Shared note ")
            try ShareInboxQueue.enqueue(title: "https://dayrule.app")

            let model = AppModel()
            model.testingSetPhase(.unlocked)
            model.ingestShareInboxIfNeeded()

            let titles = model.entities.todos.values.map(\.title).sorted()
            #expect(titles == ["Shared note", "https://dayrule.app"].sorted())
            #expect(model.entities.todos.values.allSatisfy { $0.start == .inbox })
            #expect(try ShareInboxQueue.drainTitles().isEmpty)
        }
    }

    @MainActor
    @Test func ingestNoopsWhileLocked() throws {
        try withTempQueue { _ in
            try ShareInboxQueue.enqueue(title: "Hold for unlock")

            let model = AppModel()
            model.testingSetPhase(.locked)
            model.ingestShareInboxIfNeeded()

            #expect(model.entities.todos.isEmpty)
            #expect(try ShareInboxQueue.drainTitles() == ["Hold for unlock"])
        }
    }

    @MainActor
    @Test func ingestPostsErrorNoticeOnCorruptQueue() throws {
        try withTempQueue { queue in
            let junk = Data("""
            [{"v":1,"id":"bad","createdAt":"t","nonceB64":"!!!","ciphertextB64":"!!!"}]
            """.utf8)
            try junk.write(to: queue)

            let model = AppModel()
            model.testingSetPhase(.unlocked)
            model.ingestShareInboxIfNeeded()

            #expect(model.entities.todos.isEmpty)
            #expect(model.notices.current?.kind == .error)
            #expect(model.notices.current?.message == ShareInboxError.corruptQueue.errorDescription)
            #expect(FileManager.default.fileExists(atPath: queue.path))
        }
    }

    /// Real App Group + Keychain path (signed host). Skips when unsigned CI
    /// cannot open the access group (errSecMissingEntitlement / no container).
    @Test func appGroupRoundTripWhenEntitled() throws {
        ShareInboxSupport.queueURLOverride = nil
        ShareInboxSupport.keyOverride = nil
        defer {
            // Leave overrides clear for other suites.
            ShareInboxSupport.queueURLOverride = nil
            ShareInboxSupport.keyOverride = nil
        }
        guard ShareInboxSupport.containerURL != nil else {
            // No App Group container (macOS host / misconfigured sim).
            return
        }
        let marker = "share-smoke-\(UUID().uuidString)"
        do {
            try ShareInboxQueue.enqueue(title: marker)
            let titles = try ShareInboxQueue.drainTitles()
            #expect(titles.contains(marker))
        } catch let err as ShareInboxError {
            switch err {
            case .keychain, .containerMissing:
                // Unsigned CI (`CODE_SIGNING_ALLOWED=NO`) cannot use the access group.
                return
            default:
                throw err
            }
        }
    }
    #endif
}
