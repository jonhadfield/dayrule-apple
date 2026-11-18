import Foundation

enum APIError: Error, LocalizedError, Equatable {
    case offline
    case http(status: Int, code: String, message: String)
    case decoding

    var errorDescription: String? {
        switch self {
        case .offline: "Can’t reach Dayrule. Check your connection."
        case .http(_, _, let message): message
        case .decoding: "Unexpected response from Dayrule."
        }
    }
}

struct WrappedB64: Codable, Equatable, Sendable {
    var nonce: String
    var ciphertext: String

    func sealed() throws -> Primitives.Sealed {
        Primitives.Sealed(nonce: try Base64Std.decode(nonce), ciphertext: try Base64Std.decode(ciphertext))
    }

    init(nonce: String, ciphertext: String) {
        self.nonce = nonce
        self.ciphertext = ciphertext
    }

    init(_ sealed: Primitives.Sealed) {
        nonce = Base64Std.encode(sealed.nonce)
        ciphertext = Base64Std.encode(sealed.ciphertext)
    }
}

struct KdfDTO: Codable, Equatable, Sendable {
    var v: Int
    var ops: UInt32
    var mem: UInt32

    var params: KdfParams { KdfParams(v: v, ops: ops, mem: mem) }
}

struct SecondStep: Codable, Equatable, Sendable {
    var token: String
    var methods: [String]
}

struct LoginResponse: Codable, Sendable {
    var userId: String?
    var token: String?
    var wrappedPassword: WrappedB64?
    var salt: String?
    var kdf: KdfDTO?
    var secondStep: SecondStep?
}

struct PreloginResponse: Codable, Sendable {
    var salt: String
    var kdf: KdfDTO
}

struct WireRecord: Codable, Sendable {
    var id: String
    var seq: Int64?
    var alg: Int
    var keyId: Int
    var nonce: String
    var ciphertext: String
    var tombstone: Bool?
}

struct PullResponse: Codable, Sendable {
    var records: [WireRecord]
    var cursor: Int64
    var hasMore: Bool
}

struct AccountResponse: Codable, Sendable {
    var userId: String
    var email: String
}

struct RecoverStartResponse: Codable, Sendable {
    var userId: String
    var wrappedRecovery: WrappedB64
}

struct SignupVerifyResponse: Codable, Sendable {
    var signupToken: String
}

struct RegisterResponse: Codable, Sendable {
    var userId: String
    var token: String?
}

struct SyncHead: Codable, Sendable {
    var seq: Int64
    var floor: Int64
}

struct PushWireRecord: Encodable, Sendable {
    var id: String
    var baseSeq: Int64
    var alg: Int
    var keyId: Int
    var nonce: String
    var ciphertext: String
    var tombstone: Bool?
}

struct PushResultRow: Codable, Sendable {
    var id: String
    var seq: Int64
    var conflict: Bool?
    var error: String?
}

struct PushResponse: Codable, Sendable {
    var results: [PushResultRow]
    var head: Int64
}

