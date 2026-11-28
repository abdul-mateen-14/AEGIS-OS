-- aegis-id-db: the identity portal's own storage.
--
-- ACCOUNTS THEMSELVES live in the primary aegis-sync database (created via
-- its public API — the portal is just a client of the primary backend, with
-- NO direct binding to the browser/OS databases).
-- This DB holds only what the PORTAL owns: web sessions, the Google-links,
-- the server-held credentials for Google accounts (documented: server-
-- managed, not zero-knowledge), and WebAuthn passkeys.

CREATE TABLE IF NOT EXISTS portal_sessions (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  token_hash    TEXT NOT NULL UNIQUE,        -- hex sha256 of the cookie value
  user_id       TEXT NOT NULL,               -- primary backend users.id
  email         TEXT NOT NULL,
  -- refresh tokens for the two sync backends (access tokens minted on demand)
  primary_refresh TEXT,
  os_refresh      TEXT,
  created_at    INTEGER NOT NULL,
  last_seen_at  INTEGER NOT NULL,
  expires_at    INTEGER NOT NULL,
  user_agent    TEXT,
  ip            TEXT
);

CREATE TABLE IF NOT EXISTS linked_tokens (
  user_id         TEXT PRIMARY KEY,          -- primary backend users.id
  email           TEXT NOT NULL,
  primary_refresh TEXT,                      -- portal-web device session on aegis-sync
  os_refresh      TEXT,                      -- portal-web device session on aegis-sync-os
  updated_at      INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS google_identities (
  user_id       TEXT PRIMARY KEY,            -- same user_id as the primary backend
  google_sub    TEXT NOT NULL UNIQUE,        -- stable Google subject id
  email         TEXT NOT NULL,
  -- server-held credential for Google accounts (random 32B, base64).
  -- Used to mint sessions on the primary/OS backends; never exposed.
  verifier_b64  TEXT NOT NULL,
  vault_key_b64 TEXT NOT NULL,               -- server-managed vault (see docs)
  created_at    INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS oauth_state (
  state       TEXT PRIMARY KEY,              -- CSRF nonce
  created_at  INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS passkeys (
  id            TEXT PRIMARY KEY,            -- credential id (base64url)
  user_id       TEXT NOT NULL,
  email         TEXT NOT NULL,
  public_key    TEXT NOT NULL,               -- COSE key, base64
  counter       INTEGER NOT NULL DEFAULT 0,
  transports    TEXT,
  device        TEXT,                        -- friendly name from the authenticator
  created_at    INTEGER NOT NULL,
  last_used_at  INTEGER
);

CREATE TABLE IF NOT EXISTS webauthn_challenges (
  id          TEXT PRIMARY KEY,              -- random handle
  user_id     TEXT,                          -- null for login-by-email-less flow
  email       TEXT,
  kind        TEXT NOT NULL CHECK (kind IN ('register','login')),
  challenge   TEXT NOT NULL,
  created_at  INTEGER NOT NULL
);
