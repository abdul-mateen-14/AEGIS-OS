import { errResponse, json, normalizeEmail, readJson, requireString } from '../../lib/json.js';
import { createSession } from '../../lib/session.js';
import { loginOs, loginPrimary } from '../../lib/backends.js';
import { saveLinkedTokens } from '../../lib/google.js';
import { ApiError } from '../../lib/json.js';

/**
 * POST /api/auth/login — verifier sign-in (same protocol as the browser and
 * OS clients). The verifier is derived client-side from the password; the
 * portal holds only refresh tokens afterward.
 */
export async function onRequestPost({ request, env }) {
  try {
    const body = await readJson(request);
    const email = normalizeEmail(requireString(body, 'email'));
    const verifier = requireString(body, 'verifier_b64', 128);

    const primary = await loginPrimary(env, verifier, email);
    const userId = primary.user.id;
    let os = null;
    try {
      os = await loginOs(env, verifier, email);
    } catch {
      /* non-fatal */
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
      {
        ok: true,
        user: {
          user_id: userId,
          email: primary.user.email,
          username: primary.user.username ?? null,
          avatar_url: os?.identity?.avatar_url ?? null,
          display_name: os?.identity?.display_name ?? null,
          // vault material passthrough (primary login returns it; the portal
          // UI needs it to unwrap + re-wrap the vault key on password change)
          kdf_salt_b64: primary.user.kdf_salt_b64 ?? null,
          wrapped_vault_key_b64: primary.user.wrapped_vault_key_b64 ?? null,
          vault_nonce_b64: primary.user.vault_nonce_b64 ?? null,
        },
      },
      200,
      { 'Set-Cookie': setCookie },
    );
  } catch (e) {
    if (e instanceof ApiError && e.status === 401) {
      // Same message as the backends: no account enumeration.
      return json({ error: { code: 'invalid_credentials', message: 'Invalid email or password' } }, 401);
    }
    return errResponse(e);
  }
}
