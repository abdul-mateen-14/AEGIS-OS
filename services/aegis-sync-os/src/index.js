// aegis-sync-os — the AEGIS OS sync backend (worker entry point and router).
//
// Relationship to the browser's primary backend (aegis-sync, AEGIS-BROWSER):
//   * The browser backend is the PRIMARY identity provider. Accounts are
//     created there; the OS side never registers users.
//   * OS login authenticates against the browser database READ-ONLY (same
//     email + verifier protocol → the same Aegis ID works on both).
//   * Reused identity fields (read-only from the browser DB): email, username.
//     OS-owned identity fields (stored here): avatar_url, display_name.
//   * OS sync data lives HERE ONLY, with its own field set (os-* item types).
//     The browser database is guarded read-only — see src/guard.js.
//
// All endpoints live under /v1/os/ so the two backends never share a route
// namespace, and response shapes mirror the browser backend so one client
// SDK can talk to both.

import {
  ApiError,
  b64ToBytes,
  bytesToB64,
  constantTimeEqual,
  errResponse,
  json,
  LIMITS,
  normalizeEmail,
  nowSec,
  randomTokenB64,
  readJson,
  requireB64,
  requireString,
  sha256,
  utf8,
} from './util.js';
import { browserFirst, browserPrepare } from './guard.js';
import { normalizeUsername, OS_ITEM_TYPES, validateAvatarUrl, validateDisplayName, VALID_PLATFORMS } from './identity.js';

// ---------- rate limiting (OS-owned table) ----------

async function enforceRateLimit(env, bucket, identity, limit, windowSec) {
  const key = `${bucket}|${identity}`;
  const now = nowSec();
  const row = await env.OS.prepare('SELECT window_start, count FROM rate_limits WHERE key = ?').bind(key).first();
  if (!row || row.window_start + windowSec <= now) {
    await env.OS.prepare(
      'INSERT INTO rate_limits (key, window_start, count) VALUES (?, ?, 1) ON CONFLICT(key) DO UPDATE SET window_start = excluded.window_start, count = 1',
    ).bind(key, now).run();
    return;
  }
  if (row.count >= limit) {
    throw new ApiError(429, 'rate_limited', 'Too many attempts. Try again later.');
  }
  await env.OS.prepare('UPDATE rate_limits SET count = count + 1 WHERE key = ?').bind(key).run();
}

function clientIp(request) {
  return request.headers.get('CF-Connecting-IP') ?? 'unknown';
}

async function sha256Text(text) {
  return bytesToB64(await sha256(utf8.encode(text))).slice(0, 22);
}

// ---------- auth against the browser identity (read-only) ----------

/** GET /v1/os/auth/kdf-params?email= — proxied read; fake salt for unknown emails. */
async function handleKdfParams(request, env, url) {
  const email = normalizeEmail(url.searchParams.get('email') ?? '');
  await enforceRateLimit(env, 'kdf|ip', clientIp(request), 60, 900);

  const user = await browserFirst(
    env.BROWSER,
    'SELECT kdf_salt, kdf_algo, kdf_iterations FROM users WHERE email = ?',
    email,
  );
  if (user) {
    return json({ kdf_salt_b64: bytesToB64(user.kdf_salt), kdf: { algo: user.kdf_algo, iterations: user.kdf_iterations } });
  }
  const fakeSalt = new Uint8Array(16);
  crypto.getRandomValues(fakeSalt);
  return json({ kdf_salt_b64: bytesToB64(fakeSalt), kdf: { algo: 'PBKDF2-SHA256', iterations: 600000 } });
}

