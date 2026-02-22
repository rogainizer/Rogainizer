import { Router } from 'express';
import { createAuthToken, isValidLogin, verifyAuthToken } from '../config/auth.js';

const router = Router();

router.post('/login', (req, res) => {
  const username = String(req.body?.username || '').trim();
  const password = String(req.body?.password || '');

  if (!isValidLogin(username, password)) {
    return res.status(401).json({ message: 'Invalid username or password.' });
  }

  const token = createAuthToken(username);
  const payload = verifyAuthToken(token);

  return res.json({
    token,
    expiresAt: payload?.exp || null,
    username: payload?.username || username
  });
});

router.get('/validate', (req, res) => {
  const rawAuth = String(req.headers?.authorization || '');
  if (!rawAuth.startsWith('Bearer ')) {
    return res.status(401).json({ message: 'Authentication required.' });
  }

  const token = rawAuth.slice('Bearer '.length).trim();
  const payload = verifyAuthToken(token);

  if (!payload) {
    return res.status(401).json({ message: 'Invalid or expired authentication token.' });
  }

  return res.json({ valid: true, username: payload.username, expiresAt: payload.exp });
});

export default router;
