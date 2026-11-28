import { json } from '../../lib/json.js';
import { destroyCookie, getSession } from '../../lib/session.js';

/** POST /api/auth/logout — kills THIS portal session only. */
export async function onRequestPost({ request, env }) {
  const session = await getSession(env, request);
  if (session) {
    await env.IDDB.prepare('DELETE FROM portal_sessions WHERE id = ?').bind(session.id).run();
  }
  return json({ ok: true }, 200, { 'Set-Cookie': destroyCookie() });
}