/** Creates/refreshes the OS device row and mints a new OS session pair. */
async function createSession(env, userId, device) {
  if (!device || typeof device !== 'object') {
    throw new ApiError(400, 'invalid_request', 'Field "device" is required');
  }
  const deviceId = requireString(device, 'id', 64);
  const deviceName = requireString(device, 'name', 100);
  const platform = String(device.platform ?? 'other');
  if (!VALID_PLATFORMS.includes(platform)) {
    throw new ApiError(400, 'invalid_request', `Field "device.platform" must be one of: ${VALID_PLATFORMS.join(', ')}`);
  }

  const now = nowSec();
  await env.OS.prepare(
    `INSERT INTO devices (user_id, id, name, platform, created_at, last_seen_at)
     VALUES (?, ?, ?, ?, ?, ?)
     ON CONFLICT(user_id, id) DO UPDATE SET name = excluded.name, platform = excluded.platform, last_seen_at = excluded.last_seen_at`,
  ).bind(userId, deviceId, deviceName, platform, now, now).run();

  const accessToken = randomTokenB64();
  const refreshToken = randomTokenB64();

  await env.OS.batch([
    env.OS.prepare('DELETE FROM sessions WHERE user_id = ? AND device_id = ? AND kind = ?').bind(userId, deviceId, 'access'),
    env.OS.prepare('DELETE FROM sessions WHERE user_id = ? AND device_id = ? AND kind = ?').bind(userId, deviceId, 'refresh'),
    env.OS.prepare('INSERT INTO sessions (user_id, device_id, kind, token_hash, expires_at, created_at) VALUES (?, ?, ?, ?, ?, ?)')
      .bind(userId, deviceId, 'access', await sha256(utf8.encode(accessToken)), now + LIMITS.ACCESS_TOKEN_TTL, now),
    env.OS.prepare('INSERT INTO sessions (user_id, device_id, kind, token_hash, expires_at, created_at) VALUES (?, ?, ?, ?, ?, ?)')
      .bind(userId, deviceId, 'refresh', await sha256(utf8.encode(refreshToken)), now + LIMITS.REFRESH_TOKEN_TTL, now),
  ]);

  return { accessToken, refreshToken };
}

/** POST /v1/os/auth/login — verifies against the browser users table READ-ONLY. */
async function handleLogin(request, env) {
  const body = await readJson(request, LIMITS.MAX_BODY_BYTES);
  const email = normalizeEmail(requireString(body, 'email'));
  const verifier = requireB64(body, 'verifier_b64', 64);

  await enforceRateLimit(env, 'login|ip', clientIp(request), 30, 900);
  await enforceRateLimit(env, 'login|em', await sha256Text(email), 15, 900);

  // READ-ONLY browser read — the only account data this worker ever pulls
  // from the primary backend. The guard rejects anything but SELECT.
  const user = await browserFirst(
    env.BROWSER,
    `SELECT id, email, username, kdf_salt, kdf_algo, kdf_iterations, verifier_hash, wrapped_vault_key, vault_nonce
     FROM users WHERE email = ?`,
    email,
  );

  if (!user || !constantTimeEqual(await sha256(verifier), user.verifier_hash)) {
    // Same error for unknown email and wrong verifier (no account enumeration).
    throw new ApiError(401, 'invalid_credentials', 'Invalid email or verifier');
  }

  const { accessToken, refreshToken } = await createSession(env, user.id, body.device);

  // Cache the reused identity fields into the OS-owned profile row; avatar
  // and display name are preserved if the identity already exists.
  await env.OS.prepare(
    `INSERT INTO identities (user_id, email, username, updated_at) VALUES (?, ?, ?, ?)
     ON CONFLICT(user_id) DO UPDATE SET email = excluded.email, username = excluded.username, updated_at = excluded.updated_at`,
  ).bind(user.id, user.email, user.username ?? null, nowSec()).run();

  const identity = await env.OS.prepare('SELECT avatar_url, display_name FROM identities WHERE user_id = ?').bind(user.id).first();

  return json({
    access_token: accessToken,
    refresh_token: refreshToken,
    token_type: 'Bearer',
    expires_in: LIMITS.ACCESS_TOKEN_TTL,
    user: {
      id: user.id,
      email: user.email,
      username: user.username ?? null,
      kdf_salt_b64: bytesToB64(user.kdf_salt),
      kdf: { algo: user.kdf_algo, iterations: user.kdf_iterations },
      wrapped_vault_key_b64: bytesToB64(user.wrapped_vault_key),
      vault_nonce_b64: bytesToB64(user.vault_nonce),
    },
    identity: {
      username: user.username ?? null,
      avatar_url: identity?.avatar_url ?? null,
      display_name: identity?.display_name ?? null,
    },
  });
}

