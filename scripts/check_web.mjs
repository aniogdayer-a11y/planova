import { spawn } from 'node:child_process';
import { mkdir, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { once } from 'node:events';
import { AuthService, openAccountDatabase } from '../server/auth.mjs';
import { PlannerStore } from '../server/planner-store.mjs';
import { createPlannerServer } from '../server/index.mjs';
import { createRequire } from 'node:module';
const sharp = createRequire(new URL('../server/package.json',import.meta.url))('sharp');

// Isolated browser fixture: no production account, SMTP message or billable call.
const db = openAccountDatabase(':memory:');
let verificationCode;
let fixtureNow=Date.now();
const auth = new AuthService({db,secret:'browser-fixture-secret-only',now:()=>fixtureNow,sendCode:async ({code}) => verificationCode=code});
const challenge = await auth.requestCode({email:'browser@example.test',name:'Dayer',purpose:'register',password:'Example passphrase 123'});
const account = auth.verifyCode({challengeId:challenge.challengeId,code:verificationCode});
fixtureNow+=61_000;
const store = new PlannerStore(db);
const today = new Intl.DateTimeFormat('en-CA',{year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
store.savePlan(account.user.id,today,{start_time:'9:00 AM',has_breaks:1,break_count:1,break_duration_minutes:10,
  tasks:[{title:'Review project notes',duration_minutes:30},{title:'Prepare presentation',duration_minutes:45}]},0);
const origins=[];
const server=createPlannerServer({auth,plannerStore:store,apiKey:'fixture-only',origins,
  fetchImpl:async (_url,options) => {
    const input=JSON.parse(JSON.parse(options.body).contents[0].parts[0].text);
    return new Response(JSON.stringify({candidates:[{finishReason:'STOP',content:{parts:[{text:JSON.stringify({
      tasks:input.tasks.map(t => ({input_index:t.input_index,duration_minutes:t.duration_minutes||30}))})}]}}]}));
  }});
server.listen(0,'127.0.0.1'); await once(server,'listening');
const base='http://127.0.0.1:'+server.address().port;
origins.push(base);

const chromePath = process.env.PLANNER_CHROME || 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const chrome = spawn(chromePath, [
  '--headless=new','--disable-gpu','--no-first-run','--no-default-browser-check',
  '--remote-debugging-port=0','--window-size=390,844',
  '--user-data-dir=' + resolve('build/web-smoke-' + Date.now()), 'about:blank',
], {windowsHide:true, stdio:['ignore','ignore','pipe']});
let ws;
try {
  const url = await new Promise((resolve, reject) => {
    let text = '';
    const timer = setTimeout(() => reject(new Error('Chrome startup timed out.')), 15000);
    chrome.once('error', reject);
    chrome.stderr.on('data', chunk => {
      text += chunk;
      const match = text.match(/DevTools listening on (ws:\/\/[^\s]+)/);
      if (match) { clearTimeout(timer); resolve(match[1]); }
    });
  });
  ws = new WebSocket(url);
  await new Promise((resolve, reject) => { ws.onopen = resolve; ws.onerror = reject; });
  let next = 0;
  const pending = new Map();
  const errors = [];
  let chooserNode;
  ws.onmessage = event => {
    const data = JSON.parse(event.data);
    if(data.method==='Page.fileChooserOpened')chooserNode=data.params.backendNodeId;
    if(data.method === 'Runtime.consoleAPICalled' && data.params.type === 'error') errors.push(data.params.args.map(a=>a.value||a.description||'').join(' '));
    if (data.method === 'Runtime.exceptionThrown') errors.push(data.params.exceptionDetails.text + ': ' + (data.params.exceptionDetails.exception?.description || ''));
    if (pending.has(data.id)) {
      const {resolve, reject, timer} = pending.get(data.id); clearTimeout(timer); pending.delete(data.id);
      if (data.error) reject(new Error(data.error.message)); else resolve(data.result);
    }
  };
  const send = (method, params = {}, sessionId) => new Promise((resolve, reject) => {
    const id = ++next;
    const timer = setTimeout(() => { pending.delete(id); reject(new Error('CDP timed out: ' + method)); }, 20000);
    pending.set(id, {resolve,reject,timer});
    ws.send(JSON.stringify({id,method,params,...(sessionId ? {sessionId}: {})}));
  });
  const {targetId} = await send('Target.createTarget', {url:'about:blank'});
  const {sessionId} = await send('Target.attachToTarget', {targetId,flatten:true});
  await send('Runtime.enable', {}, sessionId);
  await send('Page.enable', {}, sessionId);
  await send('Page.setInterceptFileChooserDialog',{enabled:true},sessionId);
  const evaluate = async expression => (await send('Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true},sessionId)).result.value;
  const allElements = `const roots=[document],elements=[];for(let i=0;i<roots.length;i++)for(const e of roots[i].querySelectorAll('*')){elements.push(e);if(e.shadowRoot)roots.push(e.shadowRoot);}`;
  const readText = () => evaluate(`(() => {${allElements}let text='';for(const e of elements){if(e.tagName.toLowerCase()==='flt-semantics-placeholder')e.click();text+=' '+(e.getAttribute('aria-label')||'')+' '+(e.textContent||'');}return text;})()`);
  const waitText = async expected => {
    let text='';
    for(let i=0;i<40;i++){
      await new Promise(r=>setTimeout(r,500));text=await readText();
      if(text.includes(expected))return text;
      if(errors.length)throw new Error(errors.join('\n'));
    }
    await screenshot('web-failure');
    throw new Error('Browser did not show: '+expected);
  };
  const size = async (width,height) => {await send('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:width<720},sessionId);await new Promise(r=>setTimeout(r,800));};
  const screenshot = async name => {
    await new Promise(r=>setTimeout(r,700));
    const shot=await send('Page.captureScreenshot',{format:'png'},sessionId);
    await writeFile('build/previews/'+name+'.png',Buffer.from(shot.data,'base64'));
  };
  const clickLabel = async (label,role='button') => {
    const point=await evaluate(`(() => {${allElements}for(const e of elements){if(e.getAttribute('role')===${JSON.stringify(role)} && ((e.getAttribute('aria-label')||e.textContent||'').trim()===${JSON.stringify(label)})){const r=e.getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2};}}return null;})()`);
    if(!point)throw new Error('Button not found: '+label);
    await send('Input.dispatchMouseEvent',{type:'mouseMoved',...point},sessionId);
    await send('Input.dispatchMouseEvent',{type:'mousePressed',button:'left',clickCount:1,...point},sessionId);
    await send('Input.dispatchMouseEvent',{type:'mouseReleased',button:'left',clickCount:1,...point},sessionId);
  };
  const fill = async (label,value) => {
    await new Promise(r=>setTimeout(r,500));
    const point=await evaluate(`(() => {${allElements}const label=${JSON.stringify(label)};const matches=elements.filter(e=>e.tagName==='INPUT'||e.getAttribute('role')==='textbox').map(e=>{const name=e.getAttribute('aria-label')||'';return {e,rank:name===label?3:name.startsWith(label+'\\n')?2:name.split('\\n').includes(label)?1:0};}).filter(x=>x.rank).sort((a,b)=>b.rank-a.rank);for(const {e} of matches){const r=e.getBoundingClientRect();if(r.width&&r.height){e.focus();return {x:r.x+r.width/2,y:r.y+r.height/2};}}return null;})()`);
    if(!point){await screenshot('web-failure');const fields=await evaluate(`(() => {${allElements}return elements.filter(e=>e.tagName==='INPUT'||e.getAttribute('role')==='textbox').map(e=>({tag:e.tagName,label:e.getAttribute('aria-label'),labelledby:e.getAttribute('aria-labelledby'),placeholder:e.getAttribute('placeholder'),parent:e.parentElement?.getAttribute('aria-label')}));})()`);throw new Error('Text field not found: '+label+' '+JSON.stringify(fields));}
    await send('Input.dispatchKeyEvent',{type:'rawKeyDown',key:'a',code:'KeyA',windowsVirtualKeyCode:65,modifiers:2},sessionId);
    await send('Input.dispatchKeyEvent',{type:'keyUp',key:'a',code:'KeyA',windowsVirtualKeyCode:65,modifiers:2},sessionId);
    await send('Input.insertText',{text:value},sessionId);
    await new Promise(r=>setTimeout(r,200));
  };
  const signIn = async password => {
    await fill('Email address','browser@example.test');
    await fill('Password',password);
    await clickLabel('Sign in');await waitText('Check your email');
    await fill('Verification code',verificationCode);
    await clickLabel('Verify and sign in');await waitText('Overview');
  };
  await mkdir('build/previews',{recursive:true});
  await size(1440,1000);
  await send('Page.navigate',{url:base},sessionId);
  await waitText('Welcome back');
  await screenshot('web-login');
  await signIn('Example passphrase 123');
  await waitText('Review project notes');
  await waitText('You can download Planova as an APK.');
  await waitText('Download APK');
  if(await evaluate('document.title')!=='Planova')throw new Error('Website title is not Planova.');
  if(await evaluate('navigator.serviceWorker.getRegistrations().then(r => r.length)')!==0)throw new Error('A stale service worker is still registered.');
  if((await readText()).includes('A LITTLE STRUCTURE')||(await readText()).includes('Refresh plans')||(await readText()).includes('Refresh schedule'))throw new Error('Removed header content is still visible.');
  await screenshot('web-desktop');
  await clickLabel('Feedback');await waitText('Community Feedback');
  await waitText('Share your thoughts about Planova...');
  await waitText("I'm willing to share my feedback with other Planova users.");
  await waitText('Submit Feedback');
  await screenshot('web-feedback');
  await clickLabel('Home');await waitText('Overview');
  await size(1024,1000);await waitText('Overview');await screenshot('web-tablet');
  for(const width of [320,390,820]) {
    await size(width,844);await waitText('Hi, Dayer.');
    const position=await evaluate(`(() => {${allElements}return elements.filter(e=>e.getAttribute('role')==='button'&&(e.getAttribute('aria-label')||e.textContent||'').trim()==='Home').map(e=>{const r=e.getBoundingClientRect();return {y:r.y,height:r.height};}).find(r=>r.height>0);})()`);
    if(!position||position.y<700)throw new Error('Mobile Home navigation is not at the bottom at width '+width);
    await clickLabel('Tasks');await waitText('Edit plan');
    await clickLabel('Feedback');await waitText('Community Feedback');
    await clickLabel('Profile');await waitText('Change photo');
    await clickLabel('Settings');await waitText('24-hour time');
    await clickLabel('Home');await waitText('Hi, Dayer.');
    await screenshot('web-mobile-nav-'+width);
  }
  await size(390,844);await waitText('Hi, Dayer.');await screenshot('web-phone');
  await size(1440,1000);await waitText('Overview');
  await clickLabel('Edit this day');await waitText('Generate plan');
  if((await readText()).includes('Use Gemini'))throw new Error('Provider switch is still visible.');
  await screenshot('web-plan');
  await clickLabel('Generate plan');await waitText('Edit plan');await screenshot('web-tasks');
  if((await readText()).includes('Save plan'))throw new Error('Generated plan still needs a manual save.');
  if(store.getPlan(account.user.id,today).revision!==2)throw new Error('Generated plan was not saved.');
  await clickLabel('Home');await waitText('Overview');
  await waitText('Review project notes');
  await clickLabel('Tasks');await waitText('Edit plan');
  await clickLabel('Profile');await waitText('Change photo');
  const photoPath=resolve('build/previews/avatar-fixture.png');
  await writeFile(photoPath,await sharp({create:{width:64,height:64,channels:3,background:'#a79e8e'}}).png().toBuffer());
  await clickLabel('Change photo');
  for(let i=0;i<30&&!chooserNode;i++)await new Promise(r=>setTimeout(r,100));
  if(chooserNode){await send('DOM.setFileInputFiles',{files:[photoPath],backendNodeId:chooserNode},sessionId);}
  else {
    const picked=await send('Runtime.evaluate',{expression:"document.querySelector('input[type=file]')",returnByValue:false},sessionId);
    if(!picked.result.objectId){await screenshot('web-failure');throw new Error('The photo input did not open.');}
    await send('DOM.setFileInputFiles',{files:[photoPath],objectId:picked.result.objectId},sessionId);
  }
  await waitText('Remove photo');
  if(!store.profile(account.user,today).avatar_url.startsWith('data:image/jpeg;base64,'))throw new Error('The profile photo was not saved.');
  await screenshot('web-profile');
  const uploadedPhoto=store.profile(account.user,today).avatar_url;
  await clickLabel('Customize avatar');await waitText('Save avatar');
  await fill('Initials','PV');await clickLabel('Forest');
  await screenshot('web-avatar-editor');
  await clickLabel('Save avatar');
  for(let i=0;i<40&&store.profile(account.user,today).avatar_url===uploadedPhoto;i++)await new Promise(r=>setTimeout(r,250));
  if(store.profile(account.user,today).avatar_url===uploadedPhoto)throw new Error('Customized avatar was not saved.');
  await screenshot('web-custom-avatar');
  const initialsPhoto=store.profile(account.user,today).avatar_url;
  await clickLabel('Customize avatar');await waitText('Save avatar');
  await clickLabel('Smile');await clickLabel('Lavender');await clickLabel('Save avatar');
  for(let i=0;i<40&&store.profile(account.user,today).avatar_url===initialsPhoto;i++)await new Promise(r=>setTimeout(r,250));
  if(store.profile(account.user,today).avatar_url===initialsPhoto)throw new Error('Icon avatar was not saved.');
  await size(390,844);await waitText('Customize avatar');
  await clickLabel('Customize avatar');await waitText('Save avatar');
  await screenshot('web-avatar-phone');await clickLabel('Cancel');
  await size(1440,1000);await waitText('Reset password');
  fixtureNow+=61_000;
  await clickLabel('Reset password');await waitText('Forgot password');
  await clickLabel('Send reset code');await waitText('Reset your password');
  await fill('Verification code',verificationCode);
  await fill('New password','My replacement passphrase 456');
  await fill('Confirm password','My replacement passphrase 456');
  await screenshot('web-reset-password');
  await clickLabel('Reset password');await waitText('Welcome back');
  if(auth.authenticate({headers:{authorization:'Bearer '+account.token}}))throw new Error('Password reset did not revoke the old session.');
  fixtureNow+=61_000;
  await signIn('My replacement passphrase 456');
  await clickLabel('Sign out');await waitText('Welcome back');
  if((await readText()).includes('Review project notes'))throw new Error('Private planner is visible after logout.');
  if(errors.length)throw new Error(errors.join('\n'));
  console.log('Browser checks passed: password + OTP sign-in, desktop/tablet/phone, mobile bottom navigation at 320/390/820px, automatic plan/task saving, avatar upload and customization, password reset, new-password sign-in and logout.');
  ws.send(JSON.stringify({id: ++next, method: 'Browser.close'}));
} finally {
  ws?.close();
  chrome.kill();
  server.closeAllConnections(); await new Promise(resolve=>server.close(resolve)); db.close();
}
