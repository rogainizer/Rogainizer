import crypto from 'crypto';

const authUsername = String(process.env.AUTH_USERNAME || 'admin');
const authPassword = String(process.env.AUTH_PASSWORD || 'admin');
const authSecret = String(process.env.AUTH_SECRET || 'change-this-secret');
const authTtlHours = Number(process.env.AUTH_TTL_HOURS || 12);

function base64UrlEncode(value) {
  return Buffer.from(value)
    .toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/g, '');
}

function base64UrlDecode(value) {
  const normalized = String(value)
    .replace(/-/g, '+')
    .replace(/_/g, '/');

  const padLength = (4 - (normalized.length % 4)) % 4;
  const padded = normalized + '='.repeat(padLength);

  return Buffer.from(padded, 'base64').toString('utf8');
}

function signPayload(payloadEncoded) {
  return base64UrlEncode(
    crypto
      .createHmac('sha256', authSecret)
      .update(payloadEncoded)
      .digest()
  );
}

export function createAuthToken(username) {
  const nowSeconds = Math.floor(Date.now() / 1000);
  const ttlSeconds = Number.isFinite(authTtlHours) && authTtlHours > 0
    ? Math.floor(authTtlHours * 3600)
    : 12 * 3600;

  const payload = {
    username: String(username || '').trim() || authUsername,
    iat: nowSeconds,
    exp: nowSeconds + ttlSeconds
  };

  const payloadEncoded = base64UrlEncode(JSON.stringify(payload));
  const signature = signPayload(payloadEncoded);

  return `${payloadEncoded}.${signature}`;
}

export function verifyAuthToken(token) {
  const tokenValue = String(token || '').trim();
  if (!tokenValue.includes('.')) {
    return null;
  }

  const [payloadEncoded, signature] = tokenValue.split('.');
  if (!payloadEncoded || !signature) {
    return null;
  }

  const expectedSignature = signPayload(payloadEncoded);

  const provided = Buffer.from(signature);
  const expected = Buffer.from(expectedSignature);
  if (provided.length !== expected.length || !crypto.timingSafeEqual(provided, expected)) {
    return null;
  }

  try {
    const payloadRaw = base64UrlDecode(payloadEncoded);
    const payload = JSON.parse(payloadRaw);

    const exp = Number(payload?.exp);
    if (!Number.isFinite(exp)) {
      return null;
    }

    const nowSeconds = Math.floor(Date.now() / 1000);
    if (exp <= nowSeconds) {
      return null;
    }

    return payload;
  } catch {
    return null;
  }
}

export function isValidLogin(username, password) {
  return String(username || '').trim() === authUsername
    && String(password || '') === authPassword;
}
