// OS-owned identity field validation.
//
// Field ownership across the two backends:
//   email      — browser-owned (source of truth), reused read-only
//   username   — browser-owned (source of truth), reused read-only
//   avatar_url — OS-owned    (lives in OS identities, browser DB untouched)
//   display_name — OS-owned  (lives in OS identities, browser DB untouched)
//
// The username rules match the browser backend exactly, so one account id
// renders and resolves the same way on both sides.

import { ApiError } from './util.js';

export const OS_ITEM_TYPES = ['os-setting', 'os-profile', 'os-notes', 'os-keyring', 'os-island'];
export const VALID_PLATFORMS = ['android', 'windows', 'linux', 'macos', 'other'];

/** Validates + normalizes a username; same rules as the browser backend. */
export function normalizeUsername(raw) {
  const username = String(raw ?? '').trim().toLowerCase();
  if (!/^[a-z0-9_-]{3,24}$/.test(username)) {
    throw new ApiError(400, 'invalid_request', 'Field "username" must be 3-24 chars: a-z 0-9 _ -');
  }
  return username;
}

/**
 * Validates an OS avatar URL. OS-owned field: https only, no data:/blob:
 * URIs, bounded length — it is rendered by Aegis ID and the browser UI.
 */
export function validateAvatarUrl(raw) {
  if (raw === null || raw === undefined || raw === '') return null;
  if (typeof raw !== 'string') {
    throw new ApiError(400, 'invalid_request', 'Field "avatar_url" must be a string or null');
  }
  const url = raw.trim();
  if (url.length > 512) {
    throw new ApiError(400, 'invalid_request', 'Field "avatar_url" must be at most 512 chars');
  }
  if (!/^https:\/\//i.test(url)) {
    throw new ApiError(400, 'invalid_request', 'Field "avatar_url" must be an https:// URL (or null to clear)');
  }
  let parsed;
  try {
    parsed = new URL(url);
  } catch {
    throw new ApiError(400, 'invalid_request', 'Field "avatar_url" is not a valid URL');
  }
  if (parsed.username || parsed.password || parsed.protocol !== 'https:') {
    throw new ApiError(400, 'invalid_request', 'Field "avatar_url" must be a plain https:// URL');
  }
  return url;
}

/**
 * Validates a display name (OS-owned): trims, drops control characters,
 * caps at 64 chars. Empty string clears the field.
 */
export function validateDisplayName(raw) {
  if (raw === null || raw === undefined || raw === '') return null;
  if (typeof raw !== 'string') {
    throw new ApiError(400, 'invalid_request', 'Field "display_name" must be a string or null');
  }
  // eslint-disable-next-line no-control-regex
  const cleaned = raw.replace(/[\u0000-\u001f\u007f]/g, ' ').trim().replace(/\s+/g, ' ');
  if (cleaned.length === 0) return null;
  if (cleaned.length > 64) {
    throw new ApiError(400, 'invalid_request', 'Field "display_name" must be at most 64 chars');
  }
  return cleaned;
}
