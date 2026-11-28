// THE ISOLATION GUARD — the OS worker binds the browser's aegis-sync D1
// database to reuse identity (email/username, the same Aegis ID), but the
// browser database and its users' data must never be modified from here.
//
// Every statement aimed at env.BROWSER must go through these helpers; they
// reject anything that is not a plain read. Defense in depth on top of code
// review: a bug can no longer mutate the primary browser backend.

export class ReadOnlyViolation extends Error {
  constructor(sql) {
    super(`BROWSER binding is READ-ONLY — rejected statement: ${sql.slice(0, 120)}`);
    this.name = 'ReadOnlyViolation';
  }
}

// Only SELECT (and WITH … SELECT) may touch the browser database. A trailing
// semicolon is tolerated, but a second statement ("SELECT 1; DROP …") is not.
const READ_ONLY = /^\s*(SELECT|WITH)\b/i;
const MULTI_STATEMENT = /;\s*\S/;

export function assertReadOnly(sql) {
  if (typeof sql !== 'string' || !READ_ONLY.test(sql) || MULTI_STATEMENT.test(sql)) {
    throw new ReadOnlyViolation(String(sql));
  }
}

/** Prepare a guarded read against the browser database. */
export function browserPrepare(browserDb, sql) {
  assertReadOnly(sql);
  return browserDb.prepare(sql);
}

/** First row of a guarded browser read. */
export async function browserFirst(browserDb, sql, ...binds) {
  return browserPrepare(browserDb, sql).bind(...binds).first();
}

/** All rows of a guarded browser read. */
export async function browserAll(browserDb, sql, ...binds) {
  return browserPrepare(browserDb, sql).bind(...binds).all();
}
