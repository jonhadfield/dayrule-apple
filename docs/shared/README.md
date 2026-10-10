# Shared fixtures

Known-answer fixtures for Dayrule clients (web, Go crypto mirror, native
app). Generated in this repo; never hand-edited in `dayrule-apple`.

| File | Source |
|---|---|
| `crypto-vectors.json` | Mirror of `docs/crypto-vectors.json` (`web/src/crypto/vectors.test.ts`, `UPDATE_CRYPTO_VECTORS=1`); Go still reads `docs/crypto-vectors.json`. Includes sync envelope / recovery-proof W0 fields. |
| `domain-vectors.json` | `web/src/domain/domain-vectors.test.ts` (`WRITE_DOMAIN_VECTORS=1`) |
| `sync-pull-fixture.json` | Minimal pull response shape for native contract tests |

Native mirror: `dayrule-apple/scripts/sync-shared.sh <sha>`.