async function handleRefresh(request, env) {
  const body = await readJson(request, LIMITS.MAX_BODY_BYTES);
  const raw = requireString(body, 'refresh_token', 128);
  const tokenHash = await sha256(utf8.encode(raw));

  const session = await env.OS.prepare(
    "SELECT id, user_id, device_id FROM sessions WHERE token_hash = ? AND kind = 'refresh' AND expires_at > ?",
  ).bind(tokenHash, nowSec()).first();

  if (!session) throw new ApiError(401, 'unauthorized', 'Invalid or expired refresh token');

  const now = nowSec();
  const accessToken = randomTokenB64();
  const refreshToken = randomTokenB64();

  // Rotation: the presented refresh token dies, a new pair is born.
  await env.OS.batch([
    env.OS.prepare('DELETE FROM sessions WHERE id = ?').bind(session.id),
    env.OS.prepare("DELETE FROM sessions WHERE user_id = ? AND device_id = ? AND kind = 'access'").bind(session.user_id, session.device_id),
    env.OS.prepare('INSERT INTO sessions (user_id, device_id, kind, token_hash, expires_at, created_at) VALUES (?, ?, ?, ?, ?, ?)')
      .bind(session.user_id, session.device_id, 'access', await sha256(utf8.encode(accessToken)), now + LIMITS.ACCESS_TOKEN_TTL, now),
    env.OS.prepare('INSERT INTO sessions (user_id, device_id, kind, token_hash, expires_at, created_at) VALUES (?, ?, ?, ?, ?, ?)')
      .bind(session.user_id, session.device_id, 'refresh', await sha256(utf8.encode(refreshToken)), now + LIMITS.REFRESH_TOKEN_TTL, now),
    env.OS.prepare('UPDATE devices SET last_seen_at = ? WHERE user_id = ? AND id = ?').bind(now, session.user_id, session.device_id),
  ]);

  return json({ access_token: accessToken, refresh_token: refreshToken, token_type: 'Bearer', expires_in: LIMITS.ACCESS_TOKEN_TTL });
}

async function handleLogout(request, env, auth) {
  await env.OS.prepare('DELETE FROM sessions WHERE user_id = ? AND token_hash = ?').bind(auth.userId, auth.tokenHash).run();
  return json({ ok: true });
}

async function requireAuth(request, env) {
  const header = request.headers.get('Authorization') ?? '';
  const m = /^Bearer\s+(.+)$/.exec(header);
  if (!m) throw new ApiError(401, 'unauthorized', 'Missing Bearer token');
  const tokenHash = await sha256(utf8.encode(m[1]));

  const session = await env.OS.prepare(
    "SELECT user_id, device_id, token_hash FROM sessions WHERE token_hash = ? AND kind = 'access' AND expires_at > ?",
  ).bind(tokenHash, nowSec()).first();

  if (!session) throw new ApiError(401, 'unauthorized', 'Invalid or expired access token');
  return { userId: session.user_id, deviceId: session.device_id, tokenHash: session.token_hash };
}

// ---------- OS-owned identity (avatar / display name) ----------

