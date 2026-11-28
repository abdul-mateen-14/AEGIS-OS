import { json } from '../../../lib/json.js';
import { randomToken } from '../../../lib/session.js';

/**
 * GET /api/auth/google/start — begins the Google OAuth flow (authorization
 * code, confidential client). Requires GOOGLE_CLIENT_ID/SECRET project
 * secrets; the redirect URI registered in Google Cloud Console must be
 * https://<APP_ORIGIN>/api/auth/google/callback
 */
export async function onRequestGet({ request, env }) {
  if (!env.GOOGLE_CLIENT_ID || !env.GOOGLE_CLIENT_SECRET) {
    return json({ error: { code: 'google_not_configured', message: 'Google sign-in is not configured on this deployment yet.' } }, 503);
  }
  const origin = (env.APP_ORIGIN ?? new URL(request.url).origin).replace(/\/+$/, '');
  const state = randomToken();
  await env.IDDB.prepare('INSERT INTO oauth_state (state, created_at) VALUES (?, ?)').bind(state, Math.floor(Date.now() / 1000)).run();

  const authUrl = new URL('https://accounts.google.com/o/oauth2/v2/auth');
  authUrl.searchParams.set('client_id', env.GOOGLE_CLIENT_ID);
  authUrl.searchParams.set('redirect_uri', `${origin}/api/auth/google/callback`);
  authUrl.searchParams.set('response_type', 'code');
  authUrl.searchParams.set('scope', 'openid email profile');
  authUrl.searchParams.set('state', state);
  authUrl.searchParams.set('prompt', 'select_account');

  return Response.redirect(authUrl.toString(), 302);
}
