-- aegis-sync-os: the AEGIS OS sync backend's schema (OS-owned storage).
--
-- ISOLATION RULE: the browser's aegis-sync database is bound as BROWSER and
-- is READ-ONLY (enforced by src/guard.js). Everything in this file applies
-- to the OS database ONLY and must never be run against the browser DB.
--
-- Identity field ownership:
--   email / username   — reused from the browser backend (cached at login,
--                        source of truth stays in the browser users table)
--   avatar_url / display_name — OS-owned fields, stored ONLY here.

CREATE TABLE IF NOT EXISTS identities (
  user_id      TEXT PRIMARY KEY,               -- mirrors the browser users.id (read-only reference)
  email        TEXT NOT NULL,                  -- cached at login (reused browser field)
  username     TEXT,                           -- cached at login (reused browser field)
  avatar_url   TEXT,                           -- OS-owned
  display_name TEXT,                           -- OS-owned
  updated_at   INTEGER NOT NULL                -- unix seconds
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_identities_username
  ON identities(username) WHERE username IS NOT NULL;

CREATE TABLE IF NOT EXISTS sessions (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id    TEXT NOT NULL,
  device_id  TEXT,
  kind       TEXT NOT NULL CHECK (kind IN ('access','refresh')),
  token_hash BLOB NOT NULL UNIQUE,             -- SHA-256(token); raw token never stored
  expires_at INTEGER NOT NULL,
  created_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS devices (
  user_id      TEXT NOT NULL,
  id           TEXT NOT NULL,                  -- client-generated UUID, stable per install
  name         TEXT NOT NULL,
  platform     TEXT NOT NULL CHECK (platform IN ('android','windows','linux','macos','other')),
  created_at   INTEGER NOT NULL,
  last_seen_at INTEGER NOT NULL,
  PRIMARY KEY (user_id, id)
);

-- OS sync items: the OS field set. Deliberately separate from the browser's
-- sync_items (bookmark/tab/setting/password/autofill) — an OS client push of
-- a browser item type is a 400, and vice versa.
CREATE TABLE IF NOT EXISTS os_items (
  event_id   INTEGER PRIMARY KEY AUTOINCREMENT,  -- the pull cursor
  user_id    TEXT NOT NULL,
  item_type  TEXT NOT NULL CHECK (item_type IN ('os-setting','os-profile','os-notes','os-keyring','os-island')),
  item_key   TEXT NOT NULL,                      -- client UUID for the object
  version    INTEGER NOT NULL DEFAULT 1,         -- optimistic-concurrency counter
  ciphertext BLOB,                               -- NULL on tombstones (E2E-encrypted by the client)
  nonce      BLOB,
  deleted    INTEGER NOT NULL DEFAULT 0,         -- 1 = tombstone
  device_id  TEXT,
  updated_at INTEGER NOT NULL,
  UNIQUE (user_id, item_type, item_key)
);

CREATE TABLE IF NOT EXISTS rate_limits (
  key          TEXT PRIMARY KEY,
  window_start INTEGER NOT NULL,
  count        INTEGER NOT NULL
);
