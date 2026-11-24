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
      CREATE TABLE IF NOT EXISTS planner_counter (name TEXT PRIMARY KEY, value INTEGER NOT NULL);
      INSERT OR IGNORE INTO planner_counter VALUES ('entity', 0);`);
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
    if (!input || !Array.isArray(input.tasks) || input.tasks.length < 1 || input.tasks.length > 30) throw new HttpError(400, 'Add between 1 and 30 tasks.');
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
}
