import { ApiError, errResponse, json, readJson } from '../../lib/json.js';
import { requireSession } from '../../lib/session.js';
import { verifyRegistrationResponse } from '@simplewebauthn/server';

/** POST /api/passkeys/register/finish — verify + store the credential. */
export async function onRequestPost({ request, env }) {
  try {
    const session = await requireSession(env, request);
    const body = await readJson(request);
    const challengeId = typeof body.challenge_id === 'string' ? body.challenge_id : '';
    if (!challengeId) throw new ApiError(400, 'invalid_request', 'Field "challenge_id" is required');
    if (!body.response || typeof body.response !== 'object') throw new ApiError(400, 'invalid_request', 'Field "response" is required');

    const rpID = env.RP_ID ?? 'aegis-id.pages.dev';
    const origin = (env.APP_ORIGIN ?? 'https://aegis-id.pages.dev').replace(/\/+$/, '');

    const row = await env.IDDB.prepare(
      "SELECT * FROM webauthn_challenges WHERE id = ? AND user_id = ? AND kind = 'register' AND created_at > ?",
    )
      .bind(challengeId, session.user_id, Math.floor(Date.now() / 1000) - 300)
      .first();
    if (!row) throw new ApiError(400, 'invalid_request', 'Challenge expired or unknown');
    await env.IDDB.prepare('DELETE FROM webauthn_challenges WHERE id = ?').bind(challengeId).run();

    const verification = await verifyRegistrationResponse({
      response: body.response,
      expectedChallenge: row.challenge,
      expectedOrigin: origin,
      expectedRPID: rpID,
      requireUserVerification: false,
    });
    if (!verification.verified || !verification.registrationInfo) {
      throw new ApiError(400, 'invalid_request', 'Passkey registration failed');
    }

    const { credential } = verification.registrationInfo;
    await env.IDDB.prepare(
      `INSERT INTO passkeys (id, user_id, email, public_key, counter, transports, device, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT(id) DO UPDATE SET public_key = excluded.public_key, counter = excluded.counter`,
    )
      .bind(
        credential.id,
        session.user_id,
        session.email,
        btoa(String.fromCharCode(...new Uint8Array(credential.publicKey))),
        credential.counter,
        JSON.stringify(credential.transports ?? []),
        body.response.clientExtensionResults?.credProtect ? 'protected' : null,
        Math.floor(Date.now() / 1000),
      )
      .run();

    return json({ ok: true, credential_id: credential.id });
  } catch (e) {
    return errResponse(e);
  }
}
