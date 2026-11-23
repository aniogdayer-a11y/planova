import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { DatabaseSync } from 'node:sqlite';
import { mkdirSync, existsSync, unlinkSync } from 'node:fs';
import { resolve } from 'node:path';
import { AuthService, openAccountDatabase, hashToken } from './auth.mjs';

const password='My private passphrase 123';
function fixture(db=openAccountDatabase(':memory:')) {
  const messages=[];
  let now=Date.now();
  const auth=new AuthService({db,secret:'password-test-secret-only',now:()=>now,
    sendCode:async message=>messages.push(message)});
  const request=(purpose,extra={})=>auth.requestCode({purpose,email:'owner@example.test',name:'Owner',password,...extra},'test-ip');
  const verify=challenge=>auth.verifyCode({challengeId:challenge.challengeId,code:messages.at(-1).code});
  return {db,auth,messages,request,verify,advance:()=>now+=61_000};
}
const headers=token=>({headers:{authorization:'Bearer '+token}});

test('password is salted and hashed; login requires the correct password and a fresh OTP',async()=>{
  const f=fixture();
  try {
    await assert.rejects(f.request('register',{password:'short'}),error=>error.status===400);
    const challenge=await f.request('register');
    const pending=f.db.prepare('SELECT password_hash FROM challenges').get().password_hash;
    assert.match(pending,/^scrypt\$32768\$8\$3\$/);
    assert.ok(!pending.includes(password));
    const account=f.verify(challenge);
    assert.equal(f.db.prepare('SELECT password_hash FROM users').get().password_hash,pending);
    assert.equal(account.user.password_hash,undefined);
    f.advance();
    const sent=f.messages.length;
    await assert.rejects(f.request('login',{password:'wrong password'}),error=>error.status===401);
    await assert.rejects(f.request('login',{email:'missing@example.test'}),error=>error.status===401 && error.message==='Email or password is incorrect.');
    assert.equal(f.messages.length,sent);
    const login=await f.request('login');
    assert.equal(f.db.prepare('SELECT COUNT(*) AS n FROM sessions').get().n,1);
    const second=f.verify(login);
    assert.equal(second.user.id,account.user.id);
    assert.notEqual(second.token,account.token);
  } finally {f.db.close();}
});

test('password reset is single-use, revokes sessions and pending codes, and requires normal login',async()=>{
  const f=fixture();
  try {
    const account=f.verify(await f.request('register'));
    f.advance();
    const pending=await f.request('login');
    const oldCode=f.messages.at(-1).code;
    f.advance();
    const reset=await f.request('reset');
    const resetCode=f.messages.at(-1).code;
    assert.throws(()=>f.auth.verifyCode({challengeId:reset.challengeId,code:resetCode}));
    await assert.rejects(f.auth.resetPassword({challengeId:reset.challengeId,code:resetCode,password:'short'}),error=>error.status===400);
    assert.equal(f.auth.authenticate(headers(account.token)).id,account.user.id);
    const newPassword='My replacement passphrase 456';
    assert.deepEqual(await f.auth.resetPassword({challengeId:reset.challengeId,code:resetCode,password:newPassword}),
      {ok:true,message:'Password updated. Sign in with your new password.'});
    assert.equal(f.messages.at(-1).purpose,'password-changed');
    assert.equal(f.messages.at(-1).password,undefined);
    assert.equal(f.auth.authenticate(headers(account.token)),null);
    assert.throws(()=>f.auth.verifyCode({challengeId:pending.challengeId,code:oldCode}));
    await assert.rejects(f.auth.resetPassword({challengeId:reset.challengeId,code:resetCode,password:newPassword}),error=>error.status===400);
    f.advance();
    await assert.rejects(f.request('login'),error=>error.status===401);
    const login=f.verify(await f.request('login',{password:newPassword}));
    assert.equal(login.user.id,account.user.id);
  } finally {f.db.close();}
});

test('unknown reset and duplicate registration do not disclose or overwrite accounts',async()=>{
  const f=fixture();
  try {
    const account=f.verify(await f.request('register'));
    const stored=f.db.prepare('SELECT password_hash FROM users').get().password_hash;
    f.advance();
    const count=f.messages.length;
    const duplicate=await f.request('register',{password:'An attacker password 456'});
    assert.ok(duplicate.challengeId);
    assert.equal(f.messages.length,count);
    assert.equal(f.db.prepare('SELECT password_hash FROM users').get().password_hash,stored);
    const unknown=await f.request('reset',{email:'missing@example.test'});
    assert.equal(f.messages.length,count);
    assert.equal(unknown.message,duplicate.message);
    await assert.rejects(f.auth.resetPassword({challengeId:unknown.challengeId,code:'000000',password}),error=>error.status===400);
    assert.equal(f.auth.authenticate(headers(account.token)).id,account.user.id);
  } finally {f.db.close();}
});

test('reset expiry, attempt limits and credential throttling are enforced',async()=>{
  const f=fixture();
  try {
    f.verify(await f.request('register'));f.advance();
    const reset=await f.request('reset');
    const correct=f.messages.at(-1).code;
    const wrong=((Number(correct)+1)%1_000_000).toString().padStart(6,'0');
    for(let i=0;i<5;i++) await assert.rejects(f.auth.resetPassword({challengeId:reset.challengeId,code:wrong,password}),error=>error.status===400);
    await assert.rejects(f.auth.resetPassword({challengeId:reset.challengeId,code:correct,password}),error=>error.status===400);
    for(let i=0;i<11;i++)f.advance();
    const expired=await f.request('reset');const code=f.messages.at(-1).code;
    for(let i=0;i<11;i++)f.advance();
    await assert.rejects(f.auth.resetPassword({challengeId:expired.challengeId,code,password}),error=>error.status===400);
    for(let i=0;i<10;i++)await assert.rejects(f.request('login',{password:'wrong'}),error=>error.status===401);
    await assert.rejects(f.request('login'),error=>error.status===429);
  } finally {f.db.close();}
});

test('legacy OTP accounts retain identity and data while setting their first password by email',async()=>{
  const folder=resolve('build');mkdirSync(folder,{recursive:true});
  const file=resolve(folder,'account-migration-'+randomUUID()+'.db');
  let db;
  try {
    db=new DatabaseSync(file);
    db.exec('CREATE TABLE users(id TEXT PRIMARY KEY,email TEXT UNIQUE,name TEXT,created_at INTEGER);');
    db.prepare('INSERT INTO users VALUES (?,?,?,?)').run('legacy-id','owner@example.test','Original owner',Date.now());
    db.close();db=openAccountDatabase(file);
    const f=fixture(db);
    db.prepare('INSERT INTO sessions VALUES (?,?,?,?)').run(hashToken('old-token'),'legacy-id',Date.now()+86_400_000,Date.now());
    await assert.rejects(f.request('login'),error=>error.status===401);
    const reset=await f.request('reset');
    await f.auth.resetPassword({challengeId:reset.challengeId,code:f.messages.at(-1).code,password});
    assert.equal(f.auth.authenticate(headers('old-token')),null);
    f.advance();
    const account=f.verify(await f.request('login'));
    assert.equal(account.user.id,'legacy-id');
    assert.equal(account.user.name,'Original owner');
  } finally {
    db?.close();
    for(const suffix of ['','-wal','-shm'])if(existsSync(file+suffix))unlinkSync(file+suffix);
  }
});