/// JSON client for the Dayrule API (Bearer + `X-Dayrule-Client: ios|macos/<build>`).
actor APIClient {
    var baseURL: URL
    private(set) var token: String?
    private let session: URLSession
    private let build: String

    init(
        baseURL: URL,
        build: String = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1",
        session: URLSession? = nil
    ) {
        self.baseURL = baseURL
        self.build = build
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.urlCache = nil
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: config)
        }
    }

    private var clientHeader: String { ClientPlatform.clientHeader(build: build) }

    func setToken(_ token: String?) {
        self.token = token
    }

    func setBaseURL(_ url: URL) {
        baseURL = url
    }

    func decode<T: Decodable>(_ method: String, path: String, jsonBody: [String: Any]? = nil) async throws -> T {
        let data = try await raw(method, path: path, jsonBody: jsonBody)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decoding
        }
    }

    func raw(_ method: String, path: String, jsonBody: [String: Any]? = nil) async throws -> Data {
        let base = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + "/" + trimmed) else { throw APIError.offline }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue(clientHeader, forHTTPHeaderField: "X-Dayrule-Client")
        if let token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let jsonBody {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: jsonBody)
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw APIError.offline
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.offline }
        if http.statusCode == 204 { return Data() }
        if !(200..<300).contains(http.statusCode) {
            // Vercel Firewall answers before our API; prefer a clear message (web api.ts).
            if http.value(forHTTPHeaderField: "x-vercel-mitigated") != nil {
                throw APIError.http(
                    status: http.statusCode,
                    code: "rate_limited",
                    message: "Too many attempts from this network. Please wait a while and try again."
                )
            }
            let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let message = obj?["error"] as? String ?? "Something went wrong."
            let code = obj?["code"] as? String ?? "error"
            throw APIError.http(status: http.statusCode, code: code, message: message)
        }
        return data
    }

    func prelogin(email: String) async throws -> PreloginResponse {
        try await decode("POST", path: "api/v1/auth/prelogin", jsonBody: ["email": email])
    }

    func signupStart(email: String) async throws {
        _ = try await raw(
            "POST",
            path: "api/v1/auth/signup/start",
            jsonBody: ["email": email]
        )
    }

    func signupVerify(email: String, code: String) async throws -> SignupVerifyResponse {
        try await decode(
            "POST",
            path: "api/v1/auth/signup/verify",
            jsonBody: ["email": email, "code": code]
        )
    }

    func register(
        email: String,
        signupToken: String,
        userId: String,
        saltB64: String,
        kdf: KdfParams,
        authKeyB64: String,
        wrappedPassword: WrappedB64,
        wrappedRecovery: WrappedB64,
        recoveryProofB64: String,
        deviceLabel: String
    ) async throws -> RegisterResponse {
        try await decode(
            "POST",
            path: "api/v1/auth/register",
            jsonBody: [
                "email": email,
                "signupToken": signupToken,
                "userId": userId,
                "salt": saltB64,
                "kdf": ["v": kdf.v, "ops": Int(kdf.ops), "mem": Int(kdf.mem)],
                "authKey": authKeyB64,
                "wrappedPassword": [
                    "nonce": wrappedPassword.nonce,
                    "ciphertext": wrappedPassword.ciphertext,
                ],
                "wrappedRecovery": [
                    "nonce": wrappedRecovery.nonce,
                    "ciphertext": wrappedRecovery.ciphertext,
                ],
                "recoveryProof": recoveryProofB64,
                "deviceLabel": deviceLabel,
            ]
        )
    }

    func login(email: String, authKeyB64: String, deviceLabel: String) async throws -> LoginResponse {
        try await decode(
            "POST",
            path: "api/v1/auth/login",
            jsonBody: ["email": email, "authKey": authKeyB64, "deviceLabel": deviceLabel]
        )
    }

    /// Raw JSON for `POST /api/v1/auth/login/passkey/options` (parse off-actor).
    func loginPasskeyOptionsData(token: String) async throws -> Data {
        try await raw(
            "POST",
            path: "api/v1/auth/login/passkey/options",
            jsonBody: ["token": token]
        )
    }

    /// Finish sign-in with a server-verified passkey assertion (`credential` as JSON object Data).
    func loginPasskey(token: String, credentialJSON: Data) async throws -> LoginResponse {
        guard let credential = try JSONSerialization.jsonObject(with: credentialJSON) as? [String: Any]
        else { throw APIError.decoding }
        return try await decode(
            "POST",
            path: "api/v1/auth/login/passkey",
            jsonBody: ["token": token, "credential": credential]
        )
    }

    func logout() async throws {
        _ = try await raw("POST", path: "api/v1/auth/logout")
    }

    func account() async throws -> AccountResponse {
        try await decode("GET", path: "api/v1/account")
    }

    /// `DELETE /api/v1/account` — server wipes the account after password check.
    func deleteAccount(authKeyB64: String) async throws {
        _ = try await raw(
            "DELETE",
            path: "api/v1/account",
            jsonBody: ["authKey": authKeyB64]
        )
    }

    func recoverStart(email: String, recoveryProofB64: String) async throws -> RecoverStartResponse {
        try await decode(
            "POST",
            path: "api/v1/auth/recover/start",
            jsonBody: ["email": email, "recoveryProof": recoveryProofB64]
        )
    }

    func pull(since: Int64, full: Bool) async throws -> PullResponse {
        var path = "api/v1/sync/pull?since=\(since)"
        if full { path += "&full=1" }
        return try await decode("GET", path: path)
    }

    func head() async throws -> SyncHead {
        try await decode("GET", path: "api/v1/sync/head")
    }

    func push(_ records: [PushWireRecord]) async throws -> PushResponse {
        let body: [String: Any] = [
            "records": records.map { r -> [String: Any] in
                var d: [String: Any] = [
                    "id": r.id,
                    "baseSeq": r.baseSeq,
                    "alg": r.alg,
                    "keyId": r.keyId,
                    "nonce": r.nonce,
                    "ciphertext": r.ciphertext,
                ]
                if let t = r.tombstone { d["tombstone"] = t }
                return d
            },
        ]
        return try await decode("POST", path: "api/v1/sync/push", jsonBody: body)
    }
}
