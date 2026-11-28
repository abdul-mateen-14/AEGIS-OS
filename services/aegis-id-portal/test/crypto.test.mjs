// Parity with the browser's Android client (AegisCryptoVectors.kt) and the
// deployed backend: the portal derives IDENTICAL credentials.
import test from 'node:test';
import assert from 'node:assert/strict';
import {
  DEFAULT_KDF,
  b64ToBytes,
  bytesToB64,
  deriveCredentials,
  generateVaultKey,
  wrapVaultKey,
  unwrapVaultKey,
} from '../public/lib/aegis-crypto.mjs';

const SALT1 = 'FgH9wQBEiT1IE9+slRIt6Q==';
const PW = 'correct horse battery staple';
// from android-sync/test/AegisCryptoVectors.kt (masterKey600kHex)
const MASTER_600K_HEX = 'd5ebbb5adfc344e871370d59a35049a5db936e77b3b340bdd70a5897442a599b';

test('masterKey matches the Kotlin vector byte for byte', async () => {
  const { masterKey } = await deriveCredentials(PW, SALT1, DEFAULT_KDF);
  const hex = [...masterKey].map((b) => b.toString(16).padStart(2, '0')).join('');
  assert.equal(hex, MASTER_600K_HEX);
});

test('verifier + kek are deterministic for the same inputs', async () => {
  const a = await deriveCredentials(PW, SALT1, { algo: 'PBKDF2-SHA256', iterations: 1000 });
  const b = await deriveCredentials(PW, SALT1, { algo: 'PBKDF2-SHA256', iterations: 1000 });
  assert.equal(bytesToB64(a.verifier), bytesToB64(b.verifier));
  assert.equal(bytesToB64(a.kek), bytesToB64(b.kek));
  assert.notEqual(bytesToB64(a.verifier), bytesToB64(a.kek));
});

test('different iterations → different verifier', async () => {
  const a = await deriveCredentials(PW, SALT1, DEFAULT_KDF);
  const b = await deriveCredentials(PW, SALT1, { algo: 'PBKDF2-SHA256', iterations: 1000 });
  assert.notEqual(bytesToB64(a.verifier), bytesToB64(b.verifier));
});

test('vault key wrap/unwrap roundtrip (with base64 strings, as the API returns them)', async () => {
  const vaultKey = generateVaultKey();
  const { kek } = await deriveCredentials(PW, SALT1, { algo: 'PBKDF2-SHA256', iterations: 1000 });
  const { wrapped, nonce } = await wrapVaultKey(vaultKey, kek);
  const unwrapped = await unwrapVaultKey(wrapped, bytesToB64(nonce), kek);
  assert.deepEqual([...unwrapped], [...vaultKey]);
  // and from a base64 wrapped blob (the shape /v1/auth/login returns):
  const unwrapped2 = await unwrapVaultKey(b64ToBytes(bytesToB64(wrapped)), bytesToB64(nonce), kek);
  assert.deepEqual([...unwrapped2], [...vaultKey]);
});

test('wrong kek cannot unwrap (GCM auth)', async () => {
  const vaultKey = generateVaultKey();
  const c1 = await deriveCredentials(PW, SALT1, { algo: 'PBKDF2-SHA256', iterations: 1000 });
  const c2 = await deriveCredentials('different password', SALT1, { algo: 'PBKDF2-SHA256', iterations: 1000 });
  const { wrapped, nonce } = await wrapVaultKey(vaultKey, c1.kek);
  await assert.rejects(() => unwrapVaultKey(bytesToB64(wrapped), bytesToB64(nonce), c2.kek));
});
