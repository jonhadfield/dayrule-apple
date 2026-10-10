import Foundation
import Testing
@testable import Dayrule

#if os(macOS)
/// Live sync against local Go (`scripts/local-sync-e2e.sh`). Skipped unless `DAYRULE_E2E=1`.
/// macOS-only: needs `Process` for `invite` / `plaintext-check`. Forces `ios/` client header
/// so register returns a bearer token (server `wantsBearerToken`).
@Suite("Sync e2e")
@MainActor
struct SyncE2ETests {
    @Test func pushThenServerHasNoPlaintext() async throws {
        // xcodebuild does not reliably forward env into the macOS test host; the
        // script writes this JSON sidecar instead (see scripts/local-sync-e2e.sh).
        let cfgURL = URL(fileURLWithPath: "/tmp/dayrule-e2e-config.json")
        guard FileManager.default.fileExists(atPath: cfgURL.path),
              let cfgData = try? Data(contentsOf: cfgURL),
              let cfg = try? JSONSerialization.jsonObject(with: cfgData) as? [String: String],
              cfg["enabled"] == "1"
        else { return }

        let apiBase = cfg["api"] ?? "http://127.0.0.1:8080"
        let webRoot = cfg["web"]
            ?? URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("dayrule")
            .path
        let outDir = cfg["out"] ?? (webRoot as NSString).appendingPathComponent("web/e2e/.out")
        let dbURL = cfg["database"]
            ?? "postgres://postgres:test@127.0.0.1:55432/dayrule_test?sslmode=disable"

        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        let email = "ios-e2e-\(stamp)@example.com"
        let title = "Marigold title \(stamp)"
        let notes = "Quince notes \(stamp)"
        let password = "orange kettle drift"

        let invite = try runTool(
            (outDir as NSString).appendingPathComponent("invite"),
            args: ["1"],
            env: ["DATABASE_URL_UNPOOLED": dbURL]
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(!invite.isEmpty)

        let api = APIClient(baseURL: URL(string: apiBase)!, build: "e2e")
        await api.setClientKind("ios")
        try await api.signupStart(email: email, inviteCode: invite)
        let code = try await waitForEmailCode(email: email, logPath: (outDir as NSString).appendingPathComponent("api.log"))
        let verified = try await api.signupVerify(email: email, code: code)

        Primitives.ready()
        let userId = UUID().uuidString.lowercased()
        let salt = Primitives.randomBytes(16)
        let crypto = CryptoActor()
        let created = try await crypto.createLocalDemo(password: password, userId: userId, salt: salt)
        let registered = try await api.register(
            email: email,
            signupToken: verified.signupToken,
            inviteCode: invite,
            userId: userId,
            saltB64: Base64Std.encode(salt),
            kdf: created.kdf,
            authKeyB64: Base64Std.encode(created.authKey),
            wrappedPassword: WrappedB64(created.wrappedPassword),
            wrappedRecovery: WrappedB64(created.wrappedRecovery),
            recoveryProofB64: Base64Std.encode(created.recoveryProof),
            deviceLabel: "iOS"
        )
        guard let token = registered.token else {
            throw APIError.http(
                status: 500,
                code: "no_token",
                message: "register returned no bearer token (need X-Dayrule-Client: ios/…)"
            )
        }
        await api.setToken(token)

        let db = try AppDatabase.openInMemory()
        let cipher = CipherStore(dbQueue: db, cipher: ActorRecordCipher(crypto: crypto))
        let store = EntityStore()
        store.onChanges = { changes, source in
            switch source {
            case .local: try? await cipher.applyLocal(changes)
            case .sync: try? await cipher.applyRemote(changes)
            }
        }
        _ = try store.run("Add") { d, env in
            try Commands.createTodo(d, env, .init(title: title, notes: notes, placement: .inbox))
        }
        await store.awaitPendingPersist()

        let engine = SyncEngine(store: store, db: cipher, crypto: crypto, api: api)
        try await engine.sync()

        let checkOut = try runTool(
            (outDir as NSString).appendingPathComponent("plaintext-check"),
            args: [email, title, notes],
            env: ["DATABASE_URL_UNPOOLED": dbURL]
        )
        var found: [String: [String]] = [:]
        for line in checkOut.split(separator: "\n") where !line.isEmpty {
            let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            found[parts[1], default: []].append(parts[0])
        }
        #expect(found[email]?.contains("users.email") == true)
        #expect(found[title] == nil)
        #expect(found[notes] == nil)
    }

    private func waitForEmailCode(email: String, logPath: String) async throws -> String {
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: logPath)),
               let text = String(data: data, encoding: .utf8)
            {
                for line in text.split(separator: "\n").reversed() {
                    guard line.contains("\"to\":\"\(email)\"") else { continue }
                    if let match = line.firstMatch(of: /Your Dayrule code: (\d{6})/) {
                        return String(match.1)
                    }
                }
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        throw APIError.http(status: 408, code: "timeout", message: "email code not logged")
    }

    private func runTool(_ path: String, args: [String], env: [String: String]) throws -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        var full = ProcessInfo.processInfo.environment
        for (k, v) in env { full[k] = v }
        proc.environment = full
        let out = Pipe()
        let err = Pipe()
        proc.standardOutput = out
        proc.standardError = err
        try proc.run()
        proc.waitUntilExit()
        let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard proc.terminationStatus == 0 else {
            throw APIError.http(
                status: 500,
                code: "tool",
                message: "\(path) failed: \(stderr.isEmpty ? stdout : stderr)"
            )
        }
        return stdout
    }
}
#endif
