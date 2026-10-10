import Foundation
import Testing
@testable import Dayrule

struct CryptoVectorsFile: Decodable {
    struct Input: Decodable {
        var password: String
        var salt: String
        var kdf: KdfParams
        var userId: String
        var accountKey: String
        var wrapNonce: String
        var recoveryEntropy: String
        var recordId: String
        var recordNonce: String
        var record: Record
    }

    struct Record: Decodable {
        var type: String
        var title: String
        var notes: String
        var tonight: Bool
    }

    struct Output: Decodable {
        var masterKey: String
        var authKey: String
        var kek: String
        var wrappedAccountKeyPassword: String
        var recoveryPhrase: String
        var recoveryKey: String
        var wrappedAccountKeyRecovery: String
        var recordAad: String
        var recordPlaintextJson: String
        var recordCiphertext: String
        var recoveryProof: String?
        var syncIdKey: String?
        var syncEntityKey: String?
        var syncWireId: String?
        var syncRecordAad: String?
        var syncPlaintextJson: String?
        var syncCiphertext: String?
        var syncTombstonePlaintextJson: String?
        var syncTombstoneCiphertext: String?
        var uppercaseUserIdDecryptFails: Bool?
        var padBuckets: [Int]?
    }

    var input: Input
    var output: Output
}

