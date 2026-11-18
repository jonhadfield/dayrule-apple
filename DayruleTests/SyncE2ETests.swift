import Foundation
import Testing
@testable import Dayrule

#if os(macOS)
/// Live sync against local Go (`scripts/local-sync-e2e.sh`). Skipped unless config sidecar is present.
/// macOS-only: needs `Process` for `invite` / `plaintext-check`. Uses real `macos/<build>`
/// client header (dayrule #33 accepts it for Bearer body tokens).
@Suite("Sync e2e")
@MainActor
struct SyncE2ETests {
    private struct E2EConfig {
        var api: String
        var outDir: String
        var dbURL: String
    }

    private struct Session {
        var api: APIClient
        var crypto: CryptoActor
        var email: String
        var password: String
        var userId: String
        var salt: [UInt8]
        var created: UnlockResult
    }

    @Test func pushThenServerHasNoPlaintext() async throws {
        guard let cfg = loadConfig() else { return }
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        let email = "ios-e2e-\(stamp)@example.com"
        let title = "Marigold title \(stamp)"
        let notes = "Quince notes \(stamp)"
        let password = "orange kettle drift"

        let session = try await registerSession(cfg: cfg, email: email, password: password)
        let (engine, store, _) = try await makeLocalEngine(crypto: session.crypto, api: session.api)
        _ = try store.run("Add") { d, env in
            try Commands.createTodo(d, env, .init(title: title, notes: notes, placement: .inbox))
        }
        await store.awaitPendingPersist()
        try await engine.sync()

        let checkOut = try runTool(
            (cfg.outDir as NSString).appendingPathComponent("plaintext-check"),
            args: [email, title, notes],
            env: ["DATABASE_URL_UNPOOLED": cfg.dbURL]
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

    @Test func secondDevicePullsPushedTodo() async throws {
        guard let cfg = loadConfig() else { return }
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        let email = "ios-e2e-b-\(stamp)@example.com"
        let title = "Second device \(stamp)"
        let password = "orange kettle drift"

        let a = try await registerSession(cfg: cfg, email: email, password: password)
        let (engineA, storeA, _) = try await makeLocalEngine(crypto: a.crypto, api: a.api)
        _ = try storeA.run("Add") { d, env in
            try Commands.createTodo(d, env, .init(title: title, placement: .inbox))
        }
        await storeA.awaitPendingPersist()
        try await engineA.sync()

        // Device B: fresh crypto + login with same password material.
        let apiB = APIClient(baseURL: URL(string: cfg.api)!, build: "e2e-b")
        let pre = try await apiB.prelogin(email: email)
        let kdf = pre.kdf.params
        try kdf.meetFloor()
        let salt = try Base64Std.decode(pre.salt)
        let cryptoB = CryptoActor()
        let (authKey, kek) = try await cryptoB.beginLogin(password: password, salt: salt, kdf: kdf)
        let login = try await apiB.login(
            email: email,
            authKeyB64: Base64Std.encode(authKey),
            deviceLabel: "macOS-B"
        )
        guard let token = login.token, let wrapped = login.wrappedPassword, let userId = login.userId else {
            throw APIError.decoding
        }
        await apiB.setToken(token)
        _ = try await cryptoB.unlockWithPasswordWrap(
            kek: kek,
            userId: userId.lowercased(),
            wrapped: try wrapped.sealed(),
            stayUnlocked: false
        )

        let (engineB, storeB, _) = try await makeLocalEngine(crypto: cryptoB, api: apiB)
        try await engineB.sync()
        let titles = storeB.entities.todos.values.map(\.title)
        #expect(titles.contains(title))
    }

    private func loadConfig() -> E2EConfig? {
        let cfgURL = URL(fileURLWithPath: "/tmp/dayrule-e2e-config.json")
        guard FileManager.default.fileExists(atPath: cfgURL.path),
              let cfgData = try? Data(contentsOf: cfgURL),
              let cfg = try? JSONSerialization.jsonObject(with: cfgData) as? [String: String],
              cfg["enabled"] == "1"
        else { return nil }
        let webRoot = cfg["web"]
            ?? URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("dayrule")
            .path
        return E2EConfig(
            api: cfg["api"] ?? "http://127.0.0.1:8080",
            outDir: cfg["out"] ?? (webRoot as NSString).appendingPathComponent("web/e2e/.out"),
            dbURL: cfg["database"]
                ?? "postgres://postgres:test@127.0.0.1:55432/dayrule_test?sslmode=disable"
        )
    }

    private func registerSession(cfg: E2EConfig, email: String, password: String) async throws -> Session {
        let api = APIClient(baseURL: URL(string: cfg.api)!, build: "e2e")
        try await api.signupStart(email: email)
        let code = try await waitForEmailCode(
            email: email,
            logPath: (cfg.outDir as NSString).appendingPathComponent("api.log")
        )
        let verified = try await api.signupVerify(email: email, code: code)

        Primitives.ready()
        let userId = UUID().uuidString.lowercased()
        let salt = Primitives.randomBytes(16)
        let crypto = CryptoActor()
        let created = try await crypto.createLocalDemo(password: password, userId: userId, salt: salt)
        let registered = try await api.register(
            email: email,
            signupToken: verified.signupToken,
            userId: userId,
            saltB64: Base64Std.encode(salt),
            kdf: created.kdf,
            authKeyB64: Base64Std.encode(created.authKey),
            wrappedPassword: WrappedB64(created.wrappedPassword),
            wrappedRecovery: WrappedB64(created.wrappedRecovery),
            recoveryProofB64: Base64Std.encode(created.recoveryProof),
            deviceLabel: ClientPlatform.deviceLabel
        )
        guard let token = registered.token else {
            throw APIError.http(
                status: 500,
                code: "no_token",
                message: "register returned no bearer token (need X-Dayrule-Client: ios|macos/…)"
            )
        }
        await api.setToken(token)
        return Session(
            api: api, crypto: crypto, email: email, password: password,
            userId: userId, salt: salt, created: created
        )
    }

    private func makeLocalEngine(
        crypto: CryptoActor,
        api: APIClient
    ) async throws -> (SyncEngine, EntityStore, CipherStore) {
        let db = try AppDatabase.openInMemory()
        let cipher = CipherStore(dbQueue: db, cipher: ActorRecordCipher(crypto: crypto))
        let store = EntityStore()
        store.onChanges = { changes, source in
            switch source {
            case .local: try? await cipher.applyLocal(changes)
            case .sync: try? await cipher.applyRemote(changes)
            }
        }
        let engine = SyncEngine(store: store, db: cipher, crypto: crypto, api: api)
        return (engine, store, cipher)
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
