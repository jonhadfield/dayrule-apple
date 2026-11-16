# Agent test account

Separate from the **App Review** demo account (`docs/app-review-demo.md`).
Reviewers and App Store Connect use that one; local automation (screenshot
scripts, Mac UI driving, etc.) uses this one.

| | App Review | Agent |
|---|---|---|
| Purpose | Apple Guideline 2.1 | Local capture / automation |
| Creds file | `creds.txt` (gitignored) | `agent-creds.txt` (gitignored) |
| Where else | App Store Connect only | Never ASC; never commit |
| Seed | Sample lists for screenshots | Same shape (Kitchen, Garden, Holidays, House) |

## Create (once)

1. Mint a production invite (unpooled URL):

   ```bash
   cd /path/to/dayrule/server
   DATABASE_URL_UNPOOLED='…' go run ./cmd/invite 1
   ```

   Optionally save the code to gitignored `agent-invite.txt` until used.

2. Generate a strong password into `agent-creds.txt` (email line, then password):

   ```text
   agent-dayrule@your-domain
   <password>
   ```

3. On a build pointed at `https://dayrule.app`, **Create account** with that
   email, the invite, and the password. Skip two-step (**Not now**). Save the
   recovery phrase offline (not in this repo).

4. Seed sample content on the agent vault (encrypted on device — the server
   never sees plaintext). There is no server-side plaintext seeder.

   **iPhone / iPad (preferred for first seed + ASC PNGs):** the UITest harness
   signs in against production, creates dense lists + Kitchen / Garden /
   Holidays / House, syncs, then captures:

   ```bash
   CAPTURE=iphone ./scripts/capture-app-store-screenshots.sh agent-creds.txt
   CAPTURE=ipad   ./scripts/capture-app-store-screenshots.sh agent-creds.txt
   ```

   **Mac:** `scripts/capture-mac-agent.py` signs in, waits until Kitchen is
   visible (so a personal vault is never captured), seeds denser Today /
   Scheduled / Backlog / projects via the list Add field, Sync now, then
   writes PNGs:

   ```bash
   python3 scripts/capture-mac-agent.py agent-creds.txt
   ```

   Resize Retina window captures before ASC upload (see `docs/mac-app-store.md`):

   ```bash
   mkdir -p docs/app-store-screenshots/macos-2560x1600
   for f in docs/app-store-screenshots/macos/*.png; do
     sips -z 1600 2560 "$f" --out "docs/app-store-screenshots/macos-2560x1600/$(basename "$f")"
   done
   ```

5. Capture entry points (scripts default to `agent-creds.txt` when present —
   never to App Review `creds.txt`):

   ```bash
   python3 scripts/capture-mac-agent.py agent-creds.txt
   CAPTURE=iphone ./scripts/capture-app-store-screenshots.sh agent-creds.txt
   CAPTURE=ipad   ./scripts/capture-app-store-screenshots.sh agent-creds.txt
   # fallbacks:
   CAPTURE=macos ./scripts/capture-app-store-screenshots.sh agent-creds.txt
   ./scripts/capture-mac-asc-applescript.sh agent-creds.txt
   ```

## Rules

- Do not reuse the App Review mailbox or password here.
- Do not put either password in PLAN, PRs, Issues, or chat that is retained in git.
- Rotate `agent-creds.txt` freely; update ASC only when the App Review account changes.
