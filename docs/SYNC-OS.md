# Aegis Sync (OS) — the sync backend for the operating system

One Aegis ID, two backends. The browser's `aegis-sync`
([AEGIS-BROWSER/aegis-sync](https://github.com/abdul-mateen-14/AEGIS-BROWSER/tree/main/aegis-sync))
is the **primary identity backend**: accounts live there, passwords
(verifiers) live there, the vault key wrapping lives there. The OS
backend (`aegis-sync-os`, this repo `services/aegis-sync-os/`) never
duplicates any of that — it authenticates against the primary backend
**read-only** and stores only OS-owned data.

Live worker: `https://aegis-sync-os.abdulmateen14.workers.dev`
(source: [`services/aegis-sync-os/`](../services/aegis-sync-os/), API
table in its README).

## Why the OS does not get its own accounts

The user's rule: *"do not affect any old database users data and fields,
use new ones for Operating System, and some fields of aegis-sync browser
like email username and avatar etc that can be reused."* Concretely:

- The browser DB keeps its schema, its rows, its field set — byte for
  byte. The OS backend was deployed as a NEW worker (`aegis-sync-os`)
  with a NEW D1 database (`aegis-sync-os`); the `aegis-sync` worker was
  never redeployed from here.
- The OS reuses identity FIELDS, not storage: `email` and `username`
  are read from the browser `users` table at login (SELECT-only) and
  cached into the OS `identities` table.
- OS-only fields (`avatar_url`, `display_name`) live in the OS DB —
  the browser DB has no avatar column and gains none.

Result: the same email + password that unlocks Aegis Browser sync logs
into the OS and resolves to the same identity — same username, same
avatar — with zero risk to the 5 existing browser users.

## The three field sets

| Set | Where | Fields |
| --- | --- | --- |
| Identity (primary, read-only for OS) | browser `users` | `email`, `username`, `kdf_*`, `verifier_hash`, `wrapped_vault_key`, `vault_nonce` |
| OS profile (OS-owned) | OS `identities` | `avatar_url`, `display_name` (+ cached `email`, `username`) |
| OS sync data (OS-owned, E2E) | OS `os_items` | `os-setting`, `os-profile`, `os-notes`, `os-keyring`, `os-island` × {`ciphertext`, `nonce`, `version`, `deleted`, `device_id`, `updated_at`} |

The browser's sync items (`bookmark/tab/setting/password/autofill`) and
the OS's (`os-*`) are disjoint CHECK-constrained sets — a browser-type
push to the OS backend is a 400, and vice versa.

## Isolation enforcement (machine-checked)

1. **Statement guard** — every browser-DB statement goes through
   `src/guard.js`, which accepts only a single `SELECT`/`WITH` (write
   verbs, `PRAGMA`, `ATTACH`, multi-statement injection rejected);
   unit tests: `test/guard.test.mjs`.
2. **Namespace split** — all OS routes live under `/v1/os/…`.
3. **Type split** — item-type CHECK constraints on both sides.
4. **Deploy split** — CI deploys only `aegis-sync-os`; the structure
   job fails if the worker name ever matches the browser's.
5. **Live proof** — the smoke test snapshots the browser DB row counts
   before the run and requires equality after (run 2026-11-28:
   32/32 checks passed, counts identical).

## How the clients use it

- **Aegis Browser** keeps talking to `aegis-sync` exactly as before —
  untouched, still primary.
- **AEGIS OS (CoreX + Aegis ID)**: the OS client fetches
  `/v1/os/auth/kdf-params`, derives the verifier client-side (same
  PBKDF2-SHA256 chain), logs in via `/v1/os/auth/login` (browser DB
  read-only), receives the wrapped vault key so end-to-end keys match
  the browser's, then syncs OS data via `/v1/os/sync/*`. The Aegis ID
  card renders `GET /v1/os/identity` (own profile) and resolves any
  user via the public `GET /v1/os/identity/:username`.
- **Credentials**: the Cloudflare API token lives only in GitHub
  Actions secrets (`CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`);
  deploys happen from CI on main.
