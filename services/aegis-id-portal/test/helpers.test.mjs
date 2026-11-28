// Portal helpers: email rules, session cookie/codec primitives.
import test from 'node:test';
import assert from 'node:assert/strict';
import { ApiError, normalizeEmail, requireString } from '../functions/lib/json.js';
import { b64urlEncode, sessionCookie, sha256Hex, SESSION_COOKIE } from '../functions/lib/session.js';

test('normalizeEmail mirrors the backends', () => {
  assert.equal(normalizeEmail('  User@Example.COM '), 'user@example.com');
  for (const bad of ['not-an-email', 'a@b', '', 'a b@c.com']) {
    assert.throws(() => normalizeEmail(bad), ApiError);
  }
});

test('requireString bounds', () => {
  assert.equal(requireString({ a: 'ok' }, 'a'), 'ok');
  assert.throws(() => requireString({ a: '' }, 'a'), ApiError);
  assert.throws(() => requireString({ a: 'x'.repeat(321) }, 'a'), ApiError);
  assert.throws(() => requireString({}, 'missing'), ApiError);
});

test('b64urlEncode is url-safe and unpadded', () => {
  const t = b64urlEncode(new Uint8Array(32));
  assert.ok(!/[+/=]/.test(t));
  assert.ok(t.length >= 42 && t.length <= 44);
});

test('cookie is HttpOnly Secure SameSite', () => {
  const c = sessionCookie('tok123', 60);
  assert.ok(c.includes(`${SESSION_COOKIE}=tok123`));
  assert.ok(c.includes('HttpOnly') && c.includes('Secure') && c.includes('SameSite=Lax'));
  assert.ok(c.includes('Max-Age=60'));
});

test('sha256Hex is stable and hex', async () => {
  const h = await sha256Hex('abc');
  assert.equal(h, 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
});
