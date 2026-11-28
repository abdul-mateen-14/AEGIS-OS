// Portal session helpers: HttpOnly cookie sessions stored (hashed) in the
// aegis-id D1 database. Access tokens for the sync backends are minted on
// demand from the stored refresh tokens — raw sync tokens for the CURRENT
// request only, never in the cookie.

import { ApiError } from './json.js';

export const SESSION_COOKIE = 'aegsid';
export const SESSION_TTL = 14 * 24 * 3600; // 14 days

export function b64urlEncode(bytes) {
  let bin = '';
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/, '');
}

export async function sha256Hex(text) {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

export function randomToken() {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return b64urlEncode(bytes);
}

export function sessionCookie(token, maxAgeSec) {
  return `${SESSION_COOKIE}=${token}; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=${maxAgeSec}`;
}

function nowSec() {
  return Math.floor(Date.now() / 1000);
}

/** Creates a portal session row and returns the Set-Cookie header pair. */
export async function createSession(env, { userId, email, primaryRefresh, osRefresh, request }) {
  const token = randomToken();
  const now = nowSec();
  const meta = await env.IDDB.prepare(
    `INSERT INTO portal_sessions (token_hash, user_id, email, primary_refresh, os_refresh, created_at, last_seen_at, expires_at, user_agent, ip)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
  )
    .bind(
      await sha256Hex(token),
      userId,
      email,
      primaryRefresh ?? null,
      osRefresh ?? null,
      now,
      now,
      now + SESSION_TTL,
      request.headers.get('User-Agent') ?? null,
      request.headers.get('CF-Connecting-IP') ?? null,
    )
    .run();
  return { token, setCookie: sessionCookie(token, SESSION_TTL), sessionId: meta.meta?.last_row_id ?? null };
}

/** Resolves the current portal session, or null. Does NOT check sync-token validity. */
export async function getSession(env, request) {
  const cookie = request.headers.get('Cookie') ?? '';
  const m = new RegExp(`(?:^|;\\s*)${SESSION_COOKIE}=([A-Za-z0-9_-]+)`).exec(cookie);
  if (!m) return null;
  const row = await env.IDDB.prepare(
    'SELECT * FROM portal_sessions WHERE token_hash = ? AND expires_at > ?',
  )
    .bind(await sha256Hex(m[1]), nowSec())
    .first();
  if (!row) return null;
  await env.IDDB.prepare('UPDATE portal_sessions SET last_seen_at = ? WHERE id = ?').bind(nowSec(), row.id).run();
  return row;
}

/** Same, but throws 401 — for endpoints that require a session. */
export async function requireSession(env, request) {
  const session = await getSession(env, request);
  if (!session) throw new ApiError(401, 'unauthorized', 'Sign in first');
  return session;
}

export function destroyCookie() {
  return `${SESSION_COOKIE}=; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=0`;
}
