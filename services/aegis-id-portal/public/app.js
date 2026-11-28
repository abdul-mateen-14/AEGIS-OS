// Aegis ID portal — front-of-house logic.
// Crypto: the vendored aegis-crypto.mjs (same file the browser client uses),
// so register / sign-in / change-password payloads are byte-compatible with
// every other Aegis client. The password NEVER leaves this device.

import {
  DEFAULT_KDF,
  b64ToBytes,
  bytesToB64,
  deriveCredentials,
  generateVaultKey,
  unwrapVaultKey,
  wrapVaultKey,
} from './lib/aegis-crypto.mjs';

const $ = (id) => document.getElementById(id);
const show = (el) => el.classList.remove('hidden');
const hide = (el) => el.classList.add('hidden');

const api = (path, opts = {}) =>
  fetch(path, {
    method: opts.method ?? (opts.body ? 'POST' : 'GET'),
    headers: { 'Content-Type': 'application/json' },
    credentials: 'same-origin',
    body: opts.body ? JSON.stringify(opts.body) : undefined,
  }).then(async (r) => {
    const data = await r.json().catch(() => ({}));
    if (!r.ok) throw Object.assign(new Error(data?.error?.message ?? `HTTP ${r.status}`), { code: data?.error?.code, status: r.status });
    return data;
  });

function authError(msg) { $('auth-error').textContent = msg; show($('auth-error')); }
function authStatus(msg) { $('auth-status').textContent = msg; show($('auth-status')); }
const clearAuthMsgs = () => { hide($('auth-error')); hide($('auth-status')); };

function avatarStyle(url, letter) {
  const el = $('avatar');
  el.textContent = letter ?? '?';
  el.style.backgroundImage = url ? `url("${url.replace(/"/g, '%22')}")` : 'none';
}

/* ── view switching ─────────────────────────────── */

function showAuth() { show($('view-auth')); hide($('view-dash')); }
function showDash() { hide($('view-auth')); show($('view-dash')); refreshMe(); }

/* ── boot ───────────────────────────────────────── */

(async function boot() {
  const [me, gs] = await Promise.all([
    api('/api/auth/me').catch(() => null),
    api('/api/auth/google-status').catch(() => ({ configured: false })),
  ]);
  if (me && !me.error) {
    showDash();
  } else {
    showAuth();
  }
  if (gs.configured) show($('google-btn'));
  else show($('google-note'));
})();

/* ── tabs ───────────────────────────────────────── */

$('tab-in').addEventListener('click', () => {
  $('tab-in').classList.add('active'); $('tab-up').classList.remove('active');
  show($('form-in')); hide($('form-up')); clearAuthMsgs();
});
$('tab-up').addEventListener('click', () => {
  $('tab-up').classList.add('active'); $('tab-in').classList.remove('active');
  show($('form-up')); hide($('form-in')); clearAuthMsgs();
});

/* ── sign in (password → verifier) ──────────────── */

$('form-in').addEventListener('submit', async (e) => {
  e.preventDefault(); clearAuthMsgs();
  authStatus('Deriving keys on this device…');
  try {
    const email = $('in-email').value.trim().toLowerCase();
    const kdf = await api(`/api/auth/kdf-params?email=${encodeURIComponent(email)}`).catch(() => ({ kdf: DEFAULT_KDF }));
    const salt = kdf.kdf_salt_b64;
    if (!salt) throw new Error('Cannot look up this account right now.');
    const { verifier } = await deriveCredentials($('in-pass').value, salt, kdf.kdf ?? DEFAULT_KDF);
    hide($('auth-status'));
    const r = await api('/api/auth/login', { body: { email, verifier_b64: bytesToB64(verifier) } });
    if (r.ok) showDash();
  } catch (err) {
    hide($('auth-status'));
    authError(err.message);
  }
});

/* ── create account ─────────────────────────────── */

