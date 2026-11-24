import test from 'node:test';
import assert from 'node:assert/strict';
import { once } from 'node:events';
import { AuthService, openAccountDatabase } from './auth.mjs';
import { PlannerStore } from './planner-store.mjs';
import { createPlannerServer } from './index.mjs';
import sharp from 'sharp';

async function fixture(callback) {
  const db = openAccountDatabase(':memory:');
  const codes = new Map();
  const registered = new Set();
  const started = Date.now();
  let now = started;
  const auth = new AuthService({db,secret:'http-test-secret-only',now:() => now,
    sendCode:async ({email,code}) => codes.set(email,code)});
  const server = createPlannerServer({auth,plannerStore:new PlannerStore(db),apiKey:'fake-key'});
  server.listen(0,'127.0.0.1'); await once(server,'listening');
  const base = 'http://127.0.0.1:'+server.address().port;
  const request = (path,{method='GET',data,token,cookie,native=true} = {}) => fetch(base+path,{
    method,headers:{...(data ? {'Content-Type':'application/json'}:{}),
      ...(native ? {'X-Planner-Client':'native'}:{}),...(token ? {Authorization:'Bearer '+token}:{}),...(cookie ? {Cookie:cookie}:{})},
    ...(data ? {body:JSON.stringify(data)}:{}),
  });
  const signIn = async (email,native=true) => {
    const sent = await request('/api/auth/request-code',{method:'POST',data:{email,name:'Test Person',purpose:registered.has(email)?'login':'register',password:'Example passphrase 123'},native});
    assert.equal(sent.status,200);
    const challenge = await sent.json();
    const response=await request('/api/auth/verify',{method:'POST',data:{challengeId:challenge.challengeId,code:codes.get(email)},native});
    if(response.ok)registered.add(email);
    return response;
  };
  try { await callback({request,signIn,codes,advance:ms => now += ms}); }
  finally { server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); db.close(); }
}

test('native account login, shared plans, settings and account isolation work over HTTP', async () => fixture(async ({request,signIn,advance}) => {
  const first = await (await signIn('first@example.test')).json();
  assert.ok(first.token);
  const data = {expected_revision:0,plan:{start_time:'9:00 AM',has_breaks:1,break_count:1,break_duration_minutes:5,
    tasks:[{title:'My private task',duration_minutes:50}]}};
  assert.equal((await request('/api/plans/2026-11-23',{method:'PUT',data,token:first.token})).status,200);
  advance(61_000);
  const secondDevice = await (await signIn('first@example.test')).json();
  const loaded = await (await request('/api/plans/2026-11-23',{token:secondDevice.token})).json();
  assert.equal(loaded.plan.tasks[0].title,'My private task');
  assert.equal(first.user.id,secondDevice.user.id);
  const other = await (await signIn('other@example.test')).json();
  assert.equal((await (await request('/api/plans/2026-11-23',{token:other.token})).json()).plan,null);
  assert.equal((await request('/api/tasks/'+loaded.plan.tasks[0].id,{method:'POST',token:other.token,
    data:{completed:true,expected_revision:1,timezone_offset_minutes:480}})).status,404);
  await request('/api/settings',{method:'PUT',token:first.token,data:{key:'time_format',value:'24-hour'}});
  assert.equal((await (await request('/api/settings',{token:secondDevice.token})).json()).settings.time_format,'24-hour');
}));

test('browser sessions use HttpOnly cookies and logout revokes the session', async () => fixture(async ({request,signIn}) => {
  const response = await signIn('browser@example.test',false);
  const payload = await response.json();
  assert.equal(payload.token,undefined);
  const setCookie = response.headers.get('set-cookie');
  assert.match(setCookie,/HttpOnly/); assert.match(setCookie,/SameSite=Strict/);
  const cookie = setCookie.split(';')[0];
  assert.equal((await request('/api/auth/me',{cookie,native:false})).status,200);
  const logout = await request('/api/auth/logout',{method:'POST',data:{},cookie,native:false});
  assert.equal(logout.status,200);
  assert.match(logout.headers.get('set-cookie'),/Max-Age=0/);
  assert.equal((await request('/api/auth/me',{cookie,native:false})).status,401);
}));

