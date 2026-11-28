// Client of the two sync backends. The portal NEVER touches their databases
// directly — it talks to their public APIs like any other Aegis client:
//   primary (aegis-sync)  — accounts, browser sessions/devices (browser-owned)
//   OS      (aegis-sync-os) — OS identity fields (avatar/display) + os devices
// For Google accounts the portal mints sessions server-side using the
// server-held verifier stored in the google_identities table.

import { ApiError } from './json.js';

export function primaryApi(env) {
  return (env.PRIMARY_API ?? 'https://aegis-sync.abdulmateen14.workers.dev').replace(/\/+$/, '');
}
export function osApi(env) {
  return (env.OS_API ?? 'https://aegis-sync-os.abdulmateen14.workers.dev').replace(/\/+$/, '');
}

const PORTAL_DEVICE = { id: 'aegis-id-portal-web', name: 'Aegis ID (web)', platform: 'other' };

async function call(url, { method = 'GET', body, token } = {}) {
  let res;
  try {
    res = await fetch(url, {
      method,
      headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
  } catch {
    throw new ApiError(502, 'backend_unreachable', 'A sync backend is unreachable');
  }
  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    const code = data?.error?.code ?? `http_${res.status}`;
    // Surface backend validation errors to the portal client untouched.
    throw new ApiError(res.status, code, data?.error?.message ?? 'Backend rejected the request');
  }
  return data;
}

export const registerOnPrimary = (env, body) => call(`${primaryApi(env)}/v1/auth/register`, { method: 'POST', body });
export const loginPrimary = (env, verifierB64, email) =>
  call(`${primaryApi(env)}/v1/auth/login`, { method: 'POST', body: { email, verifier_b64: verifierB64, device: PORTAL_DEVICE } });
export const loginOs = (env, verifierB64, email) =>
  call(`${osApi(env)}/v1/os/auth/login`, { method: 'POST', body: { email, verifier_b64: verifierB64, device: PORTAL_DEVICE } });
export const refreshPrimary = (env, refreshToken) =>
  call(`${primaryApi(env)}/v1/auth/refresh`, { method: 'POST', body: { refresh_token: refreshToken } });
export const refreshOs = (env, refreshToken) =>
  call(`${osApi(env)}/v1/os/auth/refresh`, { method: 'POST', body: { refresh_token: refreshToken } });
export const deleteOnPrimary = (env, verifierB64, token) =>
  call(`${primaryApi(env)}/v1/auth/account`, { method: 'DELETE', body: { verifier_b64: verifierB64 }, token });
export const deleteOnOs = (env, token) => call(`${osApi(env)}/v1/os/account`, { method: 'DELETE', token });
export const osIdentity = (env, token) => call(`${osApi(env)}/v1/os/identity`, { token });
export const osPutIdentity = (env, token, body) => call(`${osApi(env)}/v1/os/identity`, { method: 'PUT', token, body });
export const osPublicIdentity = (env, username) => call(`${osApi(env)}/v1/os/identity/${encodeURIComponent(username)}`);
export const primaryKdfParams = (env, email) => call(`${primaryApi(env)}/v1/auth/kdf-params?email=${encodeURIComponent(email)}`);

/** Mints a fresh access token for one backend from its stored refresh token. */
async function accessToken(env, refresh, kind) {
  if (!refresh) throw new ApiError(401, 'unauthorized', 'No stored credential for this backend');
  const data = kind === 'os' ? await refreshOs(env, refresh) : await refreshPrimary(env, refresh);
  return data.access_token;
}

/**
 * Runs `fn(token)` against a backend. Every refresh ROTATES (both backends
 * delete the presented refresh token), so each rotation's new refresh token
 * is persisted BEFORE it is used — on the happy path and the 401 retry alike.
 */
export async function withBackend(env, sessionRow, kind, fn) {
  const refreshCol = kind === 'os' ? 'os_refresh' : 'primary_refresh';
  if (!sessionRow[refreshCol]) {
    throw new ApiError(409, 'no_sync_session', 'Sign in with the password once to connect this backend.');
  }
  const rotate = async () => {
    const fresh = kind === 'os' ? await refreshOs(env, sessionRow[refreshCol]) : await refreshPrimary(env, sessionRow[refreshCol]);
    sessionRow[refreshCol] = fresh.refresh_token; // in-memory, for consecutive calls on the same row
    if (sessionRow.id) await persistRefresh(env, sessionRow.id, refreshCol, fresh.refresh_token);
    return fresh.access_token;
  };
  let token = await rotate();
  try {
    return await fn(token);
  } catch (e) {
    if (e instanceof ApiError && e.status === 401) {
      token = await rotate();
      return fn(token);
    }
    throw e;
  }
}

export async function persistRefresh(env, sessionId, col, value) {
  await env.IDDB.prepare(`UPDATE portal_sessions SET ${col} = ? WHERE id = ?`).bind(value, sessionId).run();
}

export { PORTAL_DEVICE };
