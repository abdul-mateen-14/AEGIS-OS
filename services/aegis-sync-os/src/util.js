// aegis-sync-os shared helpers — a faithful JS port of the browser
// backend's util.ts (AEGIS-BROWSER/aegis-sync/src/util.ts), so response
// shapes and error semantics stay identical across the two backends.

export class ApiError extends Error {
  constructor(status, code, message) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

export function json(data, status = 200, extraHeaders = {}) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json; charset=utf-8', ...extraHeaders },
  });
}

export function errResponse(e, corsHeaders) {
  if (e instanceof ApiError) {
    return json({ error: { code: e.code, message: e.message } }, e.status, corsHeaders);
  }
  console.error('internal error:', e);
  return json({ error: { code: 'internal', message: 'Internal server error' } }, 500, corsHeaders);
}

// ---------- encoding ----------

export function b64ToBytes(b64) {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

export function bytesToB64(bytes) {
  let bin = '';
  for (let i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
  return btoa(bin);
}

export const utf8 = new TextEncoder();

export function nowSec() {
  return Math.floor(Date.now() / 1000);
}

// ---------- crypto ----------

export async function sha256(data) {
  const digest = await crypto.subtle.digest('SHA-256', data);
  return new Uint8Array(digest);
}

/** Constant-time comparison (prevents trivial timing oracles on token/verifier checks). */
export function constantTimeEqual(a, b) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

export function randomTokenB64() {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return 'aeg_' + bytesToB64(bytes).replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/, '');
}

// ---------- request parsing ----------

export async function readJson(request, maxBytes) {
  const lenHeader = parseInt(request.headers.get('Content-Length') ?? '0', 10);
  if (lenHeader > maxBytes) throw new ApiError(413, 'payload_too_large', 'Request body too large');
  const text = await request.text();
  if (text.length > maxBytes) throw new ApiError(413, 'payload_too_large', 'Request body too large');
  try {
    return JSON.parse(text);
  } catch {
    throw new ApiError(400, 'invalid_request', 'Body must be valid JSON');
  }
}

export function requireString(obj, field, maxLen = 320) {
  const v = obj[field];
  if (typeof v !== 'string' || v.length === 0 || v.length > maxLen) {
    throw new ApiError(400, 'invalid_request', `Field "${field}" must be a non-empty string (max ${maxLen} chars)`);
  }
  return v;
}

export function requireB64(obj, field, maxBytes) {
  const v = obj[field];
  if (typeof v !== 'string' || v.length === 0) {
    throw new ApiError(400, 'invalid_request', `Field "${field}" must be a base64 string`);
  }
  let bytes;
  try {
    bytes = b64ToBytes(v);
  } catch {
    throw new ApiError(400, 'invalid_request', `Field "${field}" is not valid base64`);
  }
  if (bytes.length > maxBytes) throw new ApiError(400, 'invalid_request', `Field "${field}" exceeds ${maxBytes} bytes`);
  return bytes;
}

export function normalizeEmail(raw) {
  const email = raw.trim().toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email.length > 254) {
    throw new ApiError(400, 'invalid_request', 'Field "email" must be a valid email address');
  }
  return email;
}

// ---------- limits (mirrors the browser backend's free-tier tuning) ----------

export const LIMITS = {
  MAX_PUSH_ITEMS: 200,
  MAX_CIPHERTEXT_BYTES: 512 * 1024,
  MAX_BODY_BYTES: 4 * 1024 * 1024,
  PULL_PAGE_SIZE: 500,
  EXPORT_PAGE_SIZE: 1000,
  ACCESS_TOKEN_TTL: 24 * 3600,
  REFRESH_TOKEN_TTL: 90 * 24 * 3600,
};
