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

struct SyncHead: Codable, Sendable {
    var seq: Int64
    var floor: Int64
}

/// JSON client for the Dayrule API (Bearer + `X-Dayrule-Client: ios/<build>`).
actor APIClient {
    var baseURL: URL
    private(set) var token: String?
    private let session: URLSession
    private let build: String

    init(baseURL: URL, build: String = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1") {
        self.baseURL = baseURL
        self.build = build
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: config)
    }

    private var clientHeader: String { "ios/\(build)" }

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

    func login(email: String, authKeyB64: String, deviceLabel: String) async throws -> LoginResponse {
        try await decode(
            "POST",
            path: "api/v1/auth/login",
            jsonBody: ["email": email, "authKey": authKeyB64, "deviceLabel": deviceLabel]
        )
    }

    func logout() async throws {
        _ = try await raw("POST", path: "api/v1/auth/logout")
    }

    func account() async throws -> AccountResponse {
        try await decode("GET", path: "api/v1/account")
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
}