async function handleGetIdentity(request, env, auth) {
  const row = await env.OS.prepare('SELECT email, username, avatar_url, display_name FROM identities WHERE user_id = ?')
    .bind(auth.userId).first();
  if (!row) {
    // Logged in before the identities table existed; backfill from the
    // browser (read-only) so the profile is never half-empty.
    const user = await browserFirst(env.BROWSER, 'SELECT email, username FROM users WHERE id = ?', auth.userId);
    await env.OS.prepare('INSERT INTO identities (user_id, email, username, updated_at) VALUES (?, ?, ?, ?) ON CONFLICT(user_id) DO NOTHING')
      .bind(auth.userId, user?.email ?? null, user?.username ?? null, nowSec()).run();
    return json({
      user_id: auth.userId,
      email: user?.email ?? null,
      username: user?.username ?? null,
      avatar_url: null,
      display_name: null,
      field_sources: { email: 'browser', username: 'browser', avatar_url: 'os', display_name: 'os' },
    });
  }
  return json({
    user_id: auth.userId,
    email: row.email,
    username: row.username,
    avatar_url: row.avatar_url,
    display_name: row.display_name,
    field_sources: { email: 'browser', username: 'browser', avatar_url: 'os', display_name: 'os' },
  });
}

async function handlePutIdentity(request, env, auth) {
  const body = await readJson(request, LIMITS.MAX_BODY_BYTES);
  const avatar = validateAvatarUrl(body.avatar_url);
  const display = validateDisplayName(body.display_name);

  const row = await env.OS.prepare('SELECT email, username FROM identities WHERE user_id = ?').bind(auth.userId).first();
  let email = row?.email ?? null;
  let username = row?.username ?? null;
  if (!row) {
    const user = await browserFirst(env.BROWSER, 'SELECT email, username FROM users WHERE id = ?', auth.userId);
    email = user?.email ?? null;
    username = user?.username ?? null;
  }

  await env.OS.prepare(
    `INSERT INTO identities (user_id, email, username, avatar_url, display_name, updated_at)
     VALUES (?, ?, ?, ?, ?, ?)
     ON CONFLICT(user_id) DO UPDATE SET
       avatar_url = COALESCE(excluded.avatar_url, identities.avatar_url),
       display_name = COALESCE(excluded.display_name, identities.display_name),
       updated_at = excluded.updated_at`,
  ).bind(auth.userId, email, username, avatar, display, nowSec()).run();

  const updated = await env.OS.prepare('SELECT email, username, avatar_url, display_name FROM identities WHERE user_id = ?')
    .bind(auth.userId).first();
  return json({
    user_id: auth.userId,
    email: updated.email,
    username: updated.username,
    avatar_url: updated.avatar_url,
    display_name: updated.display_name,
    field_sources: { email: 'browser', username: 'browser', avatar_url: 'os', display_name: 'os' },
  });
}

/**
 * GET /v1/os/identity/:username — public identity resolution so any OS
 * surface (Aegis ID card, CoreX UI) renders the SAME username/avatar as the
 * browser side. Returns only public fields; email and ids never leave here.
 */
async function handlePublicIdentity(request, env, url, username) {
  await enforceRateLimit(env, 'identity|ip', clientIp(request), 60, 900);
  const name = normalizeUsername(username);

  const cached = await env.OS.prepare('SELECT avatar_url, display_name FROM identities WHERE username = ? LIMIT 1').bind(name).first();
  if (cached) {
    return json({ username: name, avatar_url: cached.avatar_url, display_name: cached.display_name, source: 'os' });
  }

  // Read-only fallback into the browser users table: the identity exists on
  // the primary backend even if the user has never logged into an OS device.
  const user = await browserFirst(env.BROWSER, 'SELECT username FROM users WHERE username = ? LIMIT 1', name);
  if (user) {
    return json({ username: name, avatar_url: null, display_name: null, source: 'browser' });
  }
  throw new ApiError(404, 'not_found', 'Unknown username');
}

// ---------- OS devices ----------

async function handleListDevices(request, env, auth) {
  const { results } = await env.OS.prepare(
    'SELECT id, name, platform, created_at, last_seen_at FROM devices WHERE user_id = ? ORDER BY last_seen_at DESC',
  ).bind(auth.userId).all();
  return json({
    devices: (results ?? []).map((d) => ({
      id: d.id,
      name: d.name,
      platform: d.platform,
      created_at: d.created_at,
      last_seen_at: d.last_seen_at,
      current: d.id === auth.deviceId,
    })),
  });
}

