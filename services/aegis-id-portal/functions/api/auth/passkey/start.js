import { errResponse, json, normalizeEmail, readJson } from '../../../lib/json.js';
import { generateAuthenticationOptions } from '@simplewebauthn/server';
import { b64urlEncode } from '../../../lib/session.js';

/**
 * POST /api/auth/passkey/start — sign-in options. With a known email the
 * challenge is scoped to that user's credentials; without, the browser offers
 * its discoverable credentials (usernameless flow).
 */
export async function onRequestPost({ request, env }) {
  try {
    const body = await readJson(request);
    const email = body.email ? normalizeEmail(body.email) : null;
    const rpID = env.RP_ID ?? 'aegis-id.pages.dev';

    let allow = [];
    if (email) {
      const rows = await env.IDDB.prepare('SELECT id, transports FROM passkeys WHERE email = ?').bind(email).all();
      allow = (rows.results ?? []).map((r) => ({ id: r.id, transports: r.transports ? JSON.parse(r.transports) : undefined }));
    }
    const options = await generateAuthenticationOptions({
      rpID,
      userVerification: 'preferred',
      allowCredentials: allow,
    });

    const challengeId = randomToken();
    await env.IDDB.prepare(
      'INSERT INTO webauthn_challenges (id, email, kind, challenge, created_at) VALUES (?, ?, ?, ?, ?)',
    )
      .bind(challengeId, email, 'login', options.challenge, Math.floor(Date.now() / 1000))
      .run();

    return json({ options, challenge_id: challengeId });
  } catch (e) {
    return errResponse(e);
  }
}

function randomToken() {
  const b = new Uint8Array(16);
  crypto.getRandomValues(b);
  return b64urlEncode(b);
}
