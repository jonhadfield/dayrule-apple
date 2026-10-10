# Dayrule iOS

Native SwiftUI companion to the Dayrule web app
(`/Users/hadfielj/Repositories/dayrule`). Same "paper and ink" identity,
vocabulary, domain model, sync protocol and end-to-end encryption. This
repo's `PLAN.md` is the source of truth for **native** choices; the web
repo's `PLAN.md` remains the source of truth for shared product, crypto
(§10), sync (§11) and decisions (§17). Read the relevant section before
changing behaviour, and update this `PLAN.md` in the same change when a
native decision changes. When a shared rule changes, update the web
`PLAN.md` first (or in the same coordinated change).

## Layout

- `Dayrule/` — app target (SwiftUI views, domain, store, sync, crypto,
  persistence, design system).
- `DayruleTests/` — unit tests (domain, merge, crypto vectors).
- `DayruleUITests/` — UI tests.
- `docs/` — iOS threat-model deltas; `docs/shared/` is a mirror of
  `dayrule/docs/shared/` (crypto vectors, wire fixtures, domain vectors),
  updated only with `scripts/sync-shared.sh <sha>` and pinned by
  `docs/shared/SHARED.lock`. Never hand-edit the mirror.
- `PLAN.md` — this repo's build plan and native decisions log.

## Commands

From the repo root (requires a Mac and the Xcode version pinned in CI;
pick a simulator that exists with `xcrun simctl list devices available`):

- `xcodebuild -scheme Dayrule -destination 'platform=iOS Simulator,name=<simulator>' test` — unit + UI tests.
- `xcodebuild -scheme Dayrule -destination 'generic/platform=iOS' build` — release-shaped build.
- `swift test` — only if a SwiftPM package target exists for shared pure-Swift modules.

Development and UI tests run against a **local Go server** started with
`dayrule/web/e2e/serve-api.sh` (PLAN §9.6); set the base URL in the scheme's
environment (never commit secrets). Don't target `preview.dayrule.app` from
the app: it is behind Deployment Protection and a bypass token must never
ship in a binary. TestFlight builds use the production host
`https://dayrule.app`.

## Workflow rules

- Never commit to `main` directly while it is protected. Feature branch →
  PR → review.
- Do not commit between 09:00 and 17:00 Europe/London, Monday to Friday.
- Coordinated API or crypto changes land in the **web repo first** (or the
  same release train), then this app adopts them. Do not invent a private
  wire format.
- Where the web PLAN and web code disagree, port the code and raise a web
  PLAN fix (PLAN §2, §17).
- One PLAN section or decision per PR, named in the commit message, as in
  the web repo.
- Never test Firewall limits or hammer production auth from CI, review
  accounts or your own connection; automated tests use the local server.

## Identity rules

- Dayrule must never be mistakable for another task manager (web PLAN.md
  §5, decisions 20, 21 and 26). Use Dayrule's own vocabulary in UI and
  code: Inbox, Today, Scheduled, Backlog, Not now, Done, Trash, Add. Never
  borrow another product's list or feature names, colours, icons or
  layouts.
- Use the design tokens in `Dayrule/Design/Tokens.swift` (mirrors
  `web/src/styles/tokens.css`); don't hard-code colours.
- Headings use **Fraunces**; body uses the system sans. Ship Fraunces as
  an app-bundled font (OFL), not a network download.

## Companion rules

- Shared domain types, list selectors, HLC merge, repeat rules, date
  parsing and sync record shapes must stay behaviour-compatible with
  `dayrule/web/src/domain/` and `dayrule/web/src/sync/`. Prefer porting
  tests and known answers over re-deriving rules from memory.
- Wire constants (labels, AAD formats, envelopes, lowercase userId) are in
  PLAN §8.5 and §10.1. Entities preserve unknown fields and their clocks;
  timestamps are `toISOString()` form with milliseconds (PLAN §5.3).
- Crypto suite **ALG = 1** only until a new suite is defined in the web
  PLAN and vectors. Pass the shared vectors in `docs/shared/` in CI.
- The server must never see plaintext user content. Encryption happens on
  device before any network write.

## Security rules (non-negotiable)

- 256-bit symmetric keys only; no classical-only public-key crypto
  protecting user data (web PLAN.md §10.8).
- Account key lives only in the crypto boundary (actor / isolated
  module); UI receives plaintext entities in memory while unlocked, never
  keys.
- At rest on device: **ciphertext only** in the local store. Device wrap
  keys are random 256-bit **Keychain** items
  (`WhenUnlockedThisDeviceOnly`) with a symmetric wrap. **No Secure
  Enclave wrap** — SE keys are P-256, i.e. classical public-key crypto
  (PLAN decision 10). The AK lives in `sodium_malloc` memory and is zeroed
  on lock.
- Refuse server-supplied KDF params below the floor (PLAN §8.6).
- Never put decrypted content into Spotlight, Siri/App Intents donations,
  Handoff, widgets or notification actions (PLAN §1).
- Auto-lock after 15 minutes idle unless the user chose stay-unlocked on
  this device (same defaults as web).
- No third-party analytics, trackers or ad SDKs. No shipping Crashlytics /
  Amplitude / etc. without an explicit PLAN decision.
- Network: TLS to `dayrule.app` only (plus HIBP range API for breached-
  password checks, same k-anonymity rules as web decision 31; plus the local
  server in Debug builds only). Certificate pinning is a later hardening
  decision (PLAN §18, open point 3), not a silent add.
- Reminders are local notifications only; the app never registers
  reminders with the server and has no APNs entitlement (PLAN §11).
- Auth from the app uses the native session model in PLAN §9
  (`Authorization: Bearer` + `X-Dayrule-Client: ios/<build>`). Do not stuff
  passwords into the Keychain beyond what unlock requires; never log
  bodies, tokens or recovery words.
- Never write secrets into code, docs, commits or PR text. Use env /
  Xcode scheme variable **names** only.