// ---------- OS sync (os-* item types; OS database only) ----------

function rowToJson(r) {
  return {
    event_id: r.event_id,
    item_type: r.item_type,
    item_key: r.item_key,
    version: r.version,
    ciphertext_b64: r.ciphertext ? bytesToB64(r.ciphertext) : null,
    nonce_b64: r.nonce ? bytesToB64(r.nonce) : null,
    deleted: r.deleted === 1,
    device_id: r.device_id,
    updated_at: r.updated_at,
  };
}

function validatePushItem(raw) {
  if (!raw || typeof raw !== 'object') throw new ApiError(400, 'invalid_request', 'Each item must be an object');
  const it = raw;

  if (typeof it.item_type !== 'string' || !OS_ITEM_TYPES.includes(it.item_type)) {
    throw new ApiError(400, 'invalid_request', `item_type must be one of: ${OS_ITEM_TYPES.join(', ')}`);
  }
  if (typeof it.item_key !== 'string' || it.item_key.length === 0 || it.item_key.length > 64) {
    throw new ApiError(400, 'invalid_request', 'item_key must be a non-empty string (max 64 chars)');
  }
  if (typeof it.base_version !== 'number' || !Number.isInteger(it.base_version) || it.base_version < 0) {
    throw new ApiError(400, 'invalid_request', 'base_version must be a non-negative integer');
  }
  const deleted = it.deleted === true;

  let ciphertext = null;
  let nonce = null;
  if (deleted) {
    if (it.ciphertext_b64 != null || it.nonce_b64 != null) {
      throw new ApiError(400, 'invalid_request', 'Tombstones must not carry ciphertext or nonce');
    }
  } else {
    if (typeof it.ciphertext_b64 !== 'string' || typeof it.nonce_b64 !== 'string') {
      throw new ApiError(400, 'invalid_request', 'Non-deleted items require ciphertext_b64 and nonce_b64');
    }
    let ct;
    let nc;
    try {
      ct = b64ToBytes(it.ciphertext_b64);
      nc = b64ToBytes(it.nonce_b64);
    } catch {
      throw new ApiError(400, 'invalid_request', 'ciphertext_b64/nonce_b64 must be valid base64');
    }
    if (ct.length > LIMITS.MAX_CIPHERTEXT_BYTES) {
      throw new ApiError(413, 'payload_too_large', `Ciphertext exceeds ${LIMITS.MAX_CIPHERTEXT_BYTES} bytes`);
    }
    if (nc.length < 8 || nc.length > 32) throw new ApiError(400, 'invalid_request', 'nonce_b64 must be 8-32 bytes');
    ciphertext = it.ciphertext_b64;
    nonce = it.nonce_b64;
  }

  return { item_type: it.item_type, item_key: it.item_key, base_version: it.base_version, ciphertext_b64: ciphertext, nonce_b64: nonce, deleted };
}

