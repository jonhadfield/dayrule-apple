# Dayrule for Apple

**Native SwiftUI companion to [Dayrule](https://dayrule.app) for iPhone, iPad and Mac.**

Same paper-and-ink identity, vocabulary, domain model, sync protocol and
end-to-end encryption as the web app — one multiplatform Xcode target and
one source tree.

Web / API: [`dayrule`](https://github.com/jonhadfield/dayrule) · Product:
[dayrule.app](https://dayrule.app)

---

## What you get

- **Inbox, Today, Scheduled, Backlog, Done, Trash** — plus projects, areas,
  tags, repeats and local reminders
- **Ciphertext at rest** — the on-device store holds encrypted records only
- **Account key in memory** while unlocked; Keychain device wrap (no Secure
  Enclave wrap of user data)
- **Sync** with the same wire format and crypto suite (**ALG = 1**) as web
- **Share extension** and optional import of Dayrule (or Things 3 intermediate)
  export JSON

## Requirements

- macOS with Xcode matching CI
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`xcodegen`)
- For sync tests: local Go API from the web repo (`web/e2e/serve-api.sh`)

## Build

```bash
xcodegen generate
xcodebuild -scheme Dayrule -destination 'platform=iOS Simulator,name=<simulator>' test
xcodebuild -scheme Dayrule -destination 'platform=macOS' build
```

Pick a simulator that exists: `xcrun simctl list devices available`.

Debug builds may point at a local API; TestFlight / Release use
`https://dayrule.app`. Never ship a preview-deployment bypass token in the
binary.

## Shared fixtures

`docs/shared/` mirrors crypto and domain vectors from the web repo. Update
only with:

```bash
./scripts/sync-shared.sh <dayrule-sha>
```

Pinned by `docs/shared/SHARED.lock`. Do not hand-edit the mirror.

## Security (short)

- Encryption on device before any network write
- No decrypted content in Spotlight, Siri donations, Handoff, widgets or
  notification actions
- No third-party analytics or crash SDKs
- Reminders are local notifications only (no APNs)

Native threat-model deltas: [`docs/threat-model-native.md`](docs/threat-model-native.md).

## Repository layout

- `Dayrule/` — app sources (SwiftUI, domain, sync, crypto, design)
- `DayruleTests/` / `DayruleUITests/` — unit and UI tests
- `project.yml` — XcodeGen source of truth
- `docs/` — threat model, App Store notes, shared vectors

Contributor conventions: [`AGENTS.md`](AGENTS.md).

## Licence

Source is published for transparency alongside the web app. Dayrule the
product remains invite-only at [dayrule.app](https://dayrule.app).

> _Temporary CodeRabbit smoke-test PR — safe to close._
