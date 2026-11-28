import { errResponse, json, normalizeEmail, readJson, requireString } from '../../lib/json.js';
import { createSession } from '../../lib/session.js';
import { loginOs, loginPrimary } from '../../lib/backends.js';
import { saveLinkedTokens } from '../../lib/google.js';

/**
 * POST /api/auth/register — creates the account on the PRIMARY backend
 * (aegis-sync) with client-side-derived credentials, then signs the portal
 * in on both backends. The password never reaches the portal: the client
 * sends only kdf_salt_b64 / verifier_b64 / wrapped_vault_key_b64.
 */
export async function onRequestPost({ request, env }) {
  try {
    const body = await readJson(request);
    const email = normalizeEmail(requireString(body, 'email'));
    const verifier = requireString(body, 'verifier_b64', 128);
    const salt = requireString(body, 'kdf_salt_b64', 128);
    const wrapped = requireString(body, 'wrapped_vault_key_b64', 192);
    const nonce = requireString(body, 'vault_nonce_b64', 128);
    const username = typeof body.username === 'string' && body.username.trim() !== '' ? body.username.trim().toLowerCase() : undefined;
    const kdf = body.kdf;
    if (!kdf || typeof kdf !== 'object' || kdf.algo !== 'PBKDF2-SHA256' || typeof kdf.iterations !== 'number' || kdf.iterations < 100000 || kdf.iterations > 2000000) {
      return json({ error: { code: 'invalid_request', message: 'Field "kdf" must carry {algo:"PBKDF2-SHA256", iterations:100000..2000000}' } }, 400);
    }

    // Account creation happens ONLY on the primary backend (public API).
    const reg = await fetch(`${(env.PRIMARY_API ?? 'https://aegis-sync.abdulmateen14.workers.dev').replace(/\/+$/, '')}/v1/auth/register`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, ...(username ? { username } : {}), kdf_salt_b64: salt, verifier_b64: verifier, wrapped_vault_key_b64: wrapped, vault_nonce_b64: nonce, kdf }),
    });
    const regData = await reg.json().catch(() => ({}));
    if (!reg.ok) {
      return json({ error: regData.error ?? { code: `http_${reg.status}`, message: 'Registration failed' } }, reg.status);
    }
    const userId = regData.user_id;

    // Sign the portal in on both backends (mint refresh tokens for the web device).
    const primary = await loginPrimary(env, verifier, email);
    let os = null;
    try {
      os = await loginOs(env, verifier, email);
    } catch {
      /* non-fatal: OS login retries on next password login */
    }

    const { token, setCookie } = await createSession(env, {
      userId,
      email,
      primaryRefresh: primary.refresh_token,
      osRefresh: os?.refresh_token ?? null,
      request,
    });
    await saveLinkedTokens(env, userId, email, primary.refresh_token, os?.refresh_token ?? null);

    return json(
      { ok: true, user: { user_id: userId, email, username: primary.user?.username ?? username ?? null } },
      200,
      { 'Set-Cookie': setCookie },
    );
  } catch (e) {
    return errResponse(e);
  }
}
