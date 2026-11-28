import { errResponse, json } from '../../lib/json.js';
import { requireSession } from '../../lib/session.js';
import { generateRegistrationOptions } from '@simplewebauthn/server';

/**
 * POST /api/passkeys/register/start — WebAuthn registration options for the
 * signed-in user (passkeys attach to the REAL primary user_id).
 */
export async function onRequestPost({ request, env }) {
  try {
    const session = await requireSession(env, request);
    if (String(session.user_id).startsWith('google:')) {
      return json({ error: { code: 'linked_only', message: 'Sign in with the account password once to enable passkeys.' } }, 409);
    }
    const rpID = env.RP_ID ?? 'aegis-id.pages.dev';

    const existing = await env.IDDB.prepare('SELECT id, transports FROM passkeys WHERE user_id = ?').bind(session.user_id).all();
    const options = await generateRegistrationOptions({
      rpName: 'Aegis ID',
      rpID,
      userID: new TextEncoder().encode(session.user_id),
      userName: session.email,
      attestationType: 'none',
      excludeCredentials: (existing.results ?? []).map((r) => ({ id: r.id, transports: r.transports ? JSON.parse(r.transports) : undefined })),
      authenticatorSelection: { residentKey: 'preferred', userVerification: 'preferred' },
    });

    const challengeId = randomToken();
    await env.IDDB.prepare(
      "INSERT INTO webauthn_challenges (id, user_id, kind, challenge, created_at) VALUES (?, ?, 'register', ?, ?)",
    )
      .bind(challengeId, session.user_id, options.challenge, Math.floor(Date.now() / 1000))
      .run();

    return json({ options, challenge_id: challengeId });
  } catch (e) {
    return errResponse(e);
  }
}

function randomToken() {
  const b = new Uint8Array(16);
  crypto.getRandomValues(b);
  let bin = '';
  for (const x of b) bin += String.fromCharCode(x);
  return btoa(bin).replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/, '');
}
