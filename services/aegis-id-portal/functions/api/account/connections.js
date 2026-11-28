import { errResponse, json } from '../../lib/json.js';
import { requireSession } from '../../lib/session.js';
import { primaryApi, osApi, withBackend } from '../../lib/backends.js';

/**
 * GET /api/account/connections — every place this identity is connected:
 *   browser devices  (primary aegis-sync /v1/devices)
 *   OS devices       (aegis-sync-os /v1/os/devices)
 *   portal sessions  (this D1)
 */
export async function onRequestGet({ request, env }) {
  try {
    const session = await requireSession(env, request);

    const out = { browser: [], os: [], portal: [], linked: !!session.primary_refresh };

    if (session.primary_refresh) {
      try {
        const data = await withBackend(env, session, 'primary', (token) =>
          fetch(`${primaryApi(env)}/v1/devices`, { headers: { Authorization: `Bearer ${token}` } }).then((r) => r.json()),
        );
        out.browser = data.devices ?? [];
      } catch {
        out.browser_error = 'Could not reach the browser backend';
      }
    }
    if (session.os_refresh) {
      try {
        const data = await withBackend(env, session, 'os', (token) =>
          fetch(`${osApi(env)}/v1/os/devices`, { headers: { Authorization: `Bearer ${token}` } }).then((r) => r.json()),
        );
        out.os = data.devices ?? [];
      } catch {
        out.os_error = 'Could not reach the OS backend';
      }
    }
    const rows = await env.IDDB.prepare(
      'SELECT id, created_at, last_seen_at, expires_at, user_agent FROM portal_sessions WHERE user_id = ? OR email = ? ORDER BY last_seen_at DESC',
    )
      .bind(session.user_id, session.email)
      .all();
    out.portal = (rows.results ?? []).map((r) => ({ ...r, current: r.id === session.id }));

    return json(out);
  } catch (e) {
    return errResponse(e);
  }
}
