import { errResponse, json } from '../../lib/json.js';
import { requireSession } from '../../lib/session.js';

/** GET /api/passkeys — list the signed-in user's passkeys. */
export async function onRequestGet({ request, env }) {
  try {
    const session = await requireSession(env, request);
    const rows = await env.IDDB.prepare(
      'SELECT id, device, created_at, last_used_at FROM passkeys WHERE user_id = ? OR email = ? ORDER BY created_at DESC',
    )
      .bind(session.user_id, session.email)
      .all();
    return json({ passkeys: rows.results ?? [] });
  } catch (e) {
    return errResponse(e);
  }
}

/** DELETE /api/passkeys?id=<credential id> — remove one passkey. */
export async function onRequestDelete({ request, env }) {
  try {
    const session = await requireSession(env, request);
    const id = new URL(request.url).searchParams.get('id') ?? '';
    const res = await env.IDDB.prepare('DELETE FROM passkeys WHERE id = ? AND (user_id = ? OR email = ?)')
      .bind(id, session.user_id, session.email)
      .run();
    if ((res.meta?.changes ?? 0) === 0) {
      return json({ error: { code: 'not_found', message: 'No such passkey' } }, 404);
    }
    return json({ ok: true });
  } catch (e) {
    return errResponse(e);
  }
}
