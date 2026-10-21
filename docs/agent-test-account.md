# Agent test account

Separate from the **App Review** demo account (`docs/app-review-demo.md`).
Reviewers and App Store Connect use that one; local automation (screenshot
scripts, Mac UI driving, etc.) uses this one.

| | App Review | Agent |
|---|---|---|
| Purpose | Apple Guideline 2.1 | Local capture / automation |
| Creds file | `creds.txt` (gitignored) | `agent-creds.txt` (gitignored) |
| Where else | App Store Connect only | Never ASC; never commit |
| Seed | Sample lists for screenshots | Same shape (Kitchen, etc.) is fine |

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

4. Seed sample content (Inbox / Today / Scheduled / a **Kitchen** project with
   “Paint the cupboards”) and confirm sync. Prefer the encrypted sync seeder
   (server never sees plaintext):

   ```bash
   cd /path/to/dayrule/server
   go run ./cmd/seed-agent -api https://dayrule.app -creds /path/to/dayrule-apple/agent-creds.txt
   ```

   Then **Sync now** (or lock/unlock) on the Mac Debug build. Screenshot
   scripts refuse to write PNGs until Kitchen is visible so a personal vault
   is never captured by mistake.

5. Point capture at the agent file:

   ```bash
   CAPTURE=macos ./scripts/capture-app-store-screenshots.sh agent-creds.txt
   # or
   ./scripts/capture-mac-asc-applescript.sh agent-creds.txt
   ```

   Scripts default to `agent-creds.txt` when present, else fall back to an
   explicit path argument — not to `creds.txt`.

## Rules

- Do not reuse the App Review mailbox or password here.
- Do not put either password in PLAN, PRs, Issues, or chat that is retained in git.
- Rotate `agent-creds.txt` freely; update ASC only when the App Review account changes.
