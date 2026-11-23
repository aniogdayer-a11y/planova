import { DatabaseSync } from 'node:sqlite';
import { randomUUID, randomInt, randomBytes, createHash, createHmac, timingSafeEqual, scrypt } from 'node:crypto';
import { promisify } from 'node:util';
import { mkdirSync, existsSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';

export class HttpError extends Error {
  constructor(status, message) { super(message); this.status = status; }
}
export const hashToken = value => createHash('sha256').update(value).digest('hex');
const derive = promisify(scrypt);
let activeHashes = 0;
export function validatePassword(password) {
  if (typeof password !== 'string' || password.length < 12 || password.length > 128 || Buffer.byteLength(password) > 512) {
    throw new HttpError(400,'Use a password with 12 to 128 characters.');
  }
}
async function passwordKey(password, salt) {
  if (activeHashes >= 2) throw new HttpError(503,'The account service is busy. Please try again shortly.');
  activeHashes++;
  try { return await derive(password,salt,64,{N:32768,r:8,p:3,maxmem:64*1024*1024}); }
  finally { activeHashes--; }
}
export async function hashPassword(password) {
  validatePassword(password);
  const salt = randomBytes(16);
  const hash = await passwordKey(password,salt);
  return 'scrypt$32768$8$3$'+salt.toString('base64')+'$'+hash.toString('base64');
}
async function checkPassword(password, stored) {
  const parts = typeof stored === 'string' ? stored.split('$') : [];
  const valid = parts.length === 6 && parts.slice(0,4).join('$') === 'scrypt$32768$8$3';
  const salt = valid ? Buffer.from(parts[4],'base64') : Buffer.alloc(16,1);
  const expected = valid ? Buffer.from(parts[5],'base64') : Buffer.alloc(64);
  const actual = await passwordKey(password,salt);
  return valid && expected.length === actual.length && timingSafeEqual(actual,expected);
}
export function openAccountDatabase(path) {
  if (path !== ':memory:') mkdirSync(dirname(path), {recursive:true});
  const db = new DatabaseSync(path);
  db.exec(`PRAGMA foreign_keys = ON; PRAGMA journal_mode = WAL; PRAGMA busy_timeout = 5000;
    CREATE TABLE IF NOT EXISTS users (
      id TEXT PRIMARY KEY, email TEXT NOT NULL UNIQUE, name TEXT NOT NULL, created_at INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS challenges (
      id TEXT PRIMARY KEY, email TEXT NOT NULL, name TEXT NOT NULL, purpose TEXT NOT NULL,
      code_hash TEXT NOT NULL, expires_at INTEGER NOT NULL, attempts INTEGER NOT NULL DEFAULT 0,
      consumed INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL);
    CREATE INDEX IF NOT EXISTS challenges_email ON challenges(email, created_at);
    CREATE TABLE IF NOT EXISTS auth_requests (email TEXT NOT NULL, ip TEXT NOT NULL, created_at INTEGER NOT NULL);
    CREATE INDEX IF NOT EXISTS auth_requests_time ON auth_requests(created_at);
    CREATE TABLE IF NOT EXISTS login_attempts (email TEXT NOT NULL, ip TEXT NOT NULL, created_at INTEGER NOT NULL);
    CREATE INDEX IF NOT EXISTS login_attempts_time ON login_attempts(created_at);
    CREATE TABLE IF NOT EXISTS sessions (
      token_hash TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      expires_at INTEGER NOT NULL, created_at INTEGER NOT NULL);
  `);
  const columns = table => new Set(db.prepare('PRAGMA table_info('+table+')').all().map(row => row.name));
  if (!columns('users').has('password_hash')) {
    db.exec("ALTER TABLE users ADD COLUMN password_hash TEXT NOT NULL DEFAULT ''; UPDATE challenges SET consumed = 1;");
  }
  if (!columns('users').has('avatar_data')) db.exec("ALTER TABLE users ADD COLUMN avatar_data TEXT NOT NULL DEFAULT '';");
  if (!columns('challenges').has('password_hash')) db.exec("ALTER TABLE challenges ADD COLUMN password_hash TEXT NOT NULL DEFAULT '';");
  return db;
}
export function loadAuthSecret(folder) {
  mkdirSync(folder, {recursive:true});
  const file = resolve(folder, 'auth-secret');
  if (!existsSync(file)) {
    try { writeFileSync(file,randomBytes(32).toString('hex'),{mode:0o600,flag:'wx'}); }
    catch (error) { if (error.code !== 'EEXIST') throw error; }
  }
  const value = readFileSync(file,'utf8').trim();
  if (value.length < 32) throw new Error('The account signing secret is invalid.');
  return value;
}
export class AuthService {
  constructor({db,secret,sendCode,now=Date.now}) {
    this.db=db; this.secret=secret; this.sendCode=sendCode; this.now=now;
  }
  codeHash(id,code) { return createHmac('sha256',this.secret).update(id+':'+code).digest('hex'); }
  otpLimit(email,ip) {
    const now=this.now();
    this.db.prepare('DELETE FROM auth_requests WHERE created_at < ?').run(now-3_600_000);
    const latest=this.db.prepare('SELECT created_at FROM auth_requests WHERE email = ? ORDER BY created_at DESC LIMIT 1').get(email);
    if (latest && now-latest.created_at < 60_000) throw new HttpError(429,'Wait 60 seconds before requesting another code.');
    const emailCount=this.db.prepare('SELECT COUNT(*) AS n FROM auth_requests WHERE email = ?').get(email).n;
    const ipCount=this.db.prepare('SELECT COUNT(*) AS n FROM auth_requests WHERE ip = ?').get(ip).n;
    if (emailCount>=10 || ipCount>=30) throw new HttpError(429,'Too many requests. Try again later.');
  }
  credentialLimit(email,ip) {
    const now=this.now();
    this.db.prepare('DELETE FROM login_attempts WHERE created_at < ?').run(now-900_000);
    const emailCount=this.db.prepare('SELECT COUNT(*) AS n FROM login_attempts WHERE email = ?').get(email).n;
    const ipCount=this.db.prepare('SELECT COUNT(*) AS n FROM login_attempts WHERE ip = ?').get(ip).n;
    if (emailCount>=10 || ipCount>=50) throw new HttpError(429,'Too many sign-in attempts. Try again in 15 minutes.');
    this.db.prepare('INSERT INTO login_attempts VALUES (?,?,?)').run(email,ip,now);
  }
  async requestCode({email,name='',purpose,password},ip='unknown') {
    email=typeof email==='string' ? email.trim().toLowerCase() : '';
    name=typeof name==='string' ? name.trim() : '';
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email.length>254) throw new HttpError(400,'Enter a valid email address.');
    if (!['register','login','reset'].includes(purpose) || (purpose==='register' && (name.length<2 || name.length>60))) {
      throw new HttpError(400,'Enter your name and email address.');
    }
    if (!this.sendCode) throw new HttpError(503,'Email verification is not set up yet. Please contact the app owner.');
    this.otpLimit(email,ip);
    const existing=this.db.prepare('SELECT id,password_hash FROM users WHERE email = ?').get(email);
    let pendingHash='', actualPurpose=purpose;
    if (purpose==='register') {
      validatePassword(password);
      this.credentialLimit(email,ip);
      pendingHash=await hashPassword(password);
      if (existing) actualPurpose='unavailable';
    } else if (purpose==='login') {
      if (typeof password!=='string' || password.length<1 || password.length>128 || Buffer.byteLength(password)>512) throw new HttpError(401,'Email or password is incorrect.');
      this.credentialLimit(email,ip);
      if (!await checkPassword(password,existing?.password_hash)) throw new HttpError(401,'Email or password is incorrect.');
      if (this.db.prepare('SELECT password_hash FROM users WHERE id = ?').get(existing.id)?.password_hash !== existing.password_hash) throw new HttpError(401,'Email or password is incorrect.');
    } else if (!existing) actualPurpose='unavailable';
    this.otpLimit(email,ip);
    const now=this.now(), id=randomUUID();
    this.db.prepare('DELETE FROM challenges WHERE expires_at < ?').run(now-86_400_000);
    this.db.prepare('INSERT INTO auth_requests VALUES (?,?,?)').run(email,ip,now);
    const code=randomInt(0,1_000_000).toString().padStart(6,'0');
    this.db.prepare('UPDATE challenges SET consumed = 1 WHERE email = ?').run(email);
    this.db.prepare('INSERT INTO challenges(id,email,name,purpose,code_hash,expires_at,created_at,password_hash) VALUES (?,?,?,?,?,?,?,?)')
      .run(id,email,name,actualPurpose,this.codeHash(id,code),now+600_000,now,pendingHash);
    if (actualPurpose!=='unavailable') {
      try { await this.sendCode({email,code,purpose}); }
      catch {
        this.db.prepare('UPDATE challenges SET consumed = 1 WHERE id = ?').run(id);
        throw new HttpError(503,'We could not send the email. Please try again later.');
      }
    }
    return {challengeId:id,expiresIn:600,retryAfter:60,
      message:'If this address is eligible, a code has been sent. Check your inbox and spam folder.'};
  }
  invalidCode() { return new HttpError(400,'This code is incorrect or expired. Request a new code.'); }
  checkCode({challengeId,code},purposes) {
    if (typeof challengeId!=='string' || typeof code!=='string' || !/^\d{6}$/.test(code)) throw new HttpError(400,'Enter the six-digit code from your email.');
    const row=this.db.prepare('SELECT * FROM challenges WHERE id = ?').get(challengeId);
    if (!row || row.consumed || row.expires_at<=this.now() || row.attempts>=5 || !purposes.includes(row.purpose)) throw this.invalidCode();
    this.db.prepare('UPDATE challenges SET attempts = attempts + 1 WHERE id = ?').run(challengeId);
    const actual=Buffer.from(this.codeHash(challengeId,code),'hex'), expected=Buffer.from(row.code_hash,'hex');
    if (actual.length!==expected.length || !timingSafeEqual(actual,expected)) throw this.invalidCode();
    return row;
  }
  consume(row) {
    const result=this.db.prepare('UPDATE challenges SET consumed = 1 WHERE id = ? AND consumed = 0 AND expires_at > ? AND attempts <= 5').run(row.id,this.now());
    if (!result.changes) throw this.invalidCode();
  }
  verifyCode(input) {
    const row=this.checkCode(input,['register','login']);
    this.db.exec('BEGIN IMMEDIATE');
    try {
      this.consume(row);
      let user=this.db.prepare('SELECT id,email,name FROM users WHERE email = ?').get(row.email);
      if (row.purpose==='register') {
        if (user || !row.password_hash) throw this.invalidCode();
        user={id:randomUUID(),email:row.email,name:row.name};
        this.db.prepare('INSERT INTO users(id,email,name,created_at,password_hash) VALUES (?,?,?,?,?)')
          .run(user.id,user.email,user.name,this.now(),row.password_hash);
      } else if (!user) throw this.invalidCode();
      this.db.prepare('UPDATE challenges SET consumed = 1 WHERE email = ?').run(row.email);
      const token=randomBytes(32).toString('base64url'),expiresAt=this.now()+7*86_400_000;
      this.db.prepare('DELETE FROM sessions WHERE expires_at < ?').run(this.now());
      this.db.prepare('INSERT INTO sessions VALUES (?,?,?,?)').run(hashToken(token),user.id,expiresAt,this.now());
      this.db.exec('COMMIT');
      return {user,token,expiresAt};
    } catch (error) { this.db.exec('ROLLBACK'); throw error; }
  }
  async resetPassword(input) {
    validatePassword(input.password);
    const row=this.checkCode(input,['reset']);
    const passwordHash=await hashPassword(input.password);
    this.db.exec('BEGIN IMMEDIATE');
    try {
      this.consume(row);
      const user=this.db.prepare('SELECT id FROM users WHERE email = ?').get(row.email);
      if (!user) throw this.invalidCode();
      this.db.prepare('UPDATE users SET password_hash = ? WHERE id = ?').run(passwordHash,user.id);
      this.db.prepare('DELETE FROM sessions WHERE user_id = ?').run(user.id);
      this.db.prepare('UPDATE challenges SET consumed = 1 WHERE email = ?').run(row.email);
      this.db.prepare('DELETE FROM login_attempts WHERE email = ?').run(row.email);
      this.db.exec('COMMIT');
    } catch (error) { this.db.exec('ROLLBACK'); throw error; }
    try { await this.sendCode?.({email:row.email,purpose:'password-changed'}); } catch {}
    return {ok:true,message:'Password updated. Sign in with your new password.'};
  }
  tokenFrom(req) {
    const bearer=req.headers.authorization;
    if (typeof bearer==='string' && bearer.startsWith('Bearer ')) return bearer.slice(7);
    const cookie=req.headers.cookie?.split(';').map(v=>v.trim()).find(v=>v.startsWith('planner_session='));
    return cookie ? cookie.slice('planner_session='.length) : '';
  }
  authenticate(req) {
    const token=this.tokenFrom(req);
    if (!token || token.length>512) return null;
    return this.db.prepare(`SELECT users.id,users.email,users.name FROM sessions JOIN users ON users.id = sessions.user_id
      WHERE token_hash = ? AND expires_at > ?`).get(hashToken(token),this.now()) || null;
  }
  logout(req) {
    const token=this.tokenFrom(req);
    if (token) this.db.prepare('DELETE FROM sessions WHERE token_hash = ?').run(hashToken(token));
  }
}

