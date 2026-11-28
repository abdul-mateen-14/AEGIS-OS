import { json } from '../../../lib/json.js';
import { createSession } from '../../../lib/session.js';
import { linkOrGetGoogleIdentity, mintTokensForGoogle } from '../../../lib/google.js';

/**
 * GET /api/auth/google/callback — exchanges the authorization code, decodes
 * the id_token (obtained over TLS by this confidential client), and either
 * creates the account on the primary backend (server-managed vault) or links
 * Google to the existing password account with the same email.
 */
export async function onRequestGet({ request, env }) {
  const origin = (env.APP_ORIGIN ?? new URL(request.url).origin).replace(/\/+$/, '');
  const fail = (msg) => Response.redirect(`${origin}/#error=${encodeURIComponent(msg)}`, 302);

  try {
    if (!env.GOOGLE_CLIENT_ID || !env.GOOGLE_CLIENT_SECRET) return fail('Google sign-in is not configured');
    const url = new URL(request.url);
    const code = url.searchParams.get('code');
    const state = url.searchParams.get('state');
    if (!code || !state) return fail('Missing code/state');

    // CSRF: consume the one-time state.
    const row = await env.IDDB.prepare('SELECT state FROM oauth_state WHERE state = ?').bind(state).first();
    if (!row) return fail('Unknown OAuth state');
    await env.IDDB.prepare('DELETE FROM oauth_state WHERE state = ?').bind(state).run();

    const tokenRes = await fetch('https://oauth2.googleapis.com/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        code,
        client_id: env.GOOGLE_CLIENT_ID,
        client_secret: env.GOOGLE_CLIENT_SECRET,
        redirect_uri: `${origin}/api/auth/google/callback`,
        grant_type: 'authorization_code',
      }),
    });
    const tokenData = await tokenRes.json().catch(() => ({}));
    if (!tokenData.id_token) return fail('Google token exchange failed');

    // id_token payload (JWT part 2). Obtained via a confidential code exchange
    // from Google over TLS; aud/iss checked below.
    const [, payloadB64] = tokenData.id_token.split('.');
    const claims = JSON.parse(atob(payloadB64.replaceAll('-', '+').replaceAll('_', '/')));
    if (claims.aud !== env.GOOGLE_CLIENT_ID || claims.iss !== 'https://accounts.google.com') return fail('Bad id_token claims');
    const email = String(claims.email ?? '').toLowerCase();
    if (!email || !claims.email_verified) return fail('Google account has no verified email');

    const { userId, hasVerifier } = await linkOrGetGoogleIdentity(env, claims.sub, email);

    const { token, setCookie } = await createSession(env, { userId, email, primaryRefresh: null, osRefresh: null, request });
    if (hasVerifier) {
      await mintTokensForGoogle(env, token, userId, email);
    }

    return Response.redirect(`${origin}/#dashboard${hasVerifier ? '' : '&link=1'}`, 302);
  } catch (e) {
    console.error('google callback:', e);
    return fail('Google sign-in failed');
  }
}
