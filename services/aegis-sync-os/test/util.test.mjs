// Helpers: b64, hashing, tokens, JSON parsing, email rules.
import test from 'node:test';
import assert from 'node:assert/strict';
import {
  ApiError,
  b64ToBytes,
  bytesToB64,
  constantTimeEqual,
  normalizeEmail,
  randomTokenB64,
  readJson,
  sha256,
  utf8,
} from '../src/util.js';

test('base64 roundtrip', () => {
  const bytes = new Uint8Array([0, 1, 2, 250, 251, 252, 253, 254, 255]);
  assert.deepEqual(b64ToBytes(bytesToB64(bytes)), bytes);
});

test('sha256 known vector', async () => {
  const digest = await sha256(utf8.encode('abc'));
  assert.equal(bytesToB64(digest), 'ungWv48Bz+pBQUDeXa4iI7ADYaOWF3qctBD/YfIAFa0=');
});

test('constantTimeEqual', () => {
  const a = new Uint8Array([1, 2, 3]);
  assert.ok(constantTimeEqual(a, new Uint8Array([1, 2, 3])));
  assert.ok(!constantTimeEqual(a, new Uint8Array([1, 2, 4])));
  assert.ok(!constantTimeEqual(a, new Uint8Array([1, 2])));
});

test('randomTokenB64 shape: aeg_ prefix, url-safe, ~43 chars body', () => {
  for (let i = 0; i < 20; i++) {
    const t = randomTokenB64();
    assert.ok(t.startsWith('aeg_'));
    assert.ok(!/[+/=]/.test(t));
    assert.ok(t.length >= 44 && t.length <= 52, t.length);
  }
});

test('readJson rejects junk and oversize', async () => {
  const req = (body) => new Request('https://x/', { method: 'POST', body });
  await assert.rejects(readJson(req('nope'), 1000), ApiError);
  await assert.rejects(readJson(req('x'.repeat(1001)), 1000), (e) => e instanceof ApiError && e.status === 413);
  const ok = await readJson(req('{"a":1}'), 1000);
  assert.deepEqual(ok, { a: 1 });
});

test('normalizeEmail mirrors the browser rules', () => {
  assert.equal(normalizeEmail('  User@Example.COM '), 'user@example.com');
  assert.throws(() => normalizeEmail('not-an-email'), ApiError);
  assert.throws(() => normalizeEmail('a@b'), ApiError);
});
