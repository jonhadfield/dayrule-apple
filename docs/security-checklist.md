# Native security checklist (M7)

Sign-off against web PLAN crypto (§10) and this repo’s native threat deltas
(PLAN §13 / `docs/threat-model-native.md`). Check an item only when verified
in code or by a named manual step — not by assumption.

## Crypto (web §10 / ALG = 1)

- [x] 256-bit symmetric keys only; suite ALG = 1
- [x] Shared crypto vectors pass in CI (`DayruleTests` / `docs/shared/`)
- [x] Account key in `sodium_malloc`, zeroed on lock (`CryptoActor`)
- [x] Device wrap: random 256-bit Keychain key, `WhenUnlockedThisDeviceOnly` (no Secure Enclave)
- [x] Biometric wrap: `WhenPasscodeSetThisDeviceOnly` + `.biometryCurrentSet`; gate is Keychain read
- [x] Passkey PRF unlock is device-local wrap only (no server PRF material)
- [x] KDF floor refused for server-supplied params below the web floor
- [x] HIBP range API only (k-anonymity, fails open; never via Dayrule API)
- [x] Unknown `alg` records held opaque; UI shows “Update Dayrule”

## At rest / backups (PLAN §12–§13)

- [x] Local store is ciphertext only (GRDB)
- [x] iOS ciphertext file protection `completeUntilFirstUserAuthentication`
- [x] Session + wrap keys are `ThisDeviceOnly` (not iCloud Keychain)
- [x] Threat model documents backup posture (`docs/threat-model-native.md`)
- [x] Settings warns that exports are plaintext; backups can’t unlock elsewhere

## Network / sync

- [x] Bearer + `X-Dayrule-Client: ios|macos/<build>`
- [x] Production host is `dayrule.app` only (local server in Debug)
- [x] No APNs; reminders are local notifications only
- [x] `x-vercel-mitigated` → plain-English rate-limit copy
- [x] HTTP `426` / `upgrade_required` → stop sync, keep data, “Update Dayrule”
- [ ] Certificate pinning (open PLAN §18 point 3 — not yet)

## System surfaces (must stay content-free)

- [x] Privacy cover on scene `.inactive`
- [x] No Spotlight / Siri / Handoff / content widgets donations in code
- [x] Notification titles opt-in; default body is time-only
- [x] No third-party analytics / crash / ad SDKs

## Manual / release gates

- [x] Internal TestFlight build uploaded (signing + entitlements; build 4 with Browse/When + sodium_init + phone nav fixes)
- [x] AASA served for `webcredentials:dayrule.app` (passkey QA; live `application/json` on dayrule.app)
- [ ] App Review demo account + nutrition label (before external testers)
- [ ] Confirm French encryption declaration rules before public store

**Signed off (code items above):** M7 branch review — remaining unchecked items are release ops, not app code.
