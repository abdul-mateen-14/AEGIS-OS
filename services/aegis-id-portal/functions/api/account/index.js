import { ApiError, errResponse, json, readJson } from '../../lib/json.js';
import { destroyCookie, requireSession } from '../../lib/session.js';
import { deleteOnOs, deleteOnPrimary, withBackend } from '../../lib/backends.js';


/**
 * DELETE /api/account — deletes the WHOLE identity:
 *   primary backend account (browser + everything, via its delete endpoint,
 *   which requires the verifier) + OS data (aegis-sync-os) + portal rows.
 * For Google-managed accounts the portal holds the verifier; password
 * accounts must send it (derived client-side).
 */
export async function onRequestDelete({ request, env }) {
  try {
    const session = await requireSession(env, request);
    const linkedOnly = String(session.user_id).startsWith('google:');
    const realUserId = linkedOnly ? null : session.user_id;

    // Resolve the verifier: client-supplied for password accounts, held for Google.
    let verifier = null;
    if (realUserId) {
      const g = await env.IDDB.prepare('SELECT verifier_b64 FROM google_identities WHERE user_id = ?').bind(realUserId).first();
      if (g?.verifier_b64) {
        verifier = g.verifier_b64;
      } else {
        const body = await readJson(request).catch(() => ({}));
        verifier = typeof body.verifier_b64 === 'string' && body.verifier_b64 ? body.verifier_b64 : null;
        if (!verifier) throw new ApiError(403, 'verifier_required', 'Confirm with your account password to delete.');
      }
    }

    // Hydrate the session from linked_tokens if this session lacks them.
    for (const col of ['primary_refresh', 'os_refresh']) {
      if (!session[col]) {
        const lt = await env.IDDB.prepare(`SELECT ${col} AS t FROM linked_tokens WHERE user_id = ?`).bind(session.user_id).first();
        if (lt?.t) session[col] = lt.t;
      }
    }

    if (realUserId && verifier) {
      // withBackend mints an ACCESS token from the stored refresh (rotating
      // it) — a raw refresh token as Bearer would be rejected by the backend.
      await withBackend(env, session, 'primary', (token) => deleteOnPrimary(env, verifier, token));
    }
    if (realUserId && session.os_refresh) {
      await withBackend(env, session, 'os', (token) => deleteOnOs(env, token)).catch(() => {});
    }

    // Portal rows: sessions, passkeys, google links, linked tokens.
    await env.IDDB.batch([
      env.IDDB.prepare('DELETE FROM portal_sessions WHERE user_id = ? OR email = ?').bind(realUserId ?? session.user_id, session.email),
      env.IDDB.prepare('DELETE FROM passkeys WHERE user_id = ? OR email = ?').bind(realUserId ?? session.user_id, session.email),
      env.IDDB.prepare('DELETE FROM google_identities WHERE user_id = ? OR google_sub IS NOT NULL AND email = ?').bind(realUserId ?? session.user_id, session.email),
      env.IDDB.prepare('DELETE FROM linked_tokens WHERE user_id = ? OR email = ?').bind(realUserId ?? session.user_id, session.email),
    ]);

    return json({ ok: true }, 200, { 'Set-Cookie': destroyCookie() });
  } catch (e) {
    return errResponse(e);
  }
}

