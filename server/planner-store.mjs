import { HttpError } from './auth.mjs';

const datePattern = /^\d{4}-\d{2}-\d{2}$/;
export function validDate(date) {
  let valid = false;
  try { valid = typeof date === 'string' && datePattern.test(date) && new Date(date + 'T00:00:00Z').toISOString().slice(0,10) === date; } catch {}
  if (!valid) throw new HttpError(400, 'Choose a valid date.');
  return date;
}
function minutesOf(time) {
  if (typeof time !== 'string') throw new HttpError(400, 'Choose a start time.');
  const match = time.match(/^(\d{1,2}):(\d{2})(?: (AM|PM))?$/);
  if (!match) throw new HttpError(400, 'Choose a valid start time.');
  let hour = Number(match[1]); const minute = Number(match[2]);
  if (minute > 59 || (match[3] ? hour < 1 || hour > 12 : hour > 23)) throw new HttpError(400, 'Choose a valid start time.');
  if (match[3]) hour = hour % 12 + (match[3] === 'PM' ? 12 : 0);
  return hour * 60 + minute;
}
const formatTime = value => {
  const hour = Math.floor(value / 60) % 24;
  return ((hour % 12) || 12) + ':' + (value % 60).toString().padStart(2,'0') + (hour >= 12 ? ' PM' : ' AM');
};
function localTimestamp(offset = 0) {
  if (!Number.isInteger(offset) || offset < -840 || offset > 840) throw new HttpError(400, 'Invalid time zone.');
  return new Date(Date.now() + offset * 60_000).toISOString().slice(0,-1);
}