$('form-up').addEventListener('submit', async (e) => {
  e.preventDefault(); clearAuthMsgs();
  const btn = $('up-submit'); btn.disabled = true;
  authStatus('Generating your vault key on this device…');
  try {
    const email = $('up-email').value.trim().toLowerCase();
    const username = $('up-username').value.trim().toLowerCase();
    const password = $('up-pass').value;
    const saltB64 = bytesToB64(crypto.getRandomValues(new Uint8Array(16)));
    const { verifier, kek } = await deriveCredentials(password, saltB64, DEFAULT_KDF);
    const { wrapped, nonce } = await wrapVaultKey(generateVaultKey(), kek);
    hide($('auth-status'));
    authStatus('Creating your Aegis ID…');
    const r = await api('/api/auth/register', {
      body: {
        email,
        username,
        kdf_salt_b64: saltB64,
        verifier_b64: bytesToB64(verifier),
        wrapped_vault_key_b64: bytesToB64(wrapped),
        vault_nonce_b64: bytesToB64(nonce),
        kdf: DEFAULT_KDF,
      },
    });
    if (r.ok) showDash();
  } catch (err) {
    hide($('auth-status'));
    authError(err.message);
  } finally {
    btn.disabled = false;
  }
});

/* ── Google ─────────────────────────────────────── */

$('google-btn').addEventListener('click', () => { window.location.href = '/api/auth/google/start'; });

/* ── passkey sign-in ────────────────────────────── */

$('passkey-btn').addEventListener('click', async () => {
  clearAuthMsgs();
  try {
    const email = $('in-email').value.trim().toLowerCase() || undefined;
    const { options, challenge_id } = await api('/api/auth/passkey/start', { body: { email: email || null } });
    const assertion = await navigator.credentials.get({ publicKey: options });
    const r = await api('/api/auth/passkey/finish', { body: { challenge_id, response: assertion } });
    if (r.ok) showDash();
  } catch (err) {
    authError(err.name === 'NotAllowedError' ? 'Passkey cancelled or not available.' : err.message);
  }
});

/* ── dashboard ──────────────────────────────────── */

async function refreshMe() {
  try {
    const me = await api('/api/auth/me');
    if (!me || me.error) return showAuth();
    renderMe(me);
    refreshProfile();
    refreshPasskeys();
    refreshConnections();
  } catch {
    showAuth();
  }
}

function renderMe(me) {
  const letter = (me.display_name || me.username || me.email || '?').trim()[0]?.toUpperCase() ?? '?';
  avatarStyle(me.avatar_url, letter);
  $('who-name').textContent = me.display_name || me.username || me.email;
  $('who-email').textContent = me.email;
  const flags = [
    me.has_password ? ['password account', 'ok'] : null,
    me.google_linked ? ['Google linked', 'ok'] : null,
    me.google_managed ? ['server-managed vault'] : null,
    me.sync_linked ? ['sync connected', 'ok'] : ['connect: sign in with password once'],
    me.linked_only ? ['finish linking via password sign-in'] : null,
  ].filter(Boolean);
  $('who-flags').innerHTML = flags.map(([t, c]) => `<span class="flag ${c ?? ''}">${t}</span>`).join('');
}

async function refreshProfile() {
  const p = await api('/api/account/profile').catch(() => ({}));
  if (p.identity) {
    $('pf-display').value = p.identity.display_name ?? '';
    $('pf-avatar').value = p.identity.avatar_url ?? '';
    $('public-line').textContent = p.public_profile
      ? `Public profile @${p.public_profile.username}: avatar ${p.public_profile.avatar_url ? 'set' : 'unset'} (source: ${p.public_profile.source})`
      : '';
  }
}

$('form-profile').addEventListener('submit', async (e) => {
  e.preventDefault();
  try {
    const r = await api('/api/account/profile', { method: 'PUT', body: { display_name: $('pf-display').value, avatar_url: $('pf-avatar').value || null } });
    if (r.ok) refreshMe();
  } catch (err) { alert(err.message); }
});

/* passkeys */

async function refreshPasskeys() {
  const list = await api('/api/passkeys').catch(() => ({ passkeys: [] }));
  $('pk-count').textContent = `${list.passkeys.length} registered`;
  $('pk-list').innerHTML = list.passkeys
    .map((p) => `<li><span>${p.device ?? p.id.slice(0, 10)}… <span class="dim">· ${new Date(p.created_at * 1000).toLocaleDateString()}</span></span>
      <button class="btn ghost small" data-del-pk="${p.id}">Remove</button></li>`)
    .join('');
  $('pk-list').querySelectorAll('[data-del-pk]').forEach((b) =>
    b.addEventListener('click', async () => {
      await api(`/api/passkeys?id=${encodeURIComponent(b.dataset.delPk)}`, { method: 'DELETE' });
      refreshPasskeys();
    }));
}

