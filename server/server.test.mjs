import { AuthService, openAccountDatabase } from './auth.mjs';
import { PlannerStore } from './planner-store.mjs';
import test from 'node:test';
import assert from 'node:assert/strict';
import { once } from 'node:events';
import { createPlannerServer } from './index.mjs';
import { resolve } from 'node:path';

const body = () => ({contents:[{parts:[{text: JSON.stringify({
  date:'2026-11-23',start_time:'9:00 AM',break_count:1,break_minutes:5,
  tasks:[{input_index:0,title:'Review notes',duration_minutes:0,completed:false}],
})}]}]});
const reply = {candidates:[{finishReason:'STOP',content:{parts:[{text:'{"tasks":[{"input_index":0,"duration_minutes":25}]}'}]}}]};
const tokens = new Map();
async function withServer(options, callback) {
  const db = openAccountDatabase(':memory:');
  let code;
  const auth = new AuthService({db,secret:'test-fixture-only-secret',sendCode:async value => { code = value.code; }});
  const challenge = await auth.requestCode({purpose:'register',password:'Example passphrase 123',name:'Test User',email:'test@example.test'},'test-ip');
  const session = auth.verifyCode({challengeId:challenge.challengeId,code});
  const server = createPlannerServer({...options,auth,plannerStore:new PlannerStore(db)});
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const url = 'http://127.0.0.1:' + server.address().port;
  tokens.set(url,session.token);
  try { await callback(url); }
  finally { tokens.delete(url); server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); db.close(); }
}
const post = (url, value = body(), headers = {}) => fetch(url + '/api/gemini', {
  method:'POST',headers:{'Content-Type':'application/json',Authorization:'Bearer '+tokens.get(url),...headers},body:JSON.stringify(value),
});

test('server injects its own key/model and strips client instructions and metadata', async () => {
  await withServer({apiKey:'server-only-secret',model:'test-model',fetchImpl:async (url, options) => {
    assert.equal(options.headers['x-goog-api-key'], 'server-only-secret');
    assert.match(url, /models\/test-model:generateContent$/);
    const request = JSON.parse(options.body);
    assert.notEqual(request.systemInstruction, 'attacker instruction');
    return new Response(JSON.stringify({...reply, privateMetadata:'not-for-client'}));
  }}, async url => {
    const request = body(); request.systemInstruction = 'attacker instruction';
    const response = await post(url, request);
    assert.equal(response.status, 200);
    const text = await response.text();
    assert.ok(!text.includes('server-only-secret'));
    assert.ok(!text.includes('not-for-client'));
    assert.deepEqual(JSON.parse(text), reply);
  });
});

test('missing server key gives a useful error without calling Google', async () => {
  await withServer({fetchImpl:()=>{ throw new Error('must not call'); }}, async url => {
    assert.equal((await post(url)).status, 503);
    assert.deepEqual(await (await fetch(url + '/api/health')).json(), {configured:false,emailConfigured:true,authRequired:true});
  });
});

test('invalid bodies and disallowed origins do not reach Gemini', async () => {
  let calls = 0;
  await withServer({apiKey:'secret',fetchImpl:async()=>{ calls++; return new Response('{}'); }}, async url => {
    assert.equal((await post(url, {})).status, 400);
    assert.equal((await post(url, body(), {Origin:'https://untrusted.example'})).status, 403);
    const invalid = body(); invalid.contents[0].parts[0].text = JSON.stringify({tasks:[]});
    assert.equal((await post(url, invalid)).status, 400);
    assert.equal(calls, 0);
  });
});

test('rate limits and upstream errors do not leak provider details', async () => {
  await withServer({apiKey:'secret',rateLimit:1,fetchImpl:async()=>new Response('secret provider error',{status:403})}, async url => {
    const response = await post(url);
    assert.equal(response.status, 502);
    assert.ok(!(await response.text()).includes('secret'));
    assert.equal((await post(url)).status, 429);
  });
});

test('static website cannot expose root .env or server source', async () => {
  await withServer({}, async url => {
    for (const path of ['/.env','/server/index.mjs','/%2e%2e/.env','/config/client.json']) {
      assert.equal((await fetch(url + path)).status, 404, path);
    }
  });
});


test('unauthenticated clients cannot generate or read account data', async () => {
  await withServer({apiKey:'secret'},async url => {
    assert.equal((await fetch(url+'/api/gemini',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body())})).status,401);
    assert.equal((await fetch(url+'/api/plans/2026-11-23')).status,401);
  });
});

test('web files and the retiring worker cannot retain stale UI in HTTP caches', async () => {
  await withServer({webRoot:resolve('web')},async url => {
    for (const path of ['/','/flutter_bootstrap.js','/flutter_service_worker.js']) {
      const response = await fetch(url + path);
      assert.equal(response.status,200);
      assert.equal(response.headers.get('cache-control'),'no-store');
    }
    const worker = await (await fetch(url+'/flutter_service_worker.js')).text();
    assert.ok(worker.includes('registration.unregister'));
    assert.ok(!worker.includes('RESOURCES ='));
  });
});