async function handlePush(request, env, auth) {
  const body = await readJson(request, LIMITS.MAX_BODY_BYTES);
  if (!Array.isArray(body.items) || body.items.length === 0) {
    throw new ApiError(400, 'invalid_request', 'Field "items" must be a non-empty array');
  }
  if (body.items.length > LIMITS.MAX_PUSH_ITEMS) {
    throw new ApiError(413, 'payload_too_large', `Max ${LIMITS.MAX_PUSH_ITEMS} items per push`);
  }

  const items = body.items.map(validatePushItem);
  const seen = new Set();
  for (const it of items) {
    const k = `${it.item_type}/${it.item_key}`;
    if (seen.has(k)) throw new ApiError(400, 'invalid_request', `Duplicate item in request: ${k}`);
    seen.add(k);
  }

  // ---- read phase: current server state for these keys ----
  const conditions = items.map(() => '(item_type = ? AND item_key = ?)').join(' OR ');
  const binds = [auth.userId];
  for (const it of items) binds.push(it.item_type, it.item_key);
  const { results: current } = await env.OS.prepare(
    `SELECT item_type, item_key, version, deleted FROM os_items WHERE user_id = ? AND (${conditions})`,
  ).bind(...binds).all();
  const serverMap = new Map();
  for (const r of current ?? []) serverMap.set(`${r.item_type}/${r.item_key}`, { version: r.version, deleted: r.deleted });

  // ---- decide per item (optimistic concurrency on base_version) ----
  const now = nowSec();
  const decisions = [];
  for (const it of items) {
    const key = `${it.item_type}/${it.item_key}`;
    const server = serverMap.get(key);

    if (!server) {
      if (it.base_version !== 0) {
        decisions.push({ kind: 'conflict', item: it });
        continue;
      }
      if (it.deleted) {
        decisions.push({ kind: 'noop', item: it, version: 0 });
        continue;
      }
      decisions.push({
        kind: 'write',
        item: it,
        sql: 'INSERT INTO os_items (user_id, item_type, item_key, version, ciphertext, nonce, deleted, device_id, updated_at) VALUES (?, ?, ?, 1, ?, ?, 0, ?, ?)',
        binds: [auth.userId, it.item_type, it.item_key, b64ToBytes(it.ciphertext_b64), b64ToBytes(it.nonce_b64), auth.deviceId, now],
      });
      continue;
    }

    if (server.version !== it.base_version) {
      decisions.push({ kind: 'conflict', item: it });
      continue;
    }
    if (it.deleted && server.deleted === 1) {
      decisions.push({ kind: 'noop', item: it, version: server.version });
      continue;
    }
    decisions.push({
      kind: 'write',
      item: it,
      sql: `UPDATE os_items SET version = version + 1, ciphertext = ?, nonce = ?, deleted = ?, device_id = ?, updated_at = ?
            WHERE user_id = ? AND item_type = ? AND item_key = ? AND version = ?`,
      binds: [
        it.deleted ? null : b64ToBytes(it.ciphertext_b64),
        it.deleted ? null : b64ToBytes(it.nonce_b64),
        it.deleted ? 1 : 0,
        auth.deviceId,
        now,
        auth.userId,
        it.item_type,
        it.item_key,
        it.base_version,
      ],
    });
  }

  // ---- write phase: single atomic batch ----
  const writes = decisions.filter((d) => d.kind === 'write');
  if (writes.length > 0) {
    const stmts = writes.map((d) => env.OS.prepare(d.sql).bind(...d.binds));
    let results;
    try {
      results = await env.OS.batch(stmts);
    } catch {
      throw new ApiError(409, 'conflict', 'Concurrent modification detected; pull, merge, then retry');
    }
    const racedIdx = [];
    results.forEach((r, i) => {
      if ((r.meta?.changes ?? 0) === 0) racedIdx.push(i);
    });
    if (racedIdx.length > 0) {
      for (let i = decisions.length - 1; i >= 0; i--) {
        const d = decisions[i];
        if (d.kind === 'write' && racedIdx.includes(writes.indexOf(d))) decisions[i] = { kind: 'conflict', item: d.item };
      }
    }
  }

  // ---- response; fetch server copies for conflicts ----
  const conflictKeys = decisions.filter((d) => d.kind === 'conflict').map((d) => d.item);
  const conflictRows = new Map();
  if (conflictKeys.length > 0) {
    const cBinds = [auth.userId];
    const cConds = conflictKeys.map(() => '(item_type = ? AND item_key = ?)').join(' OR ');
    for (const it of conflictKeys) cBinds.push(it.item_type, it.item_key);
    const { results: cRows } = await env.OS.prepare(
      `SELECT event_id, item_type, item_key, version, ciphertext, nonce, deleted, device_id, updated_at
       FROM os_items WHERE user_id = ? AND (${cConds})`,
    ).bind(...cBinds).all();
    for (const r of cRows ?? []) conflictRows.set(`${r.item_type}/${r.item_key}`, r);
  }

  const out = decisions.map((d) => {
    const key = `${d.item.item_type}/${d.item.item_key}`;
    if (d.kind === 'conflict') {
      const row = conflictRows.get(key);
      return {
        item_type: d.item.item_type,
        item_key: d.item.item_key,
        status: 'conflict',
        server_item: row ? rowToJson(row) : null,
      };
    }
    const version = d.kind === 'write' ? (d.item.base_version === 0 ? 1 : d.item.base_version + 1) : d.kind === 'noop' ? d.version : 0;
    return { item_type: d.item.item_type, item_key: d.item.item_key, status: 'ok', version };
  });

  return json({ results: out });
}

