import { ApiError, errResponse, json, readJson } from '../../../lib/json.js';
import { createSession } from '../../../lib/session.js';
import { verifyAuthenticationResponse } from '@simplewebauthn/server';
import { mintTokensForGoogle } from '../../../lib/google.js';

/**
 * POST /api/auth/passkey/finish — verifies the assertion and signs in.
 *   Google accounts  → server-held verifier mints sync sessions
 *   password accounts → linked_tokens (refresh tokens persisted at their
 *                       last password sign-in) mint sync sessions
 */
export async function onRequestPost({ request, env }) {
  try {
    const body = await readJson(request);
    const challengeId = requireField(body, 'challenge_id');
    const assertion = body.response;
    if (!assertion || typeof assertion !== 'object') throw new ApiError(400, 'invalid_request', 'Field "response" is required');
    const rpID = env.RP_ID ?? 'aegis-id.pages.dev';
    const origin = (env.APP_ORIGIN ?? 'https://aegis-id.pages.dev').replace(/\/+$/, '');

    const row = await env.IDDB.prepare(
      "SELECT * FROM webauthn_challenges WHERE id = ? AND kind = 'login' AND created_at > ?",
    )
      .bind(challengeId, Math.floor(Date.now() / 1000) - 300)
      .first();
    if (!row) throw new ApiError(400, 'invalid_request', 'Challenge expired or unknown');
    await env.IDDB.prepare('DELETE FROM webauthn_challenges WHERE id = ?').bind(challengeId).run();

    const cred = await env.IDDB.prepare('SELECT * FROM passkeys WHERE id = ?').bind(assertion.id).first();
    if (!cred) throw new ApiError(401, 'unauthorized', 'Unknown passkey');
    if (row.email && cred.email !== row.email) throw new ApiError(401, 'unauthorized', 'Passkey does not belong to this account');

    const verification = await verifyAuthenticationResponse({
      response: assertion,
      expectedChallenge: row.challenge,
      expectedOrigin: origin,
      expectedRPID: rpID,
      credential: {
        id: cred.id,
        publicKey: Uint8Array.from(atob(cred.public_key), (c) => c.charCodeAt(0)),
        counter: cred.counter,
        transports: cred.transports ? JSON.parse(cred.transports) : undefined,
      },
      requireUserVerification: false,
    });
    if (!verification.verified) throw new ApiError(401, 'unauthorized', 'Passkey verification failed');

    await env.IDDB.prepare('UPDATE passkeys SET counter = ?, last_used_at = ? WHERE id = ?')
      .bind(verification.authenticationInfo.newCounter, Math.floor(Date.now() / 1000), cred.id)
      .run();

    const email = cred.email;
    const userId = cred.user_id;

    const { token, setCookie, sessionId } = await createSession(env, { userId, email, primaryRefresh: null, osRefresh: null, request });

    // Mint sync sessions for the real account behind this passkey:
    //   Google-managed accounts → the held verifier mints both backends;
    //   password accounts → refresh tokens persisted at their last password sign-in.
    let synced = false;
    const googleRow = await env.IDDB.prepare('SELECT verifier_b64 FROM google_identities WHERE user_id = ?').bind(userId).first();
    if (googleRow?.verifier_b64) {
      synced = await mintTokensForGoogle(env, token, userId, email).catch(() => false);
    } else {
      const linked = await env.IDDB.prepare('SELECT primary_refresh, os_refresh FROM linked_tokens WHERE user_id = ?').bind(userId).first();
      if (linked) {
        synced = true;
        await env.IDDB.prepare('UPDATE portal_sessions SET primary_refresh = ?, os_refresh = ? WHERE id = ?')
          .bind(linked.primary_refresh, linked.os_refresh, sessionId)
          .run();
      }
    }

    return json({ ok: true, sync_linked: synced }, 200, { 'Set-Cookie': setCookie });
  } catch (e) {
    return errResponse(e);
  }
}

function requireField(obj, field) {
  const v = obj[field];
  if (typeof v !== 'string' || v.length === 0) throw new ApiError(400, 'invalid_request', `Field "${field}" is required`);
  return v;
}
