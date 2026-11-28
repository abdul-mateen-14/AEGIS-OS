# aegis-sync-os — the AEGIS OS sync backend

The OS-side Cloudflare Worker that syncs OS data (settings, profiles,
notes, keyrings, island preferences) and resolves the shared Aegis
identity for OS surfaces. The browser's primary backend
(`aegis-sync`, in [AEGIS-BROWSER](https://github.com/abdul-mateen-14/AEGIS-BROWSER))
is **never deployed, modified or written to from here**.

## Identity: one Aegis ID, two backends

| Field | Owner | How the OS uses it |
| --- | --- | --- |
| `email` | browser DB (primary) | reused read-only at login; cached into the OS `identities` table |
| `username` | browser DB (primary) | reused read-only; cached; resolved publicly by `/v1/os/identity/:username` |
| `avatar_url` | **OS-owned** | set via `PUT /v1/os/identity`; lives only in the OS DB |
| `display_name` | **OS-owned** | set via `PUT /v1/os/identity`; lives only in the OS DB |
| `password / verifier / vault key` | browser DB (primary) | the SAME verifier logs into both — one password, one identity |

There is **no registration on the OS backend**: accounts are created by the
browser (or the browser client) in `aegis-sync`. An OS login with the same
email + verifier authenticates against the browser database **read-only**
and gets the same identity, including the wrapped vault key so the client
derives the same end-to-end keys.

## Isolation guarantees

1. **Route namespace**: every OS endpoint lives under `/v1/os/…`; the
   browser backend's `/v1/…` routes can never collide.
2. **Separate storage**: OS data (sessions, devices, `os_items`,
   identities, rate limits) lives in a separate D1 database
   (`aegis-sync-os`). Browser sync items (`bookmark/tab/setting/password/
   autofill`) and OS items (`os-setting/os-profile/os-notes/os-keyring/
   os-island`) are disjoint type sets — pushing a browser type here is a
   400, and vice versa.
3. **Read-only guard**: the browser database is bound as `BROWSER`, and
   every statement aimed at it goes through `src/guard.js`, which rejects
   anything that is not a single `SELECT`/`WITH` read (write verbs,
   `PRAGMA`, multi-statement injection — all rejected; unit-tested in
   `test/guard.test.mjs`).
4. **No deploy path**: CI deploys ONLY `aegis-sync-os`. The `aegis-sync`
   worker belongs to the browser repo and its pipeline.

## API (mirrors the browser backend's shapes)

| Method | Path | Auth | Notes |
| --- | --- | --- | --- |
| GET | `/health` | — | `{ok, service:"aegis-sync-os", identity:"browser-primary"}` |
| GET | `/v1/os/auth/kdf-params?email=` | — | proxied read from the browser DB (fake salt for unknown emails) |
| POST | `/v1/os/auth/login` | — | `{email, verifier_b64, device{id,name,platform}}` → tokens + user + identity |
| POST | `/v1/os/auth/refresh` | — | refresh-token rotation (same semantics as the browser backend) |
| POST | `/v1/os/auth/logout` | Bearer | kills the presented access token |
| GET | `/v1/os/identity` | Bearer | own identity + `field_sources` (browser vs os) |
| PUT | `/v1/os/identity` | Bearer | `{avatar_url?, display_name?}` — OS-owned fields only |
| GET | `/v1/os/identity/:username` | — | public resolution: `{username, avatar_url, display_name, source}` |
| GET | `/v1/os/devices` | Bearer | OS devices seen |
| POST | `/v1/os/sync/push` | Bearer | `{items:[{item_type, item_key, base_version, ciphertext_b64, nonce_b64, deleted?}]}` |
| GET | `/v1/os/sync/pull?cursor=&types=` | Bearer | cursor page (os item types only) |
| GET | `/v1/os/sync/cursor` | Bearer | current head cursor |
| GET | `/v1/os/sync/export` | Bearer | full export paging |
| DELETE | `/v1/os/account` | Bearer | wipes THIS user's OS rows; the browser account is untouched |

Password changes happen in the browser backend (it owns the verifier and
vault wrapping); the OS side simply re-logins afterwards.

## Development

```bash
node --test services/aegis-sync-os/test/        # unit tests (no deps)
npx wrangler d1 migrations apply aegis-sync-os --remote   # from this dir
npx wrangler deploy                                      # from this dir
```

Deployment needs `CLOUDFLARE_API_TOKEN` + `CLOUDFLARE_ACCOUNT_ID` (GitHub
Actions secrets; never committed). The live worker:
`https://aegis-sync-os.abdulmateen14.workers.dev`.
