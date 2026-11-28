import { errResponse, json, readJson } from '../../lib/json.js';
import { requireSession } from '../../lib/session.js';
import { osIdentity, osPutIdentity, withBackend } from '../../lib/backends.js';
import { ApiError } from '../../lib/json.js';

/**
 * PUT /api/account/profile — updates the OS-OWNED identity fields
 * (avatar_url, display_name) on aegis-sync-os. Username and email are
 * browser-owned and intentionally not editable here.
 */
export async function onRequestPut({ request, env }) {
  try {
    const session = await requireSession(env, request);
    if (!session.os_refresh) throw new ApiError(409, 'no_sync_session', 'Sign in with the password once to manage the OS profile.');
    const body = await readJson(request);

    const payload = {};
    if ('avatar_url' in body) payload.avatar_url = body.avatar_url;
    if ('display_name' in body) payload.display_name = body.display_name;

    const updated = await withBackend(env, session, 'os', (token) => osPutIdentity(env, token, payload));
    return json({ ok: true, identity: { username: updated.username, avatar_url: updated.avatar_url, display_name: updated.display_name } });
  } catch (e) {
    return errResponse(e);
  }
}

/** GET /api/account/profile — full identity + public-profile check. */
export async function onRequestGet({ request, env }) {
  try {
    const session = await requireSession(env, request);
    let identity = null;
    if (session.os_refresh) {
      identity = await withBackend(env, session, 'os', (token) => osIdentity(env, token)).catch(() => null);
    }
    let public_profile = null;
    if (identity?.username) {
      public_profile = await fetch(`${(env.OS_API ?? 'https://aegis-sync-os.abdulmateen14.workers.dev').replace(/\/+$/, '')}/v1/os/identity/${encodeURIComponent(identity.username)}`)
        .then((r) => (r.ok ? r.json() : null))
        .catch(() => null);
    }
    return json({ identity, public_profile });
  } catch (e) {
    return errResponse(e);
  }
}
