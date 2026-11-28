// Google identity handling: link-or-create an account for a Google login.
//
// Account truth stays in the PRIMARY backend. Google accounts are created
// there through its public register API with a SERVER-GENERATED credential
// (this module holds it in google_identities). Honest trade-off, documented
// in docs/IDENTITY-PORTAL.md: Google accounts are server-managed vaults —
// the server holds their verifier — while password accounts stay zero-
// knowledge (the verifier only exists on the user's devices).

import { ApiError } from './json.js';
import { loginOs, loginPrimary, registerOnPrimary, persistRefresh } from './backends.js';

const GOOGLE_WRAP_INFO = 'aegis-google-wrap-v1';

function randomB64(n) {
  const b = new Uint8Array(n);
  crypto.getRandomValues(b);
  return btoa(String.fromCharCode(...b));
}

function bytesFromB64(b64) {
  return Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
}

/** Wraps the vault key under a KEK derived from the server-held verifier. */
async function wrapWithVerifier(verifierB64, vaultKeyB64) {
  const raw = await crypto.subtle.importKey('raw', bytesFromB64(verifierB64), 'HKDF', false, ['deriveBits']);
  const kek = await crypto.subtle.deriveBits(
    { name: 'HKDF', hash: 'SHA-256', salt: new Uint8Array(0), info: new TextEncoder().encode(GOOGLE_WRAP_INFO) },
    raw,
    256,
  );
  const nonce = crypto.getRandomValues(new Uint8Array(12));
  const key = await crypto.subtle.importKey('raw', kek, 'AES-GCM', false, ['encrypt']);
  const wrapped = await crypto.subtle.encrypt({ name: 'AES-GCM', iv: nonce, tagLength: 128 }, key, bytesFromB64(vaultKeyB64));
  return {
    wrapped_b64: btoa(String.fromCharCode(...new Uint8Array(wrapped))),
    nonce_b64: btoa(String.fromCharCode(...nonce)),
  };
}

function generateServerCredential() {
  return { verifierB64: randomB64(32), saltB64: randomB64(16), vaultKeyB64: randomB64(32) };
}

/**
 * Link-or-load a Google identity by google_sub.
 *   1. known google_sub            → return it
 *   2. email free on the primary   → CREATE the account there (server credential)
 *   3. email already a password account → LINK only (no verifier held; the
 *      portal session stays portal-only until the user signs in with the
 *      password once, which fills linked_tokens)
 */
export async function linkOrGetGoogleIdentity(env, googleSub, email) {
  const known = await env.IDDB.prepare('SELECT user_id, verifier_b64 FROM google_identities WHERE google_sub = ?').bind(googleSub).first();
  if (known) return { userId: known.user_id, isNew: false, hasVerifier: !!known.verifier_b64 };

  const cred = generateServerCredential();
  const { wrapped_b64, nonce_b64 } = await wrapWithVerifier(cred.verifierB64, cred.vaultKeyB64);
  const now = Math.floor(Date.now() / 1000);

  let userId;
  let isNew = false;
  let hasVerifier = true;
  try {
    const reg = await registerOnPrimary(env, {
      email,
      kdf_salt_b64: cred.saltB64,
      verifier_b64: cred.verifierB64,
      wrapped_vault_key_b64: wrapped_b64,
      vault_nonce_b64: nonce_b64,
      kdf: { algo: 'PBKDF2-SHA256', iterations: 600000 },
    });
    userId = reg.user_id;
    isNew = true;
  } catch (e) {
    if (e instanceof ApiError && (e.code === 'email_taken' || e.status === 409)) {
      // The email belongs to an existing password account — link, don't duplicate.
      userId = `google:${googleSub}`;
      hasVerifier = false;
    } else {
      throw e;
    }
  }

  await env.IDDB.prepare(
    'INSERT INTO google_identities (user_id, google_sub, email, verifier_b64, vault_key_b64, created_at) VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT(google_sub) DO UPDATE SET email = excluded.email',
  )
    .bind(userId, googleSub, email, hasVerifier ? cred.verifierB64 : '', hasVerifier ? cred.vaultKeyB64 : '', now)
    .run();

  return { userId, isNew, hasVerifier };
}

/**
 * Mints portal refresh tokens (primary + OS) for accounts whose verifier the
 * portal legitimately holds (server-managed Google accounts). Returns false
 * for link-only Google sessions — they upgrade after a password sign-in.
 */
export async function mintTokensForGoogle(env, sessionId, userId, email) {
  const row = await env.IDDB.prepare('SELECT verifier_b64 FROM google_identities WHERE user_id = ?').bind(userId).first();
  if (!row?.verifier_b64) return false;
  const primary = await loginPrimary(env, row.verifier_b64, email);
  let os = null;
  try {
    os = await loginOs(env, row.verifier_b64, email);
  } catch {
    /* OS backend hiccup must not block the portal login */
  }
  await persistRefresh(env, sessionId, 'primary_refresh', primary.refresh_token);
  if (os) await persistRefresh(env, sessionId, 'os_refresh', os.refresh_token);
  await env.IDDB.prepare(
    'INSERT INTO linked_tokens (user_id, email, primary_refresh, os_refresh, updated_at) VALUES (?, ?, ?, ?, ?) ON CONFLICT(user_id) DO UPDATE SET primary_refresh = excluded.primary_refresh, os_refresh = COALESCE(excluded.os_refresh, linked_tokens.os_refresh), updated_at = excluded.updated_at',
  )
    .bind(userId, email, primary.refresh_token, os?.refresh_token ?? null, Math.floor(Date.now() / 1000))
    .run();
  return true;
}

/**
 * Password sign-in/register paths persist their refresh tokens per user, so
 * a later passkey login (which has NO verifier) can still mint sessions.
 */
export async function saveLinkedTokens(env, userId, email, primaryRefresh, osRefresh) {
  await env.IDDB.prepare(
    'INSERT INTO linked_tokens (user_id, email, primary_refresh, os_refresh, updated_at) VALUES (?, ?, ?, ?, ?) ON CONFLICT(user_id) DO UPDATE SET email = excluded.email, primary_refresh = excluded.primary_refresh, os_refresh = COALESCE(excluded.os_refresh, linked_tokens.os_refresh), updated_at = excluded.updated_at',
  )
    .bind(userId, email, primaryRefresh, osRefresh ?? null, Math.floor(Date.now() / 1000))
    .run();
}

export { bytesFromB64 };
