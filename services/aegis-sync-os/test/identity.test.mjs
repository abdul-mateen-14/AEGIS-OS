// OS-owned identity field validation.
import test from 'node:test';
import assert from 'node:assert/strict';
import { normalizeUsername, validateAvatarUrl, validateDisplayName, OS_ITEM_TYPES } from '../src/identity.js';
import { ApiError } from '../src/util.js';

test('username rules match the browser backend exactly', () => {
  assert.equal(normalizeUsername('  Alice_01 '), 'alice_01');
  assert.equal(normalizeUsername('a-b_c'), 'a-b_c');
  for (const bad of ['ab', 'x'.repeat(25), 'Has Space', 'héllo', 'a!b', '']) {
    assert.throws(() => normalizeUsername(bad), ApiError, bad);
  }
});

test('avatar_url accepts https only', () => {
  assert.equal(validateAvatarUrl('https://id.aegis.os/u/x.png'), 'https://id.aegis.os/u/x.png');
  assert.equal(validateAvatarUrl(null), null);
  assert.equal(validateAvatarUrl(''), null);
  assert.equal(validateAvatarUrl(undefined), null);
  for (const bad of ['http://aegis.os/x.png', 'data:image/png;base64,AAAA', 'blob:https://x/y', 'ftp://a/b', 'https://user:pw@a/b', 'not a url']) {
    assert.throws(() => validateAvatarUrl(bad), ApiError, bad);
  }
  assert.throws(() => validateAvatarUrl('https://a/' + 'x'.repeat(600)), ApiError);
});

test('display_name trims, strips control chars, caps at 64', () => {
  assert.equal(validateDisplayName('  Ada  Lovelace '), 'Ada Lovelace');
  assert.equal(validateDisplayName('a\tb\nc'), 'a b c');
  assert.equal(validateDisplayName(''), null);
  assert.throws(() => validateDisplayName('x'.repeat(65)), ApiError);
});

test('OS item types are disjoint from the browser set', () => {
  const browserTypes = ['bookmark', 'tab', 'setting', 'password', 'autofill'];
  for (const t of OS_ITEM_TYPES) {
    assert.ok(t.startsWith('os-'), t);
    assert.ok(!browserTypes.includes(t), t);
  }
});