export class PlannerStore {
  constructor(db) {
    this.db = db;
    db.exec(`CREATE TABLE IF NOT EXISTS planner_plans (
      id INTEGER PRIMARY KEY AUTOINCREMENT, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      plan_date TEXT NOT NULL, revision INTEGER NOT NULL, data TEXT NOT NULL, UNIQUE(user_id,plan_date));
      CREATE TABLE IF NOT EXISTS planner_settings (
        user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE, key TEXT NOT NULL, value TEXT NOT NULL,
        PRIMARY KEY(user_id,key));
      CREATE TABLE IF NOT EXISTS planner_feedback (
        id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        author_name TEXT NOT NULL, content TEXT NOT NULL, visibility TEXT NOT NULL DEFAULT 'public',
        created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
        author_avatar TEXT NOT NULL DEFAULT '',
        category TEXT NOT NULL DEFAULT 'General Feedback',
        recommendation TEXT NOT NULL DEFAULT 'yes',
        is_seed INTEGER NOT NULL DEFAULT 0);
      CREATE TABLE IF NOT EXISTS planner_feedback_likes (
        feedback_id TEXT NOT NULL REFERENCES planner_feedback(id) ON DELETE CASCADE,
        user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        created_at TEXT NOT NULL, PRIMARY KEY(feedback_id,user_id));
      CREATE TABLE IF NOT EXISTS planner_counter (name TEXT PRIMARY KEY, value INTEGER NOT NULL);
      INSERT OR IGNORE INTO planner_counter VALUES ('entity', 0);`);
    const feedbackColumns = new Set(
      db.prepare('PRAGMA table_info(planner_feedback)').all().map(row => row.name),
    );
    for (const [name, type] of Object.entries({
      author_avatar: "TEXT NOT NULL DEFAULT ''",
      category: "TEXT NOT NULL DEFAULT 'General Feedback'",
      recommendation: "TEXT NOT NULL DEFAULT 'yes'",
      is_seed: 'INTEGER NOT NULL DEFAULT 0',
    })) {
      if (!feedbackColumns.has(name)) {
        db.exec(`ALTER TABLE planner_feedback ADD COLUMN ${name} ${type}`);
      }
    }
    db.prepare(`
      UPDATE planner_feedback SET is_seed = 1, visibility = 'private'
      WHERE author_name = 'Planova' AND content IN (?, ?, ?)
    `).run(
      'Start with the tasks you can realistically finish today.',
      'Leave a little room between tasks so you do not have to rush.',
      'Add a short break between focus sessions.',
    );
  }
  nextId() {
    this.db.prepare("UPDATE planner_counter SET value = value + 1 WHERE name = 'entity'").run();
    return this.db.prepare("SELECT value FROM planner_counter WHERE name = 'entity'").get().value;
  }
  getPlan(userId, date) {
    validDate(date);
    const row = this.db.prepare('SELECT revision,data FROM planner_plans WHERE user_id = ? AND plan_date = ?').get(userId,date);
    return row ? {plan:JSON.parse(row.data), revision:row.revision} : {plan:null, revision:0};
  }
  allPlans(userId) {
    return this.db.prepare('SELECT plan_date,revision,data FROM planner_plans WHERE user_id = ?').all(userId)
      .map(row => ({date:row.plan_date,revision:row.revision,plan:JSON.parse(row.data)}));
  }
  savePlan(userId, date, input, expectedRevision) {
    validDate(date);
    if (!input || !Array.isArray(input.tasks) || input.tasks.length < 1 || input.tasks.length > 200) throw new HttpError(400, 'Add between 1 and 200 tasks.');
    const start = minutesOf(input.start_time);
    const hasBreaks = input.has_breaks === 1 || input.has_breaks === true;
    const breaks = hasBreaks ? input.break_count : 0;
    const breakMinutes = hasBreaks ? input.break_duration_minutes : 0;
    if (!Number.isInteger(breaks) || breaks < 0 || breaks > 3 || !Number.isInteger(breakMinutes)
        || (breaks > 0 && (breakMinutes < 1 || breakMinutes > 60))) throw new HttpError(400, 'Check your break settings.');
    const titles = new Set();
    for (const task of input.tasks) {
      if (typeof task.title !== 'string' || !task.title.trim() || task.title.length > 200
          || !Number.isInteger(task.duration_minutes) || task.duration_minutes < 1 || task.duration_minutes > 480
          || titles.has(task.title.trim().toLowerCase())) throw new HttpError(400, 'Check task names and durations.');
      titles.add(task.title.trim().toLowerCase());
    }
    const total = input.tasks.reduce((sum,t) => sum + t.duration_minutes,0);
    if (total <= breaks || start + total + breaks * breakMinutes > 1440) throw new HttpError(400, 'This plan goes past midnight. Shorten the tasks or start earlier.');
    this.db.exec('BEGIN IMMEDIATE');
    try {
      const existing = this.getPlan(userId,date);
      if (!Number.isInteger(expectedRevision) || expectedRevision !== existing.revision) throw new HttpError(409, 'This plan changed on another device. Refresh it before saving.');
      let id = existing.plan?.id;
      if (!id) {
        const inserted = this.db.prepare('INSERT INTO planner_plans(user_id,plan_date,revision,data) VALUES (?,?,0,?)').run(userId,date,'{}');
        id = Number(inserted.lastInsertRowid);
      }
      const oldTasks = existing.plan?.tasks || [];
      const used = new Set();
      const unchanged = new Set();
      const tasks = input.tasks.map((task,index) => {
        const old = oldTasks.find(t => t.id === task.id);
        if (old && used.has(old.id)) throw new HttpError(400,'Duplicate task.');
        if (old) used.add(old.id);
        const same = old && old.title === task.title.trim() && old.duration_minutes === task.duration_minutes;
        if (same) unchanged.add(old.id);
        return {
          id:old?.id || this.nextId(), plan_id:id, title:task.title.trim(), duration_minutes:task.duration_minutes,
          order_index:index, is_completed:same ? old.is_completed : 0, completed_at:same ? old.completed_at : null,
        };
      });
      const slots = [];
      let current = start, focus = 0, breaksUsed = 0;
      const interval = breaks ? Math.min(25,Math.floor(total/(breaks+1))) : total;
      for (const task of tasks) {
        let remaining = task.duration_minutes, session = 0;
        while (remaining > 0) {
          const duration = Math.min(remaining,breaksUsed < breaks ? interval*(breaksUsed+1)-focus : remaining);
          slots.push({id:this.nextId(),plan_id:id,task_id:task.id,slot_type:'focus',title:task.title,
            subtitle:'Focus session ' + (++session),start_time:formatTime(current),end_time:formatTime(current+duration),
            duration_minutes:duration,order_index:slots.length,is_completed:task.is_completed});
          current += duration; remaining -= duration; focus += duration;
          if (breaksUsed < breaks && focus === interval*(breaksUsed+1)) {
            slots.push({id:this.nextId(),plan_id:id,task_id:null,slot_type:'break',title:'Take a break',subtitle:'Break',
              start_time:formatTime(current),end_time:formatTime(current+breakMinutes),duration_minutes:breakMinutes,
              order_index:slots.length,is_completed:0});
            current += breakMinutes; breaksUsed++;
          }
        }
        const oldSlots = (existing.plan?.schedule_slots || []).filter(s => s.task_id === task.id);
        const newSlots = slots.filter(s => s.task_id === task.id);
        if (unchanged.has(task.id) && !task.is_completed && oldSlots.length === newSlots.length && oldSlots.every((s,i) => s.duration_minutes === newSlots[i].duration_minutes)) {
          newSlots.forEach((slot,i) => slot.is_completed = oldSlots[i].is_completed);
        }
      }
      const plan = {id, plan_date:date,start_time:formatTime(start),has_breaks:hasBreaks ? 1:0,
        break_count:breaks,break_duration_minutes:breakMinutes,total_focus_minutes:total,end_time:formatTime(current),
        created_at:existing.plan?.created_at || new Date().toISOString(),tasks,schedule_slots:slots};
      const revision = existing.revision + 1;
      this.db.prepare('UPDATE planner_plans SET data = ?, revision = ? WHERE id = ? AND user_id = ?')
        .run(JSON.stringify(plan),revision,id,userId);
      this.db.exec('COMMIT');
      return {plan,revision};
    } catch (error) { this.db.exec('ROLLBACK'); throw error; }
  }
  deletePlan(userId, date, revision) {
    validDate(date);
    const result = this.db.prepare('DELETE FROM planner_plans WHERE user_id = ? AND plan_date = ? AND revision = ?').run(userId,date,revision);
    if (!result.changes) throw new HttpError(409,'This plan changed on another device. Reopen it before deleting.');
    return {ok:true};
  }
  toggle(userId, kind, id, completed, revision, offset) {
    if (typeof completed !== 'boolean' || !Number.isSafeInteger(id)) throw new HttpError(400,'Invalid completion update.');
    const found = this.allPlans(userId).find(row => (kind === 'task' ? row.plan.tasks : row.plan.schedule_slots).some(item => item.id === id));
    if (!found) throw new HttpError(404,'Task not found.');
    if (found.revision !== revision) throw new HttpError(409,'This plan changed on another device. Refresh and try again.');
    const plan = found.plan;
    const stamp = localTimestamp(offset);
    if (kind === 'task') {
      const task = plan.tasks.find(t => t.id === id);
      task.is_completed = completed ? 1:0;
      task.completed_at = completed ? task.completed_at || stamp : null;
      plan.schedule_slots.filter(s => s.task_id === id && s.slot_type === 'focus').forEach(s => s.is_completed = completed ? 1:0);
    } else {
      const slot = plan.schedule_slots.find(s => s.id === id);
      slot.is_completed = completed ? 1:0;
      if (slot.task_id != null && slot.slot_type === 'focus') {
        const task = plan.tasks.find(t => t.id === slot.task_id);
        task.is_completed = plan.schedule_slots.filter(s => s.task_id === slot.task_id && s.slot_type === 'focus').every(s => s.is_completed) ? 1:0;
        task.completed_at = task.is_completed ? task.completed_at || stamp : null;
      }
    }
    const result = this.db.prepare('UPDATE planner_plans SET data = ?, revision = revision + 1 WHERE user_id = ? AND plan_date = ? AND revision = ?')
      .run(JSON.stringify(plan),userId,found.date,revision);
    if (!result.changes) throw new HttpError(409,'This plan changed on another device. Refresh and try again.');
    return {plan,revision:revision+1};
  }
  activity(userId, today) {
    validDate(today);
    const counts = new Map();
    for (const {plan} of this.allPlans(userId)) for (const task of plan.tasks) {
      if (task.is_completed && task.completed_at) {
        const date = task.completed_at.slice(0,10);
        counts.set(date,(counts.get(date)||0)+1);
      }
    }
    const day = n => { const date = new Date(today+'T12:00:00Z'); date.setUTCDate(date.getUTCDate()+n); return date.toISOString().slice(0,10); };
    const weekly = Array.from({length:7},(_,i) => {
      const date = day(i-6), count = counts.get(date)||0;
      return {date,tasks_completed:count,is_active:count>0 ? 1:0};
    });
    let offset = counts.has(today) ? 0:-1, streak = 0;
    while (counts.has(day(offset))) { streak++; offset--; }
    return {weekly,streak};
  }
  profile(user, today) {
    const photo=this.db.prepare('SELECT avatar_data FROM users WHERE id = ?').get(user.id)?.avatar_data || '';
    return {id:1,name:user.name,workspace:'Personal',tagline:'',avatar_url:photo,
      streak_count:this.activity(user.id,today).streak,last_active_date:today,email:user.email};
  }
  settings(userId) {
    const entries = this.db.prepare('SELECT key,value FROM planner_settings WHERE user_id = ?').all(userId);
    return Object.fromEntries(entries.map(row => [row.key,row.value]));
  }
  setSetting(userId,key,value) {
    const allowed = {
      time_format: ['12-hour','24-hour'],
      color_theme: ['cream','sage','lavender','rose','sky'],
      suggestion_like_short_list: ['true','false'],
      suggestion_like_enough_time: ['true','false'],
      suggestion_like_break: ['true','false'],
    };
    if (!Object.hasOwn(allowed,key) || !allowed[key].includes(value)) throw new HttpError(400,'Invalid setting.');
    this.db.prepare('INSERT INTO planner_settings VALUES (?,?,?) ON CONFLICT(user_id,key) DO UPDATE SET value = excluded.value')
      .run(userId,key,value);
  }
  listFeedback(userId) {
    let rows = this.db.prepare(`
      SELECT id, user_id, author_name, author_avatar, content, category,
        recommendation, visibility, created_at, updated_at
      FROM planner_feedback
      WHERE is_seed = 0 AND (visibility = 'public' OR user_id = ?)
      ORDER BY created_at DESC
    `).all(userId);
    const likes = this.db.prepare('SELECT feedback_id, user_id FROM planner_feedback_likes').all();
    const counts = new Map();
    const likedSet = new Set();
    for (const l of likes) {
      counts.set(l.feedback_id, (counts.get(l.feedback_id) || 0) + 1);
      if (l.user_id === userId) likedSet.add(l.feedback_id);
    }
    return rows.map(r => ({
      ...r,
      likes_count: counts.get(r.id) || 0,
      is_liked_by_me: likedSet.has(r.id),
      is_mine: r.user_id === userId,
    }));
  }
  addFeedback(userId, content, category = 'General Feedback', recommendation = 'yes', visibility = 'private') {
    const text = typeof content === 'string' ? content.trim() : '';
    if (!text || text.length > 1000) throw new HttpError(400, 'Feedback must be between 1 and 1000 characters.');
    if (!['General Feedback', 'Feature Suggestion', 'Bug Report'].includes(category)) throw new HttpError(400, 'Choose a feedback category.');
    if (!['yes', 'maybe', 'no'].includes(recommendation)) throw new HttpError(400, 'Choose a recommendation response.');
    const vis = visibility === 'public' ? 'public' : 'private';
    const user = this.db.prepare('SELECT name, avatar_data FROM users WHERE id = ?').get(userId);
    const authorName = user?.name || 'Planova User';
    const authorAvatar = user?.avatar_data || '';
    const id = 'fb_' + Date.now() + '_' + Math.random().toString(36).slice(2, 8);
    const now = new Date().toISOString();
    this.db.prepare(`INSERT INTO planner_feedback
      (id, user_id, author_name, author_avatar, content, category, recommendation, visibility, created_at, updated_at)
      VALUES (?,?,?,?,?,?,?,?,?,?)`)
      .run(id, userId, authorName, authorAvatar, text, category, recommendation, vis, now, now);
    return {
      id, user_id: userId, author_name: authorName, author_avatar: authorAvatar,
      content: text, category, recommendation, visibility: vis,
      created_at: now, updated_at: now, likes_count: 0, is_liked_by_me: false, is_mine: true,
    };
  }
  updateFeedback(userId, id, content, category = 'General Feedback', recommendation = 'yes', visibility = 'private') {
    const text = typeof content === 'string' ? content.trim() : '';
    if (!text || text.length > 1000) throw new HttpError(400, 'Feedback must be between 1 and 1000 characters.');
    if (!['General Feedback', 'Feature Suggestion', 'Bug Report'].includes(category)) throw new HttpError(400, 'Choose a feedback category.');
    if (!['yes', 'maybe', 'no'].includes(recommendation)) throw new HttpError(400, 'Choose a recommendation response.');
    const vis = visibility === 'public' ? 'public' : 'private';
    const row = this.db.prepare('SELECT user_id, author_name, author_avatar, created_at FROM planner_feedback WHERE id = ?').get(id);
    if (!row) throw new HttpError(404, 'Feedback not found.');
    if (row.user_id !== userId) throw new HttpError(403, 'Unauthorized to edit this feedback.');
    const now = new Date().toISOString();
    this.db.prepare('UPDATE planner_feedback SET content = ?, category = ?, recommendation = ?, visibility = ?, updated_at = ? WHERE id = ?')
      .run(text, category, recommendation, vis, now, id);
    const likesCount = this.db.prepare('SELECT COUNT(*) as count FROM planner_feedback_likes WHERE feedback_id = ?').get(id)?.count || 0;
    const isLiked = Boolean(this.db.prepare('SELECT 1 FROM planner_feedback_likes WHERE feedback_id = ? AND user_id = ?').get(id, userId));
    return {
      id, user_id: userId, author_name: row.author_name, author_avatar: row.author_avatar,
      content: text, category, recommendation, visibility: vis,
      created_at: row.created_at, updated_at: now, likes_count: likesCount, is_liked_by_me: isLiked, is_mine: true,
    };
  }
  deleteFeedback(userId, id) {
    const row = this.db.prepare('SELECT user_id FROM planner_feedback WHERE id = ?').get(id);
    if (!row) throw new HttpError(404, 'Feedback not found.');
    if (row.user_id !== userId) throw new HttpError(403, 'Unauthorized to delete this feedback.');
    this.db.prepare('DELETE FROM planner_feedback WHERE id = ?').run(id);
    return {ok: true};
  }
  toggleFeedbackLike(userId, id) {
    const row = this.db.prepare('SELECT id FROM planner_feedback WHERE id = ?').get(id);
    if (!row) throw new HttpError(404, 'Feedback not found.');
    const existing = this.db.prepare('SELECT 1 FROM planner_feedback_likes WHERE feedback_id = ? AND user_id = ?').get(id, userId);
    if (existing) {
      this.db.prepare('DELETE FROM planner_feedback_likes WHERE feedback_id = ? AND user_id = ?').run(id, userId);
    } else {
      this.db.prepare('INSERT OR IGNORE INTO planner_feedback_likes (feedback_id, user_id, created_at) VALUES (?,?,?)')
        .run(id, userId, new Date().toISOString());
    }
    const count = this.db.prepare('SELECT COUNT(*) as count FROM planner_feedback_likes WHERE feedback_id = ?').get(id)?.count || 0;
    return {is_liked_by_me: !existing, likes_count: count};
  }
}