@Suite("Crypto vectors")
struct CryptoVectorsTests {
    private func loadVectors() throws -> CryptoVectorsFile {
        let here = URL(fileURLWithPath: #filePath)
        let root = here
            .deletingLastPathComponent() // DayruleTests
            .deletingLastPathComponent() // repo root
        let url = root.appendingPathComponent("docs/shared/crypto-vectors.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(CryptoVectorsFile.self, from: data)
    }

    @Test("match docs/shared/crypto-vectors.json")
    func matchSharedVectors() async throws {
        Primitives.ready()
        let vectors = try loadVectors()
        let input = vectors.input
        let expected = vectors.output

        let mk = try Primitives.deriveMasterKey(
            password: input.password,
            salt: try Hex.decode(input.salt),
            kdf: input.kdf
        )
        #expect(Hex.encode(mk) == expected.masterKey)

        let authKey = Primitives.hkdf(ikm: mk, label: Labels.auth)
        #expect(Hex.encode(authKey) == expected.authKey)

        let kek = Primitives.hkdf(ikm: mk, label: Labels.kek)
        #expect(Hex.encode(kek) == expected.kek)

        let ak = try Hex.decode(input.accountKey)
        let wrapNonce = try Hex.decode(input.wrapNonce)
        let wrappedPw = try Primitives.wrapKey(
            kek: kek,
            key: ak,
            label: Labels.wrapUnderKek,
            userId: input.userId,
            nonce: wrapNonce
        )
        #expect(Hex.encode(wrappedPw.ciphertext) == expected.wrappedAccountKeyPassword)

        let entropy = try Hex.decode(input.recoveryEntropy)
        let phrase = try Recovery.toPhrase(entropy)
        #expect(phrase.joined(separator: " ") == expected.recoveryPhrase)

        let rk = Recovery.recoveryKey(entropy: entropy)
        #expect(Hex.encode(rk) == expected.recoveryKey)

        let wrappedRecovery = try Primitives.wrapKey(
            kek: rk,
            key: ak,
            label: Labels.wrapRecovery,
            userId: input.userId,
            nonce: wrapNonce
        )
        #expect(Hex.encode(wrappedRecovery.ciphertext) == expected.wrappedAccountKeyRecovery)

        let meta = Primitives.RecordMeta(
            userId: input.userId,
            recordId: input.recordId,
            schemaVersion: 1,
            keyId: 1
        )
        let aad = String(bytes: Primitives.recordAad(meta), encoding: .utf8)
        #expect(aad == expected.recordAad)
        #expect(expected.recordPlaintextJson == #"{"type":"todo","title":"Buy milk","notes":"semi-skimmed","tonight":false}"#)

        let env = try Primitives.encryptRecordJSON(
            ak: ak,
            meta: meta,
            jsonUTF8: Array(expected.recordPlaintextJson.utf8),
            nonce: try Hex.decode(input.recordNonce)
        )
        #expect(Hex.encode(env.ciphertext) == expected.recordCiphertext)

        let opened = try Primitives.decryptRecordJSON(ak: ak, meta: meta, env: env)
        #expect(String(bytes: opened, encoding: .utf8) == expected.recordPlaintextJson)

        if let proofHex = expected.recoveryProof {
            let proof = Primitives.hkdf(ikm: try Hex.decode(input.recoveryEntropy), label: Labels.recoveryProof)
            #expect(Hex.encode(proof) == proofHex)
        }
        if let syncIdKeyHex = expected.syncIdKey,
           let entityKey = expected.syncEntityKey,
           let wireId = expected.syncWireId,
           let syncAad = expected.syncRecordAad,
           let syncPlain = expected.syncPlaintextJson,
           let syncCt = expected.syncCiphertext
        {
            let syncIdKey = Primitives.hkdf(ikm: ak, label: Labels.syncId)
            #expect(Hex.encode(syncIdKey) == syncIdKeyHex)
            let crypto = CryptoActor()
            // Unlock via known AK through password wrap from vectors.
            let (_, kek2) = try await crypto.beginLogin(
                password: input.password,
                salt: try Hex.decode(input.salt),
                kdf: input.kdf
            )
            _ = try await crypto.unlockWithPasswordWrap(
                kek: kek2,
                userId: input.userId,
                wrapped: Primitives.Sealed(
                    nonce: wrapNonce,
                    ciphertext: try Hex.decode(expected.wrappedAccountKeyPassword)
                ),
                stayUnlocked: false
            )
            #expect(try await crypto.syncId(for: entityKey) == wireId)
            let syncMeta = Primitives.RecordMeta(
                userId: input.userId,
                recordId: "sync/\(wireId)",
                schemaVersion: 1,
                keyId: 1
            )
            #expect(String(bytes: Primitives.recordAad(syncMeta), encoding: .utf8) == syncAad)
            let syncEnv = try Primitives.encryptRecordJSON(
                ak: ak,
                meta: syncMeta,
                jsonUTF8: Array(syncPlain.utf8),
                nonce: try Hex.decode(input.recordNonce)
            )
            #expect(Hex.encode(syncEnv.ciphertext) == syncCt)
            #expect(expected.uppercaseUserIdDecryptFails == true)
            let badMeta = Primitives.RecordMeta(
                userId: input.userId.uppercased(),
                recordId: "sync/\(wireId)",
                schemaVersion: 1,
                keyId: 1
            )
            #expect(throws: CryptoError.openFailed) {
                try Primitives.decryptRecordJSON(ak: ak, meta: badMeta, env: syncEnv)
            }
            if let buckets = expected.padBuckets {
                #expect(buckets == [256, 256, 512, 512, 2048, 4096, 8192])
            }
        }
    }

    @Test("pads into fixed buckets")
    func paddingBuckets() throws {
        let sizes = [1, 255, 256, 511, 2047, 2048, 5000].map { Primitives.bucketSize($0 + 1) }
        #expect(sizes == [256, 256, 512, 512, 2048, 4096, 8192])
        for n in [0, 1, 255, 300, 4095] {
            let data = [UInt8](repeating: 7, count: n)
            #expect(try Primitives.unpad(Primitives.pad(data)) == data)
        }
    }

    @Test("wrap binds purpose and user")
    func wrapBinding() throws {
        let ak = try Hex.decode(String(repeating: "2a", count: 32))
        let kek = try Hex.decode(String(repeating: "33", count: 32))
        let w = try Primitives.wrapKey(kek: kek, key: ak, label: Labels.wrapUnderKek, userId: "u")
        #expect(try Primitives.unwrapKey(kek: kek, wrapped: w, label: Labels.wrapUnderKek, userId: "u") == ak)
        #expect(throws: CryptoError.openFailed) {
            try Primitives.unwrapKey(kek: kek, wrapped: w, label: Labels.wrapRecovery, userId: "u")
        }
        #expect(throws: CryptoError.openFailed) {
            try Primitives.unwrapKey(kek: kek, wrapped: w, label: Labels.wrapUnderKek, userId: "v")
        }
    }

    @Test("recovery phrase round-trip and typo rejection")
    func recoveryRoundTrip() throws {
        let entropy = try Hex.decode(String(repeating: "7f", count: 32))
        let words = try Recovery.toPhrase(entropy)
        #expect(words.count == 24)
        let back = try Recovery.fromPhrase("  \(words.joined(separator: "   ").uppercased()) ")
        #expect(back == entropy)
        var typo = words
        typo[3] = typo[3] == "abandon" ? "ability" : "abandon"
        #expect(throws: CryptoError.recoveryPhraseInvalid) {
            try Recovery.fromPhrase(typo.joined(separator: " "))
        }
    }

    @Test("KDF floor rejects weak params")
    func kdfFloor() {
        #expect(throws: CryptoError.kdfRejected("ops out of range")) {
            try KdfParams(v: 1, ops: 2, mem: 64 * 1024 * 1024).meetFloor()
        }
        #expect(throws: CryptoError.kdfRejected("mem out of range")) {
            try KdfParams(v: 1, ops: 3, mem: 1024).meetFloor()
        }
    }
}
