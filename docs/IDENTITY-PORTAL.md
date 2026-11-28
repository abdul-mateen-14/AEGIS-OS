# Aegis ID — the central identity portal

**https://aegis-id.pages.dev** — the clean web front door for the Aegis
identity: create an account, sign in (password-derived verifier,
**Google**, or a **passkey**), and manage profile, connections,
passwords and settings for Aegis Browser, AEGIS OS and anything else
connected. Source: [`services/aegis-id-portal/`](../services/aegis-id-portal/)
(Cloudflare Pages + Functions on the same account as the sync backends).

## What it is

One account, usable everywhere, created here:

- **Create account** — the page derives everything client-side with the
  SAME crypto the browser and Android clients use (vendored verbatim,
  vector-tested against the Kotlin suite): password → masterKey
  (PBKDF2-SHA256, 600k) → verifier, vault key wrapped under the KEK.
  The password never leaves the device; the portal forwards the derived
  material to the PRIMARY backend's public register API. The account
  that is created is the SAME account the browser and OS log into.
- **Sign in** — three paths:
  1. email + password → verifier (identical protocol to the clients),
  2. **Google** — OAuth (authorization code, confidential client). A
     Google login either LINKS to the existing account with the same
     email, or creates one with a SERVER-generated credential (see the
     honest trade-off below),
  3. **Passkey** — WebAuthn (@simplewebauthn). Works for Google-managed
     accounts via the held verifier and for password accounts via the
     refresh tokens the portal stored at their last password sign-in.
- **Manage** — profile (avatar + display name = OS-owned fields; email +
  username = browser-owned, read-only here), security (passkeys, password
  change with vault-key re-wrap, done client-side), **connections**
  (browser-sync devices, OS-sync devices, portal sessions), and the
  danger zone (full identity deletion).

## Where the data lives

| Thing | Storage |
| --- | --- |
| Accounts, verifiers, wrapped vault keys, browser sync items | primary `aegis-sync` D1 (via its public API only) |
| Avatar / display name, OS sync items | `aegis-sync-os` D1 (via its public API only) |
| Portal sessions, Google links + server-held credentials, passkeys | `aegis-id-db` (this project's own D1) |

The portal has **no D1 binding to either sync database** — it is just a
client of their public APIs, so the browser backend stays untouched and
the isolation guarantees from [`docs/SYNC-OS.md`](SYNC-OS.md) hold.

## Honest security notes

- **Password accounts stay zero-knowledge**: the verifier exists only on
  the user's devices; the server keeps its SHA-256.
- **Google accounts are server-managed** (like every OAuth-plus-vault
  product): the portal generates their verifier and vault key and holds
  them in `aegis-id-db` to mint sessions on the sync backends. Synced
  vault DATA for Google accounts is therefore server-visible. The
  register page and the dashboard say so.
- **Portal sessions** are HttpOnly + Secure cookies, 14 days, stored
  hashed; sync refresh tokens live server-side per user
  (`linked_tokens`) so passkey logins work without the password.
- **Rate limits**: the primary backend throttles by IP, and every portal
  request shares one IP — the browser repo should raise
  `login|ip`/`register|ip` limits as portal traffic grows (one-line
  change there; the portal cannot do it).

## Google sign-in activation (one-time, account owner)

1. Google Cloud Console → create an **OAuth client ID** (Web application)
   with redirect URI `https://aegis-id.pages.dev/api/auth/google/callback`.
2. Set the project secrets:
   ```bash
   npx wrangler pages secret put GOOGLE_CLIENT_ID --project-name aegis-id
   npx wrangler pages secret put GOOGLE_CLIENT_SECRET --project-name aegis-id
   ```
3. Done — `/api/auth/google-status` flips to `configured:true` and the
   portal shows the Google button. Until then the button is hidden and
   `/api/auth/google/start` returns a clean 503.

## Development / ops

```bash
node --test services/aegis-id-portal/test/crypto.test.mjs \
           services/aegis-id-portal/test/helpers.test.mjs     # parity + helpers
cd services/aegis-id-portal && npm install && npx wrangler@4 pages deploy
node services/aegis-id-portal/test/smoke-live.mjs               # full live flow
```

Deployment is CI-automated (main only) with a read-only live smoke.
Last full live smoke (2026-11-28): **20 pass, 0 fail**, browser DB row
counts identical before/after (register → profile → connections →
password change with vault re-wrap → negatives → deletion → isolation).
