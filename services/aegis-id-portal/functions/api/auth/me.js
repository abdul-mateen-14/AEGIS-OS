import { errResponse, json } from '../../lib/json.js';
import { requireSession } from '../../lib/session.js';
import { osIdentity, withBackend } from '../../lib/backends.js';

/**
 * GET /api/auth/me — the signed-in identity, assembled from the sources of
 * truth: email/username (primary backend, read-only), avatar/display_name
 * (OS backend, OS-owned fields), plus portal-specific flags.
 */
export async function onRequestGet({ request, env }) {
  try {
    const session = await requireSession(env, request);
    const linkedOnly = String(session.user_id).startsWith('google:');

    let identity = null;
    if (session.os_refresh) {
      try {
        identity = await withBackend(env, session, 'os', (token) => osIdentity(env, token));
      } catch {
        /* fall through to a minimal profile */
      }
    }

    const google = await env.IDDB.prepare('SELECT google_sub, verifier_b64 FROM google_identities WHERE google_sub IS NOT NULL AND (user_id = ? OR email = ?)')
      .bind(session.user_id, session.email)
      .first();
    const passkeys = await env.IDDB.prepare('SELECT COUNT(*) AS n FROM passkeys WHERE user_id = ?').bind(session.user_id).first();
    const portalSessions = await env.IDDB.prepare('SELECT COUNT(*) AS n FROM portal_sessions WHERE user_id = ? OR email = ?')
      .bind(session.user_id, session.email)
      .first();

    return json({
      user_id: session.user_id,
      email: session.email,
      username: identity?.username ?? null,
      avatar_url: identity?.avatar_url ?? null,
      display_name: identity?.display_name ?? null,
      field_sources: identity?.field_sources ?? { email: 'browser', username: 'browser', avatar_url: 'os', display_name: 'os' },
      google_linked: !!google,
      google_managed: !!(google && google.verifier_b64), // server-managed vault
      has_password: !linkedOnly && !(google && google.verifier_b64),
      linked_only: linkedOnly,
      passkey_count: passkeys?.n ?? 0,
      portal_sessions: portalSessions?.n ?? 1,
      sync_linked: !!(session.primary_refresh),
    });
  } catch (e) {
    return errResponse(e);
  }
}
