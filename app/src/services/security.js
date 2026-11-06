import { randomBytes, scryptSync, timingSafeEqual } from 'node:crypto';
export function hashPassword(password) { const salt = randomBytes(16).toString('hex'); return salt + ':' + scryptSync(password,salt,64).toString('hex'); }
export function verifyPassword(password, stored) { const [salt,hash] = stored.split(':'); const derived = scryptSync(password,salt,64); const expected = Buffer.from(hash,'hex'); return derived.length === expected.length && timingSafeEqual(derived,expected); }
