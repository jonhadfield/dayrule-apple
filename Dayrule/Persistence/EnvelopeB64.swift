import Foundation

/// Wire/local envelope as standard base64 (web `EnvelopeB64`).
struct EnvelopeB64: Codable, Equatable, Sendable {
    var alg: Int
    var keyId: Int
    var nonce: String
    var ciphertext: String

    init(alg: Int, keyId: Int, nonce: String, ciphertext: String) {
        self.alg = alg
        self.keyId = keyId
        self.nonce = nonce
        self.ciphertext = ciphertext
    }

    init(_ env: Primitives.Envelope) {
        self.alg = env.alg
        self.keyId = env.keyId
        self.nonce = Base64Std.encode(env.nonce)
        self.ciphertext = Base64Std.encode(env.ciphertext)
    }

    func envelope() throws -> Primitives.Envelope {
        Primitives.Envelope(
            alg: alg,
            keyId: keyId,
            nonce: try Base64Std.decode(nonce),
            ciphertext: try Base64Std.decode(ciphertext)
        )
    }
}
