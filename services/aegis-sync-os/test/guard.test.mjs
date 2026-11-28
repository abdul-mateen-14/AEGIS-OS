// The isolation guard is the OS backend's most important safety property:
// it must reject anything that could mutate the browser database.
import test from 'node:test';
import assert from 'node:assert/strict';
import { assertReadOnly, ReadOnlyViolation } from '../src/guard.js';

test('SELECT statements pass', () => {
  assertReadOnly('SELECT id FROM users WHERE email = ?');
  assertReadOnly('  select * from users');
  assertReadOnly('SELECT * FROM t;');
  assertReadOnly('WITH x AS (SELECT 1) SELECT * FROM x');
});

test('every write verb is rejected', () => {
  for (const sql of [
    'INSERT INTO users VALUES (1)',
    'UPDATE users SET email = ?',
    'DELETE FROM users',
    'ALTER TABLE users ADD COLUMN x',
    'CREATE TABLE evil (id)',
    'DROP TABLE users',
    'PRAGMA foreign_keys = off',
    'REPLACE INTO users VALUES (1)',
    'ATTACH DATABASE "x" AS evil',
    'VACUUM',
  ]) {
    assert.throws(() => assertReadOnly(sql), ReadOnlyViolation, sql);
  }
});

test('multi-statement injection is rejected even if it starts with SELECT', () => {
  assert.throws(() => assertReadOnly('SELECT 1; DROP TABLE users'), ReadOnlyViolation);
  assert.throws(() => assertReadOnly('SELECT 1; DELETE FROM users'), ReadOnlyViolation);
  assert.throws(() => assertReadOnly("SELECT * FROM t; INSERT INTO users VALUES (1)"), ReadOnlyViolation);
  // a lone trailing semicolon stays fine
  assertReadOnly('SELECT * FROM t ; ');
});

test('non-string input is rejected', () => {
  assert.throws(() => assertReadOnly(null), ReadOnlyViolation);
  assert.throws(() => assertReadOnly(undefined), ReadOnlyViolation);
  assert.throws(() => assertReadOnly(42), ReadOnlyViolation);
});