$('pk-add').addEventListener('click', async () => {
  try {
    const { options, challenge_id } = await api('/api/passkeys/register-start', { method: 'POST' });
    const attestation = await navigator.credentials.create({ publicKey: options });
    const r = await api('/api/passkeys/register-finish', { method: 'POST', body: { challenge_id, response: attestation } });
    if (r.ok) refreshPasskeys();
  } catch (err) { alert(err.name === 'NotAllowedError' ? 'Passkey cancelled.' : err.message); }
});

/* password change */

$('pw-toggle').addEventListener('click', () => $('form-pw').classList.toggle('hidden'));

$('form-pw').addEventListener('submit', async (e) => {
  e.preventDefault();
  try {
    const oldPw = $('pw-old').value;
    const newPw = $('pw-new').value;
    const kdf = await api(`/api/auth/kdf-params?email=${encodeURIComponent($('who-email').textContent)}`).catch(() => ({ kdf: DEFAULT_KDF }));
    const oldCred = await deriveCredentials(oldPw, kdf.kdf_salt_b64, kdf.kdf ?? DEFAULT_KDF);
    const newSaltB64 = bytesToB64(crypto.getRandomValues(new Uint8Array(16)));
    const newCred = await deriveCredentials(newPw, newSaltB64, DEFAULT_KDF);
    // Sign in with the OLD verifier to receive the wrapped vault key, unwrap
    // it on this device, and re-wrap it under the NEW credentials — so every
    // other device can still decrypt the synced data with the new password.
    const me = await api('/api/auth/me');
    const login = await api('/api/auth/login', { body: { email: me.email, verifier_b64: bytesToB64(oldCred.verifier) } });
    const vaultKey = await unwrapVaultKey(b64ToBytes(login.user.wrapped_vault_key_b64), login.user.vault_nonce_b64, oldCred.kek);
    const rewrapped = await wrapVaultKey(vaultKey, newCred.kek);
    const r = await api('/api/account/password', {
      body: {
        old_verifier_b64: bytesToB64(oldCred.verifier),
        new_verifier_b64: bytesToB64(newCred.verifier),
        kdf_salt_b64: newSaltB64,
        kdf: DEFAULT_KDF,
        wrapped_vault_key_b64: bytesToB64(rewrapped.wrapped),
        vault_nonce_b64: bytesToB64(rewrapped.nonce),
      },
    });
    if (r.ok) {
      $('form-pw').classList.add('hidden');
      refreshMe();
      alert('Password updated. Other devices must sign in again.');
    }
  } catch (err) { alert(err.message); }
});

/* connections */

async function refreshConnections() {
  const c = await api('/api/account/connections').catch(() => null);
  if (!c) return;
  const group = (title, items, fmt) => `
    <div class="tgroup"><h4>${title}</h4><ul>
      ${items.length ? items.map(fmt).join('') : '<li class="dim">None yet</li>'}
    </ul></div>`;
  $('conn-wrap').innerHTML = [
    group('Browser sync', c.browser ?? [], (d) => `<li><span>${d.name}</span><span class="dim">${d.platform}${d.current ? ' <span class="cur">this</span>' : ''}</span></li>`),
    group('AEGIS OS sync', c.os ?? [], (d) => `<li><span>${d.name}</span><span class="dim">${d.platform}${d.current ? ' <span class="cur">this</span>' : ''}</span></li>`),
    group('Portal (web)', c.portal ?? [], (d) => `<li><span>${new Date(d.created_at * 1000).toLocaleDateString()}</span><span class="dim">${d.current ? '<span class="cur">this session</span>' : ''}</span></li>`),
  ].join('');
}

/* logout + delete */

$('logout').addEventListener('click', async () => {
  await api('/api/auth/logout', { method: 'POST' });
  showAuth();
});

$('del-toggle').addEventListener('click', () => $('form-del').classList.toggle('hidden'));

$('form-del').addEventListener('submit', async (e) => {
  e.preventDefault();
  if (!confirm('Delete your Aegis ID and ALL synced data? This cannot be undone.')) return;
  try {
    const body = {};
    if ($('del-pass').value) {
      const kdf = await api(`/api/auth/kdf-params?email=${encodeURIComponent($('who-email').textContent)}`).catch(() => ({ kdf: DEFAULT_KDF }));
      const { verifier } = await deriveCredentials($('del-pass').value, kdf.kdf_salt_b64, kdf.kdf ?? DEFAULT_KDF);
      body.verifier_b64 = bytesToB64(verifier);
    }
    const r = await api('/api/account', { method: 'DELETE', body });
    if (r.ok) showAuth();
  } catch (err) { alert(err.message); }
});
