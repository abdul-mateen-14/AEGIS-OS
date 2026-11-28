import { json } from '../../lib/json.js';

/**
 * GET /api/auth/google-status — the UI asks whether Google sign-in is live.
 * GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET are project secrets the account
 * owner sets after registering the OAuth client (see docs/IDENTITY-PORTAL.md).
 */
export async function onRequestGet({ env }) {
  const configured = !!(env.GOOGLE_CLIENT_ID && env.GOOGLE_CLIENT_SECRET);
  return json({
    configured,
    redirect_uri: configured ? `${(env.APP_ORIGIN ?? 'https://aegis-id.pages.dev').replace(/\/+$/, '')}/api/auth/google/callback` : null,
  });
}
