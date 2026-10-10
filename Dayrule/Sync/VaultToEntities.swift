import Foundation

/// Build Entities from decrypted sync payloads (full JSON + unknown fields).
enum VaultToEntities {
    static func build(from vault: VaultSnapshot) -> Entities {
        var e = Entities.empty()
        for payload in vault.payloads {
            guard let value = payload.valueAny else { continue }
            _ = EntityJSON.insert(key: payload.key, value: value, into: &e)
        }
        return e
    }
}
