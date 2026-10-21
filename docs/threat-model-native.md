# Dayrule native (iOS + macOS) — threat model deltas

Reviewed with M0; broadened for macOS with the multiplatform target. The
web threat model at `/Users/hadfielj/Repositories/dayrule/docs/threat-model.md`
still applies. This file only records **device-specific** differences.

## Trust boundary

The unlocked app process is trusted for content (same role as the unlocked
browser). The Go API and Neon remain untrusted for plaintext. App Store /
Mac App Store binaries are signed by Apple under our team certificate;
unlike the web app there is no per-build hash verification published for
users to check.

## At rest on device

| Asset | Where |
|---|---|
| Record ciphertext | Application Support SQLite (GRDB) — ciphertext only (from M4); iOS file protection `completeUntilFirstUserAuthentication` |
| Account key | `sodium_malloc` inside `CryptoActor` while unlocked; wiped on lock |
| Device wrap key | Keychain, `WhenUnlockedThisDeviceOnly`, random 256-bit — **never** iCloud Keychain |
| Biometric wrap key | Keychain, `WhenPasscodeSetThisDeviceOnly` + `.biometryCurrentSet` |
| Session token | Keychain (from M2), `WhenUnlockedThisDeviceOnly` — never logged |
| Recovery phrase / password | Never persisted; SecureField copies are best-effort only |

## Backups (iCloud / Finder / iTunes)

Device backups may include the SQLite file (ciphertext only). They do **not**
include the device or biometric wrap keys (`ThisDeviceOnly` Keychain). Restoring
a backup onto another device therefore yields ciphertext the new device cannot
unwrap until the user signs in with password (or recovery) and re-derives keys.
Explicit Export (Settings → Your data) is plaintext by design — warn in UI.
Stay-unlocked / biometric / passkey wraps are per-device and not part of the
synced vault.

## Shared residual risks (iOS + macOS)

- **Unlocked device / malware** with the OS account — out of scope (same as
  an unlocked browser profile).
- **Scene snapshots** — privacy cover on `.inactive` so app-switcher /
  Mission Control snapshots never show content (PLAN §8.7).
- **Local notification titles** — when the user opts in, the OS stores the
  title in its notification store; default is content-free (PLAN §11).
- **No Secure Enclave wrap** — SE is P-256 only; wrapping the AK under it
  would be classical public-key crypto (decision 10). Device wrap stays
  symmetric in the Keychain.
- **Swift `String` / `Data`** cannot be reliably zeroed after use; only
  `sodium_malloc` key buffers are wiped.

## iOS-specific

- Third-party keyboards are refused app-wide
  (`shouldAllowExtensionPointIdentifier` → `.keyboard`; UIKit has no
  per-field hook). Password fields also use `SecureField`.
- Recovery-phrase copy uses a local-only, expiring `UIPasteboard` item.

## macOS-specific

- Sandboxed Mac builds use network-client entitlement only; Keychain items
  stay in the app's sandbox.
- Recovery-phrase copy writes to `NSPasteboard` and clears after 60s when
  the content is unchanged (no iOS-style local-only / expiration API).
- An unlocked Mac login session is a larger physical-access surface than a
  locked phone; stay-unlocked must explain that trade-off in Settings.

## Input hygiene

Password and recovery fields refuse autocorrect. iOS refuses third-party
keyboards app-wide. Recovery-phrase copy never stays on the pasteboard
indefinitely.
