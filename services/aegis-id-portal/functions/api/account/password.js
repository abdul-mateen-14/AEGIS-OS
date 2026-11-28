import { errResponse, json, readJson, requireString } from '../../lib/json.js';
import { requireSession } from '../../lib/session.js';
import { persistRefresh, refreshPrimary } from '../../lib/backends.js';
import { ApiError } from '../../lib/json.js';

const CHANGE_URL = (env) => `${(env.PRIMARY_API ?? 'https://aegis-sync.abdulmateen14.workers.dev').replace(/\/+$/, '')}/v1/auth/change-password`;

/**
 * POST /api/account/password — rotates the account credential on the PRIMARY
 * backend. The client derives old + new verifiers locally (password never
 * leaves the device). Other devices are force-logged-out by the backend;
 * the portal's stored refresh token dies too, so we mint a fresh pair.
 */
export async function onRequestPost({ request, env }) {
  try {
    const session = await requireSession(env, request);
    if (!session.primary_refresh) throw new ApiError(409, 'no_sync_session', 'Sign in with the password once before changing it.');
    const body = await readJson(request);
    const oldVerifier = requireString(body, 'old_verifier_b64', 128);
    const newVerifier = requireString(body, 'new_verifier_b64', 128);
    const salt = requireString(body, 'kdf_salt_b64', 128);
    const wrapped = requireString(body, 'wrapped_vault_key_b64', 192);
    const nonce = requireString(body, 'vault_nonce_b64', 128);
    const kdf = body.kdf;
    if (!kdf || typeof kdf !== 'object' || kdf.algo !== 'PBKDF2-SHA256' || typeof kdf.iterations !== 'number' || kdf.iterations < 100000 || kdf.iterations > 2000000) {
      throw new ApiError(400, 'invalid_request', 'Field "kdf" must carry {algo:"PBKDF2-SHA256", iterations:100000..2000000}');
    }

    let access = null;
    try {
      access = await refreshPrimary(env, session.primary_refresh).then((d) => d.access_token);
    } catch {
      throw new ApiError(409, 'session_expired', 'Portal session credentials expired — sign in again.');
    }

    const res = await fetch(CHANGE_URL(env), {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${access}` },
      body: JSON.stringify({
        old_verifier_b64: oldVerifier,
        new_verifier_b64: newVerifier,
        kdf_salt_b64: salt,
        kdf,
        wrapped_vault_key_b64: wrapped,
        vault_nonce_b64: nonce,
      }),
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) {
      return json({ error: data.error ?? { code: `http_${res.status}`, message: 'Change failed' } }, res.status);
    }

    // The backend killed all other refresh sessions incl. ours; re-login with
    // the NEW verifier to restore the portal's linked tokens.
    const email = session.email;
    const login = await fetch(`${(env.PRIMARY_API ?? 'https://aegis-sync.abdulmateen14.workers.dev').replace(/\/+$/, '')}/v1/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, verifier_b64: newVerifier, device: { id: 'aegis-id-portal-web', name: 'Aegis ID (web)', platform: 'other' } }),
    }).then((r) => r.json());

    await persistRefresh(env, session.id, 'primary_refresh', login.refresh_token ?? null);
    return json({ ok: true, note: 'Other devices must sign in again with the new password.' });
  } catch (e) {
    return errResponse(e);
  }
}

