# Dayrule native (iOS + macOS)

Native SwiftUI companion to the Dayrule web app for **iPhone, iPad, and Mac**.
Same paper-and-ink identity, vocabulary, domain model, sync protocol and
end-to-end encryption. One multiplatform Xcode target and one source tree.

Native product decisions live in a local `PLAN.md` (gitignored, not published).
Shared product, crypto, sync and wire rules live in the companion web repo’s
plan and code. Read the relevant section before changing behaviour. When a
shared rule changes, land it in the web repo first (or the same release train),
then adopt it here. Do not invent a private wire format.

## Layout

- `Dayrule/` — shared app sources (SwiftUI views, domain, store, sync,
  crypto, persistence, design system, `Platform/` helpers).
- `DayruleTests/` — unit tests (domain, merge, crypto vectors).
- `DayruleUITests/` — UI tests.
- `project.yml` — XcodeGen source of truth (`supportedDestinations: iOS,
  macOS`); regenerate with `xcodegen generate`.
- `docs/` — native threat-model deltas; `docs/shared/` is a mirror of the
  web repo’s `docs/shared/` (crypto vectors, wire fixtures, domain vectors),
  updated only with `scripts/sync-shared.sh <sha>` and pinned by
  `docs/shared/SHARED.lock`. Never hand-edit the mirror.

## Commands

From the repo root (requires a Mac and the Xcode version pinned in CI;
pick a simulator that exists with `xcrun simctl list devices available`):

- `xcodegen generate` — regenerate `Dayrule.xcodeproj` from `project.yml`.
- `xcodebuild -scheme Dayrule -destination 'platform=iOS Simulator,name=<simulator>' test` — unit + UI tests.
- `xcodebuild -scheme Dayrule -destination 'generic/platform=iOS' build` — release-shaped iOS build.
- `xcodebuild -scheme Dayrule -destination 'platform=macOS' build` — macOS build.
- `swift test` — only if a SwiftPM package target exists for shared pure-Swift modules.

Development and UI tests run against a **local Go server** started with the
web repo’s `web/e2e/serve-api.sh`; set the base URL in the scheme’s
environment (never commit secrets). Don’t target `preview.dayrule.app` from
the app: it is behind Deployment Protection and a bypass token must never
ship in a binary. TestFlight builds use the production host
`https://dayrule.app`.

## Workflow rules

- Never commit to `main` directly while it is protected. Feature branch →
  PR → review.
- Coordinated API or crypto changes land in the **web repo first** (or the
  same release train), then this app adopts them.
- Where the web plan and web code disagree, port the code and raise a web
  plan fix.
- Never test Firewall limits or hammer production auth from CI, review
  accounts or your own connection; automated tests use the local server.

## Identity rules

- Use Dayrule’s own vocabulary in UI and code: Inbox, Today, Scheduled,
  Backlog, Not now, Done, Trash, Add.
- Use the design tokens in `Dayrule/Design/Tokens.swift` (mirrors the web
  app’s `web/src/styles/tokens.css`); don’t hard-code colours.
- Headings use **Fraunces**; body uses the system sans. Ship Fraunces as
  an app-bundled font (OFL), not a network download.

## Companion rules

- Shared domain types, list selectors, HLC merge, repeat rules, date
  parsing and sync record shapes must stay behaviour-compatible with the
  web repo’s `web/src/domain/` and `web/src/sync/`. Prefer porting tests
  and known answers over re-deriving rules from memory.
- Wire constants (labels, AAD formats, envelopes, lowercase userId), entity
  unknown-field preservation, and `toISOString()` timestamps with
  milliseconds follow the shared web plan and vectors.
- Crypto suite **ALG = 1** only until a new suite is defined in the web
  plan and vectors. Pass the shared vectors in `docs/shared/` in CI.
- The server must never see plaintext user content. Encryption happens on
  device before any network write.

## Security rules (non-negotiable)

- 256-bit symmetric keys only; no classical-only public-key crypto
  protecting user data.
- Account key lives only in the crypto boundary (actor / isolated
  module); UI receives plaintext entities in memory while unlocked, never
  keys.
- At rest on device: **ciphertext only** in the local store. Device wrap
  keys are random 256-bit **Keychain** items
  (`WhenUnlockedThisDeviceOnly`) with a symmetric wrap. **No Secure
  Enclave wrap** — SE keys are P-256, i.e. classical public-key crypto.
  The AK lives in `sodium_malloc` memory and is zeroed on lock.
- Refuse server-supplied KDF params below the published floor.
- Never put decrypted content into Spotlight, Siri/App Intents donations,
  Handoff, widgets or notification actions.
- Auto-lock after 15 minutes idle unless the user chose stay-unlocked on
  this device (same defaults as web).
- No third-party analytics, trackers or ad SDKs. No shipping Crashlytics /
  Amplitude / etc. without an explicit local plan decision.
- Network: TLS to `dayrule.app` only (plus HIBP range API for breached-
  password checks, same k-anonymity rules as web; plus the local server in
  Debug builds only). Certificate pinning is deferred until Cloudflare (or
  equivalent) terminates TLS; do not silently add pins against
  Vercel-issued certs.
- Reminders are local notifications only; the app never registers
  reminders with the server and has no APNs entitlement.
- Auth from the app uses the native session model
  (`Authorization: Bearer` + `X-Dayrule-Client: ios/<build>` or
  `macos/<build>`). Do not stuff passwords into the Keychain beyond what
  unlock requires; never log bodies, tokens or recovery words.
- Never write secrets into code, docs, commits or PR text. Use env /
  Xcode scheme variable **names** only.
