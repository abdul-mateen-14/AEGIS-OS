// Response helpers for Pages Functions (same error shape as the sync backends).

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

export function errResponse(e) {
  if (e instanceof ApiError) {
    return json({ error: { code: e.code, message: e.message } }, e.status);
  }
  console.error('internal error:', e);
  return json({ error: { code: 'internal', message: 'Internal server error' } }, 500);
}

export async function readJson(request, maxBytes = 512 * 1024) {
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

export function normalizeEmail(raw) {
  const email = String(raw ?? '').trim().toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email.length > 254) {
    throw new ApiError(400, 'invalid_request', 'Field "email" must be a valid email address');
  }
  return email;
}