async function handlePull(request, env, auth, url) {
  const cursorRaw = url.searchParams.get('cursor') ?? '0';
  const cursor = Number.parseInt(cursorRaw, 10);
  if (!Number.isInteger(cursor) || cursor < 0) throw new ApiError(400, 'invalid_request', 'cursor must be a non-negative integer');

  const typesParam = url.searchParams.get('types');
  let types = null;
  if (typesParam) {
    types = typesParam.split(',').map((t) => t.trim()).filter(Boolean);
    for (const t of types) {
      if (!OS_ITEM_TYPES.includes(t)) throw new ApiError(400, 'invalid_request', `Unknown item type: ${t}`);
    }
    if (types.length === 0) types = null;
  }

  let sql = 'SELECT event_id, item_type, item_key, version, ciphertext, nonce, deleted, device_id, updated_at FROM os_items WHERE user_id = ? AND event_id > ?';
  const binds = [auth.userId, cursor];
  if (types) {
    sql += ` AND item_type IN (${types.map(() => '?').join(',')})`;
    binds.push(...types);
  }
  sql += ' ORDER BY event_id ASC LIMIT ?';
  binds.push(LIMITS.PULL_PAGE_SIZE + 1);

  const { results } = await env.OS.prepare(sql).bind(...binds).all();
  const rows = results ?? [];
  const hasMore = rows.length > LIMITS.PULL_PAGE_SIZE;
  const page = hasMore ? rows.slice(0, LIMITS.PULL_PAGE_SIZE) : rows;
  const nextCursor = page.length > 0 ? page[page.length - 1].event_id : cursor;

  return json({ items: page.map(rowToJson), next_cursor: hasMore ? nextCursor : null, has_more: hasMore });
}

async function handleCursor(request, env, auth) {
  const row = await env.OS.prepare('SELECT COALESCE(MAX(event_id), 0) AS cursor FROM os_items WHERE user_id = ?').bind(auth.userId).first();
  return json({ cursor: row?.cursor ?? 0 });
}

async function handleExport(request, env, auth, url) {
  const cursorRaw = url.searchParams.get('cursor') ?? '0';
  const cursor = Number.parseInt(cursorRaw, 10);
  if (!Number.isInteger(cursor) || cursor < 0) throw new ApiError(400, 'invalid_request', 'cursor must be a non-negative integer');

  const { results } = await env.OS.prepare(
    'SELECT event_id, item_type, item_key, version, ciphertext, nonce, deleted, device_id, updated_at FROM os_items WHERE user_id = ? AND event_id > ? ORDER BY event_id ASC LIMIT ?',
  ).bind(auth.userId, cursor, LIMITS.EXPORT_PAGE_SIZE + 1).all();
  const rows = results ?? [];
  const hasMore = rows.length > LIMITS.EXPORT_PAGE_SIZE;
  const page = hasMore ? rows.slice(0, LIMITS.EXPORT_PAGE_SIZE) : rows;
  return json({ items: page.map(rowToJson), next_cursor: hasMore ? page[page.length - 1].event_id : null });
}

// ---------- OS account deletion (OS rows only; browser account untouched) ----------

async function handleDeleteOsAccount(request, env, auth) {
  await env.OS.batch([
    env.OS.prepare('DELETE FROM os_items WHERE user_id = ?').bind(auth.userId),
    env.OS.prepare('DELETE FROM sessions WHERE user_id = ?').bind(auth.userId),
    env.OS.prepare('DELETE FROM devices WHERE user_id = ?').bind(auth.userId),
    env.OS.prepare('DELETE FROM identities WHERE user_id = ?').bind(auth.userId),
  ]);
  return json({ ok: true, deleted: 'os-data', note: 'The browser account lives in the primary aegis-sync backend and is untouched; delete it there if you want the whole identity gone.' });
}

