# Native security checklist (M7)

Sign-off against web PLAN crypto (§10) and this repo’s native threat deltas
(PLAN §13 / `docs/threat-model-native.md`). Check an item only when verified
in code or by a named manual step — not by assumption.

## Crypto (web §10 / ALG = 1)

- [x] 256-bit symmetric keys only; suite ALG = 1
- [x] Shared crypto vectors pass in CI (`DayruleTests` / `docs/shared/`)
- [x] Account key in `sodium_malloc`, zeroed on lock (`CryptoActor`); encrypt/decrypt/wrap borrow via `SecureBuffer.withUnsafeBytes` (decision 60)
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
- [x] `DAYRULE_API` and `DAYRULE_MEMORY_KEYCHAIN` are `#if DEBUG` (Release always production + SecItem; PLAN §9.6 / decision 16)
- [x] `NSAllowsLocalNetworking` is Debug-only (`DAYRULE_DEBUG_ATS` Info.plist preprocess; PLAN §9.6)
- [x] No APNs; reminders are local notifications only
- [x] `x-vercel-mitigated` → plain-English rate-limit copy
- [x] HTTP `426` / `upgrade_required` → stop sync, keep data, “Update Dayrule”
- [x] Certificate pinning deferred until Cloudflare (or equivalent) terminates TLS (PLAN decision 27 / §18.3); no pin code while Vercel alone issues the leaf

## System surfaces (must stay content-free)

- [x] Privacy cover on scene `.inactive` (iOS) / app resign-active (macOS); `PrivacyCoverPolicy` + idle auto-lock unit tests (`docs/security-audit-2026-11-10.md`)
- [x] iOS privacy cover shows only while the vault is unlocked (or recovery words are on screen), is inserted with **no animation** so the app-switcher snapshot never catches a half-faded frame, and fades only on reveal (`DayruleApp.privacyCoverNeeded` / `setPrivacyCover`)
- [x] Auto-lock after 15 min idle (unless stay-unlocked): the idle timer resets on unlock, on return to the foreground and on real user activity only (edits; on macOS key, click and scroll), throttled to once every 10s; sync, polls and merges never reset it (`AppModel.noteUserActivity` / `bumpIdle`)
- [x] No Spotlight / Siri / Handoff / content widgets donations in code
- [x] Count-only Home Screen widget (decision 76): App Group publishes Inbox/Today open counts only; cleared on lock, sign-out, and account deletion (`WidgetCountsStore`; never titles)
- [x] Notification titles opt-in; default body is time-only
- [x] No third-party analytics / crash / ad SDKs
- [x] iOS refuses third-party keyboard extensions (`DayruleAppDelegate` / PLAN §8.7) so recovery words are not delivered to a Full Access keyboard

## Manual / release gates

- [x] Internal TestFlight / ASC upload history: **0.1.2 (30)** iOS+Mac (2026-11-16); prior **(29)** / **(28)** / **0.1.1 (27)** / **(26)**. **0.1.2** train closed / approved. **0.1.3 (32)** archived + uploaded 2026-11-21 (Mac wake remount + Gate Passwords AutoFill).
- [x] App Store **0.1.1** / **0.1.2** approved (trains closed). **0.1.3** build **32** submitted for review 2026-11-21 — iOS + Mac.
- [x] AASA served for `webcredentials:dayrule.app` (passkey QA; live `application/json` on dayrule.app)
- [x] Native passkey second-step sign-in (platform assertion after password; recovery still both factors)
- [x] In-app account deletion (`DELETE /api/v1/account` + wipe local DB / Keychain wraps)
- [x] App Review demo account — runbook `docs/app-review-demo.md` (no second step; credentials only in App Store Connect; maintained for resubmits)
- [x] Privacy nutrition label (App Store Connect) — filled for the shipped iOS + Mac store apps
- [x] French encryption declaration / export-compliance — answered for the shipped store submissions
- [x] Mac App Store packaging — `docs/mac-app-store.md` (**0.1.3 (32)** submitted with iOS)
- [x] Server `MIN_IOS_BUILD` / `MIN_MACOS_BUILD` → `426` / `upgrade_required` middleware (web decision 37; client maps to needsUpdate in `AppModel`). **Ops:** production floors remain **26** while **0.1.3** is in review. **Do not raise** until **0.1.3** is live on the store and you intend to retire older clients; pick the new floor then (not before approval).

**Signed off:** M7 code items and the 0.1.x App Store / Mac App Store release gates above. Revisit nutrition / encryption / demo-account ASC fields only when submitting a new store version.
