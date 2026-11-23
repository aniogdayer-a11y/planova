import test from 'node:test';
import assert from 'node:assert/strict';
import { AuthService, openAccountDatabase, HttpError } from './auth.mjs';

function fixture() {
  const db = openAccountDatabase(':memory:');
  const codes = [];
  let now = Date.now();
  const auth = new AuthService({db,secret:'test-secret-only-not-a-real-credential',
    now:() => now,sendCode:async value => codes.push(value)});
  return {db,auth,codes,advance:ms => now += ms};
}
const signup = {purpose:'register',password:'Example passphrase 123',name:'Test User',email:'person@example.test'};

test('account is created only after a valid single-use email OTP', async () => {
  const f = fixture();
  try {
    const challenge = await f.auth.requestCode(signup,'test-ip');
    assert.equal(f.db.prepare('SELECT COUNT(*) AS n FROM users').get().n,0);
    const stored = f.db.prepare('SELECT code_hash FROM challenges').get().code_hash;
    assert.notEqual(stored,f.codes[0].code);
    const session = f.auth.verifyCode({challengeId:challenge.challengeId,code:f.codes[0].code});
    assert.equal(session.user.email,signup.email);
    assert.equal(f.auth.authenticate({headers:{authorization:'Bearer '+session.token}}).id,session.user.id);
    assert.throws(() => f.auth.verifyCode({challengeId:challenge.challengeId,code:f.codes[0].code}),HttpError);
    f.auth.logout({headers:{authorization:'Bearer '+session.token}});
    assert.equal(f.auth.authenticate({headers:{authorization:'Bearer '+session.token}}),null);
  } finally { f.db.close(); }
});

test('OTP expires, rate limits resends, and blocks a sixth attempt', async () => {
  const f = fixture();
  try {
    const first = await f.auth.requestCode(signup,'test-ip');
    await assert.rejects(f.auth.requestCode(signup,'test-ip'),error => error.status === 429);
    const correct = f.codes[0].code;
    const wrong = ((Number(correct)+1)%1_000_000).toString().padStart(6,'0');
    for (let i=0;i<5;i++) assert.throws(() => f.auth.verifyCode({challengeId:first.challengeId,code:wrong}),HttpError);
    assert.throws(() => f.auth.verifyCode({challengeId:first.challengeId,code:correct}),HttpError);
    f.advance(61_000);
    const second = await f.auth.requestCode(signup,'test-ip');
    f.advance(601_000);
    assert.throws(() => f.auth.verifyCode({challengeId:second.challengeId,code:f.codes.at(-1).code}),HttpError);
  } finally { f.db.close(); }
});

test('resending invalidates the older challenge and login preserves the account', async () => {
  const f = fixture();
  try {
    const first = await f.auth.requestCode(signup,'test-ip');
    const oldCode = f.codes.at(-1).code;
    f.advance(61_000);
    const second = await f.auth.requestCode(signup,'test-ip');
    assert.throws(() => f.auth.verifyCode({challengeId:first.challengeId,code:oldCode}),HttpError);
    const registered = f.auth.verifyCode({challengeId:second.challengeId,code:f.codes.at(-1).code});
    f.advance(61_000);
    const login = await f.auth.requestCode({purpose:'login',password:'Example passphrase 123',email:signup.email},'test-ip');
    const signedIn = f.auth.verifyCode({challengeId:login.challengeId,code:f.codes.at(-1).code});
    assert.equal(signedIn.user.id,registered.user.id);
    assert.equal(f.db.prepare('SELECT COUNT(*) AS n FROM users').get().n,1);
    f.advance(8*86_400_000);
    assert.equal(f.auth.authenticate({headers:{authorization:'Bearer '+signedIn.token}}),null);
  } finally { f.db.close(); }
});

test('unknown login does not create accounts or disclose membership', async () => {
  const f = fixture();
  try {
    const challenge = await f.auth.requestCode({purpose:'reset',email:'unknown@example.test'},'test-ip');
    assert.ok(challenge.challengeId);
    assert.equal(f.codes.length,0);
    assert.equal(f.db.prepare('SELECT COUNT(*) AS n FROM users').get().n,0);
  } finally { f.db.close(); }
});

test('unconfigured or failed SMTP is reported honestly', async () => {
  const f = fixture();
  try {
    f.auth.sendCode = null;
    await assert.rejects(f.auth.requestCode(signup),error => error.status === 503);
    f.auth.sendCode = async () => { throw new Error('private SMTP password detail'); };
    await assert.rejects(f.auth.requestCode(signup),error => error.status === 503 && !error.message.includes('password'));
    assert.equal(f.db.prepare('SELECT consumed FROM challenges').get().consumed,1);
  } finally { f.db.close(); }
});
