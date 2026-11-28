#!/usr/bin/env node
// Live smoke for the Aegis ID portal at https://aegis-id.pages.dev
// Env: CLOUDFLARE_ACCOUNT_ID, CLOUDFLARE_API_TOKEN, BROWSER_DB_ID
import { randomBytes } from 'node:crypto';
import { deriveCredentials, generateVaultKey, wrapVaultKey, bytesToB64 } from '../public/lib/aegis-crypto.mjs';

const BASE = 'https://aegis-id.pages.dev';
const CF = 'https://api.cloudflare.com/client/v4';
const ACC = process.env.CLOUDFLARE_ACCOUNT_ID;
const TOK = process.env.CLOUDFLARE_API_TOKEN;
const BDB = process.env.BROWSER_DB_ID;

let pass = 0, fail = 0;
const check = (name, cond, extra = '') => { (cond ? pass++ : fail++, console.log(`  ${cond ? 'PASS' : 'FAIL'} ${name}${cond ? '' : ' ' + extra}`)); };

async function d1(sql) {
  const r = await fetch(`${CF}/accounts/${ACC}/d1/database/${BDB}/query`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${TOK}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ sql }),
  }).then((x) => x.json());
  return r.result?.[0]?.results ?? null;
}
const counts = () => d1('SELECT (SELECT COUNT(*) FROM users) AS users, (SELECT COUNT(*) FROM sync_items) AS sync_items, (SELECT COUNT(*) FROM sessions) AS sessions, (SELECT COUNT(*) FROM devices) AS devices');
const baseline = (await counts())[0];
console.log('browser DB baseline:', JSON.stringify(baseline));

// tiny cookie jar
let cookie = null;
async function call(method, path, body) {
  const res = await fetch(BASE + path, {
    method,
    headers: { 'Content-Type': 'application/json', ...(cookie ? { Cookie: cookie } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body),
    redirect: 'manual',
  });
  const setCookie = res.headers.get('set-cookie');
  if (setCookie) cookie = setCookie.split(';')[0];
  let data = null;
  try { data = await res.json(); } catch {}
  return { status: res.status, data, location: res.headers.get('location') };
}

const ts = Date.now().toString(36).slice(-8);
const email = `portal-smoke-${ts}@aegis.test`;
const username = `psmoke${ts.replace(/[^a-z0-9]/g, '0')}`;
const password = `smoke-pw-${randomBytes(8).toString('hex')}`;

// ---------- 1. static + unauthenticated ----------
console.log('\n[1] static + unauthenticated');
const page = await fetch(BASE + '/');
check('portal HTML served', page.status === 200 && (await page.text()).includes('One ID.'));
let r = await call('GET', '/api/auth/google-status');
check('google-status: not configured (503-ready UI)', r.status === 200 && r.data.configured === false);
r = await call('GET', '/api/auth/me');
check('me without session → 401', r.status === 401);
r = await call('GET', '/api/auth/google/start');
check('google-start → 503 not configured', r.status === 503 && r.data?.error?.code === 'google_not_configured');
r = await call('POST', '/api/auth/passkey/start', { email: null });
check('passkey/start returns options', r.status === 200 && !!r.data.options?.challenge && !!r.data.challenge_id);

// ---------- 2. register through the portal ----------
console.log('\n[2] register via portal');
const saltB64 = randomBytes(16).toString('base64');
const { verifier, kek } = await deriveCredentials(password, saltB64, { algo: 'PBKDF2-SHA256', iterations: 600000 });
const vaultKey = randomBytes(32);
const { wrapped, nonce } = await wrapVaultKey(vaultKey, kek);
r = await call('POST', '/api/auth/register', {
  email, username,
  kdf_salt_b64: saltB64,
  verifier_b64: bytesToB64(verifier),
  wrapped_vault_key_b64: bytesToB64(wrapped),
  vault_nonce_b64: bytesToB64(nonce),
  kdf: { algo: 'PBKDF2-SHA256', iterations: 600000 },
});
check('register ok + cookie', r.status === 200 && r.data.ok === true && !!cookie, JSON.stringify(r.data));
const userId = r.data?.user?.user_id;
r = await call('GET', '/api/auth/me');
check('me: profile assembled', r.status === 200 && r.data.email === email && r.data.username === username && r.data.sync_linked === true, JSON.stringify(r.data));
check('me: field sources documented', r.data.field_sources?.avatar_url === 'os' && r.data.field_sources?.email === 'browser');

// ---------- 3. profile + connections ----------
console.log('\n[3] profile + connections');
r = await call('PUT', '/api/account/profile', { display_name: 'Portal Smoke', avatar_url: 'https://id.aegis.test/p.png' });
check('PUT profile', r.status === 200 && r.data.identity?.display_name === 'Portal Smoke', JSON.stringify(r.data));
r = await call('PUT', '/api/account/profile', { avatar_url: 'http://insecure/x.png' });
check('http avatar rejected', r.status >= 400);
r = await call('GET', '/api/account/connections');
check('connections: portal + browser + OS devices', r.status === 200 && (r.data.portal?.length ?? 0) >= 1 && (r.data.browser?.length ?? 0) >= 1 && (r.data.os?.length ?? 0) >= 1, JSON.stringify(r.data).slice(0, 160));
check('connections: portal-web device visible', (r.data.browser ?? []).some((d) => d.id === 'aegis-id-portal-web') && (r.data.os ?? []).some((d) => d.id === 'aegis-id-portal-web'));

// ---------- 4. change password ----------
console.log('\n[4] change password');
const newPassword = `new-${password}`;
const newSaltB64 = randomBytes(16).toString('base64');
const oldCred = await deriveCredentials(password, saltB64, { algo: 'PBKDF2-SHA256', iterations: 600000 });
const newCred = await deriveCredentials(newPassword, newSaltB64, { algo: 'PBKDF2-SHA256', iterations: 600000 });
// unwrap the SAME vault key and re-wrap under the new credentials
const login = await call('POST', '/api/auth/login', { email, verifier_b64: bytesToB64(oldCred.verifier) });
const { unwrapVaultKey } = await import('../public/lib/aegis-crypto.mjs');
const unwrappedKey = await unwrapVaultKey(Buffer.from(login.data.user.wrapped_vault_key_b64, 'base64'), login.data.user.vault_nonce_b64, oldCred.kek);
const rewrapped = await wrapVaultKey(unwrappedKey, newCred.kek);
r = await call('POST', '/api/account/password', {
  old_verifier_b64: bytesToB64(oldCred.verifier),
  new_verifier_b64: bytesToB64(newCred.verifier),
  kdf_salt_b64: newSaltB64,
  kdf: { algo: 'PBKDF2-SHA256', iterations: 600000 },
  wrapped_vault_key_b64: bytesToB64(rewrapped.wrapped),
  vault_nonce_b64: bytesToB64(rewrapped.nonce),
});
check('change password ok', r.status === 200 && r.data.ok === true, JSON.stringify(r.data));

// old verifier must now fail on the PRIMARY backend; new one must work
const oldCheck = await fetch('https://aegis-sync.abdulmateen14.workers.dev/v1/auth/login', {
  method: 'POST', headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ email, verifier_b64: bytesToB64(oldCred.verifier), device: { id: 'sm', name: 'sm', platform: 'other' } }),
});
check('old verifier rejected on primary (401)', oldCheck.status === 401);
const newCheck = await fetch('https://aegis-sync.abdulmateen14.workers.dev/v1/auth/login', {
  method: 'POST', headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ email, verifier_b64: bytesToB64(newCred.verifier), device: { id: 'sm', name: 'sm', platform: 'other' } }),
});
const newLogin = await newCheck.json();
check('new verifier works on primary + vault key preserved', newCheck.status === 200 && Buffer.from(newLogin.user.wrapped_vault_key_b64, 'base64').equals(Buffer.from(bytesToB64(rewrapped.wrapped), 'base64')));