test('avatar upload, replacement and removal sync only to the owning account',async()=>fixture(async({request,signIn})=>{
  const owner=await(await signIn('photo@example.test')).json();
  const other=await(await signIn('different@example.test')).json();
  const photo=await sharp({create:{width:16,height:16,channels:3,background:'#9c88b0'}}).png().toBuffer();
  assert.equal((await request('/api/profile/avatar',{method:'PUT',token:owner.token,data:{image_base64:photo.toString('base64')}})).status,200);
  const profile=await(await request('/api/profile',{token:owner.token})).json();
  assert.ok(profile.profile.avatar_url.startsWith('data:image/jpeg;base64,'));
  assert.equal((await(await request('/api/profile',{token:other.token})).json()).profile.avatar_url,'');
  assert.equal((await request('/api/profile/avatar',{method:'PUT',token:owner.token,data:{image_base64:'https://example.test/a.png'}})).status,400);
  assert.equal((await request('/api/profile/avatar',{method:'PUT',token:owner.token,data:{image_base64:null}})).status,200);
  assert.equal((await(await request('/api/profile',{token:owner.token})).json()).profile.avatar_url,'');
  assert.equal((await request('/api/profile/avatar',{method:'PUT',data:{image_base64:photo.toString('base64')}})).status,401);
}));

test('feedback API persists categories and recommendations and isolates private entries', async () => fixture(async ({request, signIn}) => {
  const owner = await (await signIn('feedback-owner@example.test')).json();
  const other = await (await signIn('feedback-other@example.test')).json();

  const publicResponse = await request('/api/feedback', {
    method: 'POST',
    token: owner.token,
    data: {
      content: 'Please add calendar reminders.',
      category: 'Feature Suggestion',
      recommendation: 'maybe',
      visibility: 'public',
    },
  });
  assert.equal(publicResponse.status, 201);
  const {feedback: shared} = await publicResponse.json();
  assert.equal(shared.category, 'Feature Suggestion');
  assert.equal(shared.recommendation, 'maybe');

  const privateResponse = await request('/api/feedback', {
    method: 'POST',
    token: owner.token,
    data: {
      content: 'A private note.',
      category: 'Bug Report',
      recommendation: 'no',
      visibility: 'private',
    },
  });
  const {feedback: privateItem} = await privateResponse.json();
  const otherFeed = await (await request('/api/feedback', {token: other.token})).json();
  assert.ok(otherFeed.feedback.some(item => item.id === shared.id));
  assert.ok(!otherFeed.feedback.some(item => item.id === privateItem.id));

  assert.equal((await request(`/api/feedback/${privateItem.id}`, {
    method: 'PUT',
    token: other.token,
    data: {content: 'Unauthorized edit.'},
  })).status, 403);
  assert.equal((await request(`/api/feedback/${privateItem.id}`, {
    method: 'DELETE',
    token: other.token,
  })).status, 403);

  const like = await (await request(`/api/feedback/${shared.id}/like`, {
    method: 'POST',
    token: other.token,
  })).json();
  assert.deepEqual(like, {is_liked_by_me: true, likes_count: 1});
  const unlike = await (await request(`/api/feedback/${shared.id}/like`, {
    method: 'POST',
    token: other.token,
  })).json();
  assert.deepEqual(unlike, {is_liked_by_me: false, likes_count: 0});
}));

test('email password reset clears browser cookies and revokes native sessions',async()=>fixture(async({request,signIn,codes,advance})=>{
  const owner=await(await signIn('reset@example.test')).json();
  advance(61_000);
  const response=await request('/api/auth/request-code',{method:'POST',data:{purpose:'reset',email:'reset@example.test'}});
  const challenge=await response.json();
  const reset=await request('/api/auth/reset-password',{method:'POST',native:false,
    data:{challengeId:challenge.challengeId,code:codes.get('reset@example.test'),password:'New private passphrase 456'}});
  assert.equal(reset.status,200);
  assert.match(reset.headers.get('set-cookie'),/Max-Age=0/);
  assert.equal((await reset.json()).token,undefined);
  assert.equal((await request('/api/auth/me',{token:owner.token})).status,401);
  advance(61_000);
  assert.equal((await request('/api/auth/request-code',{method:'POST',data:{purpose:'login',email:'reset@example.test',password:'Example passphrase 123'}})).status,401);
  assert.equal((await request('/api/auth/request-code',{method:'POST',data:{purpose:'login',email:'reset@example.test',password:'New private passphrase 456'}})).status,200);
}));
