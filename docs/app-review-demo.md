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

8. Paste Review Notes (adapt as needed):

   ```
   Sign in with the demo account (Sign-in required fields). Do not create a new account — signup is invite-only.

   After unlock, use the bottom tabs (Inbox · Today · Scheduled · Browse).
   Sample to-dos are already synced. Completing or editing items is fine; data is end-to-end encrypted on device.

   Dayrule locks after 15 minutes idle unless “Stay unlocked on this device” is on. Re-enter the same password to unlock. There is no SMS or authenticator step on this account.

   Privacy and Terms: Settings → Help → Legal.
   ```

## Maintain

- Before each App Review or external TestFlight that Apple staff may use,
  sign in once and confirm unlock + sync still work.
- If the password must change, update App Store Connect in the same sitting.
- Do not reuse this account as your personal Dayrule account.
- Deleting the account (`Settings → Delete account`) destroys the demo; only
  do that when retiring it, then create a fresh one with a new invite.

## Related (not this doc)

- Privacy nutrition label and export-compliance / encryption declaration:
  still open on `docs/security-checklist.md`.
- `MIN_IOS_BUILD` / HTTP 426: separate server gate before broad TestFlight.
