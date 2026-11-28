import { errResponse, json, normalizeEmail } from '../../lib/json.js';
import { primaryKdfParams } from '../../lib/backends.js';

/**
 * GET /api/auth/kdf-params?email= — proxied to the primary backend so the
 * portal UI can derive verifiers locally with the account's real KDF params.
 * Unknown emails get a fake salt from the backend (no account enumeration).
 */
export async function onRequestGet({ request, env }) {
  try {
    const email = normalizeEmail(new URL(request.url).searchParams.get('email') ?? '');
    const data = await primaryKdfParams(env, email);
    return json(data);
  } catch (e) {
    return errResponse(e);
  }
}