// ---------- nightly maintenance (OS database only) ----------

async function prune(env) {
  const now = nowSec();
  await env.OS.batch([
    env.OS.prepare('DELETE FROM sessions WHERE expires_at < ?').bind(now),
    env.OS.prepare('DELETE FROM os_items WHERE deleted = 1 AND updated_at < ?').bind(now - 90 * 24 * 3600),
    env.OS.prepare('DELETE FROM rate_limits WHERE window_start < ?').bind(now - 3600),
  ]);
}

// ---------- router ----------

function corsHeaders(env) {
  return {
    'Access-Control-Allow-Origin': env.CORS_ORIGIN || '*',
    'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
    'Access-Control-Allow-Headers': 'Authorization, Content-Type',
    'Access-Control-Max-Age': '86400',
  };
}

export default {
  async fetch(request, env) {
    const cors = corsHeaders(env);
    try {
      if (request.method === 'OPTIONS') {
        return new Response(null, { status: 204, headers: cors });
      }

      const url = new URL(request.url);
      const path = url.pathname.replace(/\/+$/, '') || '/';
      const method = request.method;
      const seg = path.split('/').filter(Boolean); // e.g. ["v1","os","sync","push"]

      if (method === 'GET' && path === '/health') {
        return json({ ok: true, service: 'aegis-sync-os', version: '1.0.0', identity: 'browser-primary' });
      }

      if (seg[0] === 'v1' && seg[1] === 'os' && seg[2] === 'auth') {
        if (method === 'GET' && seg[3] === 'kdf-params') return await handleKdfParams(request, env, url);
        if (method === 'POST' && seg[3] === 'login') return await handleLogin(request, env);
        if (method === 'POST' && seg[3] === 'refresh') return await handleRefresh(request, env);
      }

      // Public identity resolution needs no auth — MUST be matched before
      // the authenticated block below (which would 401 it).
      if (method === 'GET' && seg[0] === 'v1' && seg[1] === 'os' && seg[2] === 'identity' && seg.length === 4) {
        return await handlePublicIdentity(request, env, url, seg[3]);
      }

      if (seg[0] === 'v1' && seg[1] === 'os') {
        const auth = await requireAuth(request, env);

        if (seg[2] === 'auth') {
          if (method === 'POST' && seg[3] === 'logout') return await handleLogout(request, env, auth);
          if (method === 'DELETE' && seg[3] === 'account') return await handleDeleteOsAccount(request, env, auth);
        }
        if (seg[2] === 'identity') {
          if (method === 'GET' && seg.length === 3) return await handleGetIdentity(request, env, auth);
          if (method === 'PUT' && seg.length === 3) return await handlePutIdentity(request, env, auth);
        }
        if (seg[2] === 'devices' && method === 'GET' && seg.length === 3) {
          return await handleListDevices(request, env, auth);
        }
        if (seg[2] === 'sync') {
          if (method === 'GET' && seg[3] === 'cursor') return await handleCursor(request, env, auth);
          if (method === 'GET' && seg[3] === 'pull') return await handlePull(request, env, auth, url);
          if (method === 'POST' && seg[3] === 'push') return await handlePush(request, env, auth);
          if (method === 'GET' && seg[3] === 'export') return await handleExport(request, env, auth, url);
        }
        if (method === 'DELETE' && seg[2] === 'account' && seg.length === 3) {
          return await handleDeleteOsAccount(request, env, auth);
        }
      }

      return json({ error: { code: 'not_found', message: `No route for ${method} ${path}` } }, 404, cors);
    } catch (e) {
      return errResponse(e, cors);
    }
  },

  async scheduled(_event, env) {
    await prune(env);
  },
};
