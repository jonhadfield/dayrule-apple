# App Review demo account

Apple needs a working sign-in for Guideline 2.1. Dayrule is end-to-end
encrypted and invite-only, so reviewers **sign in** to a pre-made production
account (they do not sign up). Put the email and password only in
**App Store Connect → App Review Information**. Never commit them, never put
them in this repo, PR text, Issues or chat logs that are retained in git.

## Requirements

| Requirement | How Dayrule meets it |
|---|---|
| Production backend live during review | `https://dayrule.app` (same host the Release/TestFlight app uses) |
| Sign-in required | Email + password on the Gate screen |
| No SMS / email OTP at sign-in | Login uses password (and optional second step). **Do not enable** passkey, TOTP or backup codes on this account |
| No invite at review time | Account already exists; Review Notes say “Sign in”, not “Create account” |
| Non-empty app | After creating the account, add a handful of sample to-dos (Inbox / Today / a project) and let them sync |
| Credentials do not expire | Use a dedicated mailbox you control; do not rotate the password mid-review |

Two-step sign-in stays **off** for this account (PLAN gate: “no second step”).
Your own account can keep two-step on.

## Create the account (once)

1. Mint a single-use invite against **production** Neon `main` (unpooled URL):

   ```bash
   cd /path/to/dayrule/server
   DATABASE_URL_UNPOOLED='…' go run ./cmd/invite 1
   ```

   The code prints once; only its hash is stored.

2. On a device or simulator build pointed at production, **Create account**
   with a dedicated address (e.g. a plus-address on your domain) and a strong
   unique password. Enter the invite when asked. Complete email verification.

3. When the app offers two-step sign-in after sign-up, choose **Not now**.
   Do not turn it on later under Settings for this account.

4. Save the **24-word recovery phrase** offline (password manager / paper).
   Reviewers do not need it if the password works; you need it if the
   password is ever lost. Never put the recovery phrase in App Store Connect.

5. Add sample content (a few Inbox items, one for Today, one dated Scheduled,
   one small project). Confirm Settings shows a recent sync.

6. Sign out, sign back in once with only email + password to confirm the path
   reviewers will use. Lock and unlock once.

7. In App Store Connect → the iOS app → **App Review Information**:
   - Enable **Sign-in required**
   - Username = the demo email
   - Password = the demo password
   - Contact info = you

8. Paste Review Notes (adapt as needed). Use the **full template** under
   [App Review Information (Notes)](#app-review-information-notes) so a
   Guideline 2.1 “information needed” rejection is covered in one place.

## App Review Information (Notes)

Paste the block below into **App Store Connect → App Review Information → Notes**
and into the Resolution Center reply when Apple asks for items 1–6. Keep the
demo email/password only in the Sign-in required fields (and the same values
in the reply if they ask again). Never put the 24-word recovery phrase here.

### Screen recording (you capture; attach in Resolution Center)

Record on a **physical iPhone** on the latest iOS. Start from a cold launch:

1. Launch Dayrule → Gate → sign in with the demo email/password (Sign-in
   required fields). Leave Stay unlocked off or on as you prefer; no
   second-step prompts on this account.
2. After unlock: open **Today**, **Inbox**, **Scheduled**, **Backlog**, a
   **project** if seeded; edit a to-do (title / notes / checklist); Add one
   item; complete one; open **Settings** (sync status, appearance).
3. **Account creation:** open Create account briefly and show that an
   **invite code** is required, then Cancel — reviewers must use the demo
   sign-in, not self-serve signup.
4. **Account deletion:** Settings → scroll to **Delete account** → open the
   confirmation. **Cancel** (do not confirm on the shared demo account).
   State in Notes that confirming would destroy the review vault; the control
   is live and completes deletion when confirmed.
5. No in-app purchases, subscriptions or paid unlocks.
6. No public / social user-generated content: to-dos are private and
   end-to-end encrypted; other users cannot see them, so there is no
   report/block of third-party content.

Attach the recording to the Resolution Center reply (and keep a copy for
resubmits).

### Notes / Resolution Center text (items 2–6 + how to use the app)

```
Dayrule — App Review notes

1) Screen recording
Attached: physical-device recording starting at cold launch, demo sign-in,
main lists, edit/Add, Settings, Create account (invite required — cancelled),
Delete account confirmation (cancelled so the demo account remains).

2) Purpose and audience
Dayrule is a personal to-do and planning app for individuals who want a calm
“paper and ink” interface and end-to-end encryption. It organises work into
Inbox, Today, Scheduled, Backlog (including Not now), Done and Trash, plus
user projects. Titles, notes, checklists and structure are encrypted on
device before sync; the server cannot read user content. Target audience:
people who want a private task list that syncs across iPhone, iPad, Mac and
the companion web app at dayrule.app — not teams, social feeds or public
sharing.

3) Setup and main features
• Sign-in required: use the Username/Password in App Review Information.
  Do not create a new account (signup is invite-only).
• No SMS, email OTP, TOTP or passkey second step on this demo account.
• After unlock: tabs / sidebar — Inbox, Today, Scheduled, Backlog, Done,
  Trash; open a project from the sidebar; tap a row to edit; use Add;
  Settings for sync, appearance, Help, export and Delete account.
• Mac: lists are a sidebar (Inbox · Today · Scheduled · Backlog · Done ·
  Trash), not phone tabs. New List under the sidebar creates a Project or
  Area. Lock is ⇧⌘L or the toolbar lock. Settings is ⌘,; Find is ⌘F.
• Sample to-dos are pre-seeded and synced. Editing/completing them is fine.
• Lock: Settings toolbar lock, or idle auto-lock (~15 min) unless Stay
  unlocked was chosen at sign-in. Unlock with the same password.
• Privacy / Terms: Settings → Help → Legal.

4) External services (core functionality)
• Dayrule API and sync: https://dayrule.app (our backend; hosted on Vercel;
  encrypted records stored in Neon/Postgres in London). Authentication and
  sync only — no plaintext to-do content on the server.
• Have I Been Pwned password range API (k-anonymity) when setting/changing
  a password — direct from device, fails open.
• Apple platforms only on device: Keychain, optional biometrics / passkey
  unlock (not enabled on the demo account), local notifications for
  reminders (no APNs server registration).
• No third-party analytics, ads, payment processors, AI APIs or social SDKs.

5) Regional differences
The app functions the same in all regions. There is no region-locked
content, pricing tier or feature flag by country.

6) Regulated industry / protected third-party material
Not applicable. Dayrule is a general personal productivity app. It does not
operate in a highly regulated industry and does not include protected
third-party media or credentials beyond the user’s own account.
```

## Maintain

- Before each App Review or external TestFlight that Apple staff may use,
  sign in once and confirm unlock + sync still work.
- If the password must change, update App Store Connect in the same sitting.
- Do not reuse this account as your personal Dayrule account.
- Deleting the account (`Settings → Delete account`) destroys the demo; only
  do that when retiring it, then create a fresh one with a new invite.

## Related (not this doc)

- Agent / automation test account (separate mailbox + `agent-creds.txt`):
  `docs/agent-test-account.md`. Do not reuse this App Review account there.
- Privacy nutrition label and export-compliance / encryption declaration:
  still open on `docs/security-checklist.md`.
- `MIN_IOS_BUILD` / HTTP 426: separate server gate before broad TestFlight.
