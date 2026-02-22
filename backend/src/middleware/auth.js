import { verifyAuthToken } from '../config/auth.js';

export function requireAuth(req, res, next) {
  const rawAuth = String(req.headers?.authorization || '');
  const hasBearer = rawAuth.startsWith('Bearer ');

  if (!hasBearer) {
    return res.status(401).json({ message: 'Authentication required.' });
  }

  const token = rawAuth.slice('Bearer '.length).trim();
  const payload = verifyAuthToken(token);

  if (!payload) {
    return res.status(401).json({ message: 'Invalid or expired authentication token.' });
  }

  req.auth = payload;
  return next();
}
