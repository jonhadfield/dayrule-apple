# Dayrule iOS — threat model deltas

Reviewed with M0. The web threat model at
`/Users/hadfielj/Repositories/dayrule/docs/threat-model.md` still applies.
This file only records **device-specific** differences.

## Trust boundary

The unlocked app process is trusted for content (same role as the unlocked
browser). The Go API and Neon remain untrusted for plaintext. The App Store
binary is signed by Apple under our team certificate; unlike the web app
there is no per-build hash verification published for users to check.

## At rest on device

| Asset | Where |
|---|---|
| Record ciphertext | App-group SQLite (GRDB) — ciphertext only (from M4) |
| Account key | `sodium_malloc` inside `CryptoActor` while unlocked; wiped on lock |
| Device wrap key | Keychain, `WhenUnlockedThisDeviceOnly`, random 256-bit |
| Session token | Keychain (from M2) — never logged |
| Recovery phrase / password | Never persisted; SecureField copies are best-effort only |

## iOS-specific residual risks

- **Unlocked phone / malware** with the OS account — out of scope (same as
  an unlocked browser profile).
- **App switcher snapshots** — mitigated by a privacy cover on `.inactive`
  (PLAN §8.7).
- **Local notification titles** — when the user opts in, iOS stores the
  title in its notification store; default is content-free (PLAN §11).
- **No Secure Enclave wrap** — SE is P-256 only; wrapping the AK under it
  would be classical public-key crypto (decision 10). Device wrap stays
  symmetric in the Keychain.
- **Swift `String` / `Data`** cannot be reliably zeroed after use; only
  `sodium_malloc` key buffers are wiped.

## Input hygiene

Password and recovery fields refuse third-party keyboards and autocorrect.
Recovery-phrase copy uses a local, expiring pasteboard item.