// ---------- 5. negative paths ----------
console.log('\n[5] negatives');
r = await call('POST', '/api/auth/login', { email, verifier_b64: randomBytes(32).toString('base64') });
check('wrong verifier → 401 same message', r.status === 401 && r.data.error?.code === 'invalid_credentials');
r = await call('POST', '/api/auth/register', { email: `bad-${ts}@aegis.test`, username: username, kdf_salt_b64: saltB64, verifier_b64: 'x'.repeat(64), wrapped_vault_key_b64: 'y'.repeat(64), vault_nonce_b64: 'z'.repeat(64), kdf: { algo: 'PBKDF2-SHA256', iterations: 600000 } });
check('garbage verifier rejected by backend', r.status >= 400);

// ---------- 6. cleanup + isolation ----------
console.log('\n[6] cleanup + isolation proof');
cookie = null; // fresh browser: delete requires the verifier
await call('POST', '/api/auth/login', { email, verifier_b64: bytesToB64(newCred.verifier) });
r = await call('DELETE', '/api/account', { verifier_b64: bytesToB64(newCred.verifier) });
check('account deleted via portal', r.status === 200 && r.data.ok === true, JSON.stringify(r.data));
const gone = await d1(`SELECT COUNT(*) AS n FROM users WHERE email = '${email}'`);
check('primary backend user row gone', gone[0].n === 0);
const after = (await counts())[0];
console.log('browser DB after:', JSON.stringify(after));
check('browser DB identical to baseline', after.users === baseline.users && after.sync_items === baseline.sync_items && after.sessions === baseline.sessions && after.devices === baseline.devices);

console.log(`\nRESULT: ${pass} pass, ${fail} fail`);
process.exit(fail === 0 ? 0 : 1);
