import { existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { once } from 'node:events';
import { createPlannerServer, projectRoot } from './index.mjs';
import { AuthService, openAccountDatabase } from './auth.mjs';
import { PlannerStore } from './planner-store.mjs';

if (existsSync(resolve(projectRoot,'.env'))) process.loadEnvFile(resolve(projectRoot,'.env'));
if (!process.env.GEMINI_API_KEY) throw new Error('Set GEMINI_API_KEY in .env first.');
const db = openAccountDatabase(':memory:');
let code;
const auth = new AuthService({db,secret:'one-time-integration-test-secret',sendCode:async value => { code=value.code; }});
const challenge = await auth.requestCode({purpose:'register',password:'Example passphrase 123',name:'Integration Test',email:'integration@example.test'},'test');
const session = auth.verifyCode({challengeId:challenge.challengeId,code});
const server = createPlannerServer({auth,plannerStore:new PlannerStore(db),apiKey:process.env.GEMINI_API_KEY,
  model:process.env.GEMINI_MODEL || 'gemini-3.5-flash-lite'});
server.listen(0,'127.0.0.1'); await once(server,'listening');
try {
  const response = await fetch('http://127.0.0.1:'+server.address().port+'/api/gemini',{
    method:'POST',headers:{'Content-Type':'application/json',Authorization:'Bearer '+session.token},
    body:JSON.stringify({contents:[{parts:[{text:JSON.stringify({
      date:'2026-11-23',start_time:'9:00 AM',break_count:1,break_minutes:5,
      tasks:[{input_index:0,title:'Review study notes',duration_minutes:30,completed:false}],
    })}]}]}),
  });
  const data = await response.json();
  if (!response.ok) { console.error('Live Gemini check failed. HTTP '+response.status+': '+data.error); process.exitCode=1; }
  else {
    const tasks = JSON.parse(data.candidates[0].content.parts.map(p=>p.text).join('')).tasks;
    if (tasks.length !== 1 || tasks[0].input_index !== 0 || tasks[0].duration_minutes !== 30) throw new Error('Invalid generated schedule.');
    console.log('Live Gemini generation passed through the authenticated planning server.');
  }
} finally { server.closeAllConnections(); await new Promise(resolve=>server.close(resolve)); db.close(); }
