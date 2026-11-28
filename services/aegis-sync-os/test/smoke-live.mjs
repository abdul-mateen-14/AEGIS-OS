#!/usr/bin/env node
// Smoke test for aegis-sync-os against the LIVE deployment.
// Ends with the isolation proof: browser DB row counts must equal the baseline.
// Env: CLOUDFLARE_ACCOUNT_ID, CLOUDFLARE_API_TOKEN, OS_DB_ID, BROWSER_DB_ID
import { randomBytes } from 'node:crypto';

const OS = 'https://aegis-sync-os.abdulmateen14.workers.dev';
const BROWSER = 'https://aegis-sync.abdulmateen14.workers.dev';
const CF = 'https://api.cloudflare.com/client/v4';
const ACC = process.env.CLOUDFLARE_ACCOUNT_ID;
const TOK = process.env.CLOUDFLARE_API_TOKEN;
const OSDB = process.env.OS_DB_ID;
const BDB = process.env.BROWSER_DB_ID;

let pass = 0, fail = 0;
function check(name, cond, extra = '') {
  if (cond) { pass++; console.log(`  PASS ${name}`); }
  else { fail++; console.log(`  FAIL ${name} ${extra}`); }
}
async function api(sql, db) {
  const r = await fetch(`${CF}/accounts/${ACC}/d1/database/${db}/query`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${TOK}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ sql }),
  }).then((x) => x.json());
  return r.result?.[0]?.results ?? null;
}
async function j(method, url, body, token) {
  const r = await fetch(url, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  let data = null;
  try { data = await r.json(); } catch {}
  return { status: r.status, data };
}
const b64 = (n) => randomBytes(n).toString('base64');

// ---------- baseline ----------
const counts = () => api(
  'SELECT (SELECT COUNT(*) FROM users) AS users, (SELECT COUNT(*) FROM sync_items) AS sync_items, (SELECT COUNT(*) FROM sessions) AS sessions, (SELECT COUNT(*) FROM devices) AS devices',
  BDB,
);
const baseline = (await counts())[0];
console.log('browser DB baseline:', JSON.stringify(baseline));

const ts = Date.now().toString(36).slice(-8);
const email = `smoke-os-${ts}@aegis.test`;
const username = `ossmoke${ts.replace(/[^a-z0-9]/g, '0')}`;
const verifier = b64(32);
const account = { email, username, kdf_salt_b64: b64(16), verifier_b64: verifier, wrapped_vault_key_b64: b64(48), vault_nonce_b64: b64(12), kdf: { algo: 'PBKDF2-SHA256', iterations: 600000 } };
const device = { id: `smoke-dev-${ts}`, name: 'Smoke Runner', platform: 'linux' };

// ---------- 1. health + kdf-params ----------
console.log('\n[1] health + kdf-params');
let r = await j('GET', `${OS}/health`);
check('OS /health', r.status === 200 && r.data.service === 'aegis-sync-os' && r.data.identity === 'browser-primary', JSON.stringify(r.data));
r = await j('GET', `${OS}/v1/os/auth/kdf-params?email=unknown-${ts}@aegis.test`);
check('kdf-params fake-salt shape', r.status === 200 && !!r.data.kdf_salt_b64 && r.data.kdf.iterations === 600000);

// ---------- 2. register on the BROWSER backend (primary) ----------
console.log('\n[2] register on browser backend');
r = await j('POST', `${BROWSER}/v1/auth/register`, account);
check('browser register 201', r.status === 201 && !!r.data.user_id, JSON.stringify(r.data));
const userId = r.data.user_id;

// ---------- 3. OS login (same verifier) + negative cases ----------
console.log('\n[3] OS login');
r = await j('POST', `${OS}/v1/os/auth/login`, { email, verifier_b64: verifier, device });
check('OS login 200', r.status === 200 && r.data.access_token?.startsWith('aeg_'), JSON.stringify(r.data));
check('login returns reused identity fields', r.data.user?.email === email && r.data.user?.username === username && r.data.user?.id === userId);
check('login returns wrapped vault key (same E2E keys)', !!r.data.user?.wrapped_vault_key_b64);
let access = r.data.access_token;
let refresh = r.data.refresh_token;

r = await j('POST', `${OS}/v1/os/auth/login`, { email, verifier_b64: b64(32), device });
check('wrong verifier → 401 invalid_credentials', r.status === 401 && r.data.error?.code === 'invalid_credentials');
r = await j('POST', `${OS}/v1/os/auth/login`, { email: `nobody-${ts}@aegis.test`, verifier_b64: verifier, device });
check('unknown email → same 401 message (no enumeration)', r.status === 401 && r.data.error?.code === 'invalid_credentials');

// ---------- 4. identity: OS-owned fields + public resolution ----------
console.log('\n[4] identity');
r = await j('PUT', `${OS}/v1/os/identity`, { avatar_url: 'https://id.aegis.test/avatar.png', display_name: 'OS Smoke' }, access);
check('PUT identity', r.status === 200 && r.data.avatar_url === 'https://id.aegis.test/avatar.png' && r.data.display_name === 'OS Smoke', JSON.stringify(r.data));
check('field_sources: email/username=browser, avatar/display=os', JSON.stringify(r.data.field_sources) === JSON.stringify({ email: 'browser', username: 'browser', avatar_url: 'os', display_name: 'os' }));
r = await j('PUT', `${OS}/v1/os/identity`, { avatar_url: 'http://insecure/x.png' }, access);
check('http avatar rejected 400', r.status === 400);
r = await j('GET', `${OS}/v1/os/identity`, undefined, access);
check('GET own identity', r.status === 200 && r.data.username === username && r.data.email === email);
r = await j('GET', `${OS}/v1/os/identity/${username}`);
check('public identity by username (os source)', r.status === 200 && r.data.avatar_url?.includes('avatar.png') && r.data.source === 'os', JSON.stringify(r.data));
r = await j('GET', `${OS}/v1/os/identity/nosuchuser123`);
check('unknown public identity → 404', r.status === 404);

// ---------- 5. OS sync roundtrip + conflicts + tombstones ----------
console.log('\n[5] os sync');
const item = (key, v, deleted = false) => ({
  item_type: 'os-setting', item_key: key, base_version: v,
  ...(deleted ? {} : { ciphertext_b64: b64(64), nonce_b64: b64(12) }), deleted,
});
r = await j('POST', `${OS}/v1/os/sync/push`, { items: [item('dock.prefs', 0), { item_type: 'os-notes', item_key: 'note1', base_version: 0, ciphertext_b64: b64(32), nonce_b64: b64(12), deleted: false }] }, access);
check('push 2 new items ok', r.status === 200 && r.data.results?.every((x) => x.status === 'ok' && x.version === 1), JSON.stringify(r.data));
r = await j('POST', `${OS}/v1/os/sync/push`, { items: [item('dock.prefs', 1)] }, access);
check('re-push v1 → v2', r.status === 200 && r.data.results?.[0]?.version === 2);
r = await j('POST', `${OS}/v1/os/sync/push`, { items: [item('dock.prefs', 0)] }, access);
check('stale base_version → conflict + server_item', r.status === 200 && r.data.results?.[0]?.status === 'conflict' && r.data.results?.[0]?.server_item?.version === 2);
r = await j('POST', `${OS}/v1/os/sync/push`, { items: [{ item_type: 'bookmark', item_key: 'x', base_version: 0, ciphertext_b64: b64(8), nonce_b64: b64(12), deleted: false }] }, access);
check('browser item_type rejected on OS backend', r.status === 400);
r = await j('GET', `${OS}/v1/os/sync/pull?cursor=0`, undefined, access);
check('pull returns 2 items', r.status === 200 && r.data.items?.length === 2);
r = await j('GET', `${OS}/v1/os/sync/pull?types=os-notes`, undefined, access);
check('pull types filter', r.data.items?.length === 1 && r.data.items[0].item_type === 'os-notes');
r = await j('GET', `${OS}/v1/os/sync/cursor`, undefined, access);
check('cursor >= 2', (r.data.cursor ?? 0) >= 2);
r = await j('POST', `${OS}/v1/os/sync/push`, { items: [{ item_type: 'os-notes', item_key: 'note1', base_version: 1, deleted: true }] }, access);
check('tombstone push ok', r.status === 200 && r.data.results?.[0]?.status === 'ok');
r = await j('GET', `${OS}/v1/os/sync/export`, undefined, access);
check('export includes tombstone', r.status === 200 && r.data.items?.some((x) => x.deleted === true && x.item_key === 'note1'));

// ---------- 6. refresh rotation + devices ----------
console.log('\n[6] sessions');
r = await j('POST', `${OS}/v1/os/auth/refresh`, { refresh_token: refresh });
check('refresh rotates', r.status === 200 && r.data.access_token?.startsWith('aeg_'));
const newAccess = r.data.access_token;
r = await j('GET', `${OS}/v1/os/identity`, undefined, access);
check('old access token dead after rotation', r.status === 401);
r = await j('GET', `${OS}/v1/os/identity`, undefined, newAccess);
check('new access token works', r.status === 200);
r = await j('GET', `${OS}/v1/os/devices`, undefined, newAccess);
check('devices list, current flag', r.status === 200 && r.data.devices?.some((d) => d.current === true && d.platform === 'linux'));

// ---------- 7. OS account wipe + browser account removal ----------
console.log('\n[7] cleanup');
r = await j('DELETE', `${OS}/v1/os/account`, undefined, newAccess);
check('OS account wipe', r.status === 200 && r.data.deleted === 'os-data');
r = await j('GET', `${OS}/v1/os/identity/${username}`);
check('OS cache gone, browser fallback remains', r.status === 200 && r.data.source === 'browser' && r.data.avatar_url === null, JSON.stringify(r.data));
r = await j('POST', `${BROWSER}/v1/auth/login`, { email, verifier_b64: verifier, device });
check('browser login with same verifier works', r.status === 200);
const bAccess = r.data.access_token;
r = await j('DELETE', `${BROWSER}/v1/auth/account`, { verifier_b64: verifier }, bAccess);
check('browser account deleted', r.status === 200 && r.data.deleted === true);

// ---------- 8. isolation proof ----------
console.log('\n[8] isolation proof');
const after = (await counts())[0];
console.log('browser DB after:', JSON.stringify(after));
check('browser DB counts identical to baseline (users/sync_items/sessions/devices)',
  after.users === baseline.users && after.sync_items === baseline.sync_items && after.sessions === baseline.sessions && after.devices === baseline.devices,
  `${JSON.stringify(baseline)} → ${JSON.stringify(after)}`);

console.log(`\nRESULT: ${pass} pass, ${fail} fail`);
process.exit(fail === 0 ? 0 : 1);
