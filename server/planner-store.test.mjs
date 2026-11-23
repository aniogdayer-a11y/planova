import test from 'node:test';
import assert from 'node:assert/strict';
import { openAccountDatabase } from './auth.mjs';
import { PlannerStore } from './planner-store.mjs';

const input = () => ({start_time:'9:00 AM',has_breaks:1,break_count:1,break_duration_minutes:5,
  tasks:[{title:'Design poster',duration_minutes:50},{title:'Review notes',duration_minutes:30}]});
function fixture() {
  const db = openAccountDatabase(':memory:');
  db.prepare('INSERT INTO users(id,email,name,created_at) VALUES (?,?,?,?)').run('a','a@example.test','Account A',Date.now());
  db.prepare('INSERT INTO users(id,email,name,created_at) VALUES (?,?,?,?)').run('b','b@example.test','Account B',Date.now());
  return {db,store:new PlannerStore(db)};
}
test('plans sync across clients and remain isolated by account', () => {
  const {db,store} = fixture();
  try {
    const saved = store.savePlan('a','2026-11-23',input(),0);
    assert.equal(saved.plan.schedule_slots.length,4);
    assert.equal(saved.plan.end_time,'10:25 AM');
    assert.equal(store.getPlan('a','2026-11-23').plan.tasks[0].title,'Design poster');
    assert.equal(store.getPlan('b','2026-11-23').plan,null);
    assert.throws(() => store.toggle('b','task',saved.plan.tasks[0].id,true,1,480),error => error.status === 404);
    assert.equal(store.activity('b','2026-11-23').streak,0);
  } finally { db.close(); }
});
test('stale revisions cannot overwrite another device', () => {
  const {db,store} = fixture();
  try {
    store.savePlan('a','2026-11-23',input(),0);
    const changed = input(); changed.start_time = '10:00 AM';
    store.savePlan('a','2026-11-23',changed,1);
    assert.throws(() => store.savePlan('a','2026-11-23',input(),1),error => error.status === 409);
    assert.equal(store.getPlan('a','2026-11-23').plan.start_time,'10:00 AM');
  } finally { db.close(); }
});
test('session completion syncs tasks, stats and unchanged plan edits', () => {
  const {db,store} = fixture();
  try {
    let saved = store.savePlan('a','2026-11-23',input(),0);
    const focus = saved.plan.schedule_slots.filter(s => s.task_id === saved.plan.tasks[0].id);
    saved = store.toggle('a','slot',focus[0].id,true,saved.revision,480);
    assert.equal(saved.plan.tasks[0].is_completed,0);
    saved = store.savePlan('a','2026-11-23',{...input(),tasks:saved.plan.tasks},saved.revision);
    assert.equal(saved.plan.schedule_slots[0].is_completed,1);
    const remaining = saved.plan.schedule_slots.find(s => s.task_id === saved.plan.tasks[0].id && !s.is_completed);
    saved = store.toggle('a','slot',remaining.id,true,saved.revision,480);
    assert.equal(saved.plan.tasks[0].is_completed,1);
    const today = new Date(Date.now()+480*60_000).toISOString().slice(0,10);
    assert.equal(store.activity('a',today).weekly.at(-1).tasks_completed,1);
    assert.equal(store.activity('a',today).streak,1);
    saved = store.toggle('a','task',saved.plan.tasks[0].id,false,saved.revision,480);
    assert.equal(saved.plan.tasks[0].completed_at,null);
    assert.equal(saved.plan.schedule_slots.filter(s => s.task_id === saved.plan.tasks[0].id).every(s => !s.is_completed),true);
  } finally { db.close(); }
});
test('failed validation leaves the previous plan intact', () => {
  const {db,store} = fixture();
  try {
    const saved = store.savePlan('a','2026-11-23',input(),0);
    assert.throws(() => store.savePlan('a','2026-11-23',{...input(),start_time:'11:45 PM'},1),error => error.status === 400);
    assert.deepEqual(store.getPlan('a','2026-11-23'),saved);
    store.setSetting('a','time_format','24-hour');
    assert.deepEqual(store.settings('b'),{});
  } finally { db.close(); }
});
