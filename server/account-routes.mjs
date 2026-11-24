import { HttpError } from './auth.mjs';
import { prepareAvatar } from './avatar.mjs';

export async function readJson(req, limit = 32_768) {
  if (!req.headers['content-type']?.startsWith('application/json')) throw new HttpError(415,'Use JSON.');
  const chunks = []; let size = 0;
  for await (const chunk of req) {
    size += chunk.length;
    if (size > limit) throw new HttpError(413,'Request too large.');
    chunks.push(chunk);
  }
  try { return JSON.parse(Buffer.concat(chunks).toString('utf8')); }
  catch { throw new HttpError(400,'Invalid JSON.'); }
}
export async function accountRoutes({req,res,pathname,url,json,auth,store,cookieSecure}) {
  const isAuth = pathname.startsWith('/api/auth/');
  const isData = /^\/api\/(plans|tasks|slots|profile|settings|activity|feedback)(\/|$)/.test(pathname);
  if (!isAuth && !isData) return false;
  try {
    if (!auth) throw new HttpError(503,'Account service is unavailable.');
    const cookie = (token,maxAge) => res.setHeader('Set-Cookie',
      'planner_session=' + token + '; HttpOnly; SameSite=Strict; Path=/; Max-Age=' + maxAge + (cookieSecure ? '; Secure' : ''));
    if (pathname === '/api/auth/request-code' && req.method === 'POST') {
      json(200,await auth.requestCode(await readJson(req),req.socket.remoteAddress)); return true;
    }
    if (pathname === '/api/auth/verify' && req.method === 'POST') {
      const session = auth.verifyCode(await readJson(req));
      cookie(session.token,7*86400);
      json(200,{user:session.user,expiresAt:session.expiresAt,
        ...(req.headers['x-planner-client'] === 'native' ? {token:session.token} : {})});
      return true;
    }
    if (pathname === '/api/auth/reset-password' && req.method === 'POST') {
      const result = await auth.resetPassword(await readJson(req));
      cookie('',0);
      json(200,result); return true;
    }
    if (pathname === '/api/auth/logout' && req.method === 'POST') {
      await readJson(req); auth.logout(req); cookie('',0); json(200,{ok:true}); return true;
    }
    const user = auth.authenticate(req);
    if (!user) throw new HttpError(401,'Please sign in to continue.');
    if (pathname === '/api/auth/me' && req.method === 'GET') { json(200,{user}); return true; }
    if (!store) throw new HttpError(503,'Planner storage is unavailable.');
    const today = url.searchParams.get('today') || new Date().toISOString().slice(0,10);
    if (pathname === '/api/profile/avatar' && req.method === 'PUT') {
      const {image_base64} = await readJson(req,2_850_000);
      const photo = await prepareAvatar(image_base64);
      auth.db.prepare('UPDATE users SET avatar_data = ? WHERE id = ?').run(photo,user.id);
      json(200,{ok:true}); return true;
    }
    if (pathname === '/api/profile') {
      if (req.method === 'GET') json(200,{profile:store.profile(user,today)});
      else if (req.method === 'PUT') {
        const {name} = await readJson(req);
        if (typeof name !== 'string' || name.trim().length < 2 || name.trim().length > 60) throw new HttpError(400,'Enter a name between 2 and 60 characters.');
        auth.db.prepare('UPDATE users SET name = ? WHERE id = ?').run(name.trim(),user.id);
        json(200,{ok:true});
      } else throw new HttpError(405,'Method not allowed.');
      return true;
    }
    if (pathname === '/api/settings') {
      if (req.method === 'GET') json(200,{settings:store.settings(user.id)});
      else if (req.method === 'PUT') {
        const {key,value} = await readJson(req); store.setSetting(user.id,key,value); json(200,{ok:true});
      } else throw new HttpError(405,'Method not allowed.');
      return true;
    }
    if (pathname === '/api/activity' && req.method === 'GET') { json(200,store.activity(user.id,today)); return true; }
    const planMatch = pathname.match(/^\/api\/plans\/(\d{4}-\d{2}-\d{2})$/);
    if (planMatch) {
      if (req.method === 'GET') json(200,store.getPlan(user.id,planMatch[1]));
      else if (req.method === 'PUT') {
        const body = await readJson(req,262144); json(200,store.savePlan(user.id,planMatch[1],body.plan,body.expected_revision));
      } else if (req.method === 'DELETE') {
        const body = await readJson(req); json(200,store.deletePlan(user.id,planMatch[1],body.expected_revision));
      } else throw new HttpError(405,'Method not allowed.');
      return true;
    }
    const toggleMatch = pathname.match(/^\/api\/(tasks|slots)\/(\d+)$/);
    if (toggleMatch && req.method === 'POST') {
      const body = await readJson(req);
      json(200,store.toggle(user.id,toggleMatch[1] === 'tasks' ? 'task':'slot',Number(toggleMatch[2]),
        body.completed,body.expected_revision,body.timezone_offset_minutes));
      return true;
    }
    if (pathname === '/api/feedback') {
      if (req.method === 'GET') json(200, {feedback: store.listFeedback(user.id)});
      else if (req.method === 'POST') {
        const body = await readJson(req);
        json(201, {feedback: store.addFeedback(
          user.id,
          body.content,
          body.category,
          body.recommendation,
          body.visibility,
        )});
      } else throw new HttpError(405, 'Method not allowed.');
      return true;
    }
    const fbLikeMatch = pathname.match(/^\/api\/feedback\/([^\/]+)\/like$/);
    if (fbLikeMatch && req.method === 'POST') {
      json(200, store.toggleFeedbackLike(user.id, fbLikeMatch[1]));
      return true;
    }
    const fbItemMatch = pathname.match(/^\/api\/feedback\/([^\/]+)$/);
    if (fbItemMatch) {
      if (req.method === 'PUT') {
        const body = await readJson(req);
        json(200, {feedback: store.updateFeedback(
          user.id,
          fbItemMatch[1],
          body.content,
          body.category,
          body.recommendation,
          body.visibility,
        )});
      } else if (req.method === 'DELETE') {
        json(200, store.deleteFeedback(user.id, fbItemMatch[1]));
      } else throw new HttpError(405, 'Method not allowed.');
      return true;
    }
    throw new HttpError(404,'Not found.');
  } catch (error) {
    json(error instanceof HttpError ? error.status : 500,
      {error:error instanceof HttpError ? error.message : 'The account service is temporarily unavailable.'});
    return true;
  }
}
