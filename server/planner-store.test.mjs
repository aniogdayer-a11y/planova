import test from 'node:test';
import assert from 'node:assert/strict';
import { openAccountDatabase } from './auth.mjs';
import { PlannerStore } from './planner-store.mjs';

const input = () => ({start_time:'9:00 AM',has_breaks:1,break_count:1,break_duration_minutes:5,
  tasks:[{title:'Design poster',duration_minutes:50},{title:'Review notes',duration_minutes:30}]});

test('theme and likes are validated and isolated per account', () => {
  const {db,store} = fixture();
  try {
    store.setSetting('a','color_theme','sage');
    store.setSetting('a','suggestion_like_short_list','true');
    assert.equal(store.settings('a').color_theme,'sage');
    assert.equal(store.settings('a').suggestion_like_short_list,'true');
    assert.deepEqual(store.settings('b'),{});
    assert.throws(() => store.setSetting('a','color_theme','unknown'));
    assert.throws(() => store.setSetting('a','suggestion_like_short_list','10'));
    assert.throws(() => store.setSetting('a','__proto__','true'));
  } finally { db.close(); }
});

test('feedback submission, visibility, likes, editing and deletion work and isolate permissions', () => {
  const {db,store} = fixture();
  try {
    // The community feed starts empty instead of displaying seeded tips.
    const initial = store.listFeedback('a');
    assert.deepEqual(initial, []);

    // Create feedback
    const created = store.addFeedback(
      'a',
      'Great planning assistant!',
      'Feature Suggestion',
      'yes',
      'public',
    );
    assert.equal(created.content, 'Great planning assistant!');
    assert.equal(created.is_mine, true);
    assert.equal(created.category, 'Feature Suggestion');
    assert.equal(created.recommendation, 'yes');

    // Visible to b
    const listB = store.listFeedback('b');
    const itemInB = listB.find(f => f.id === created.id);
    assert.ok(itemInB);
    assert.equal(itemInB.is_mine, false);

    // Like by b
    const liked = store.toggleFeedbackLike('b', created.id);
    assert.equal(liked.is_liked_by_me, true);
    assert.equal(liked.likes_count, 1);

    // Prevent duplicate like: liking again should toggle unlike
    const unliked = store.toggleFeedbackLike('b', created.id);
    assert.equal(unliked.is_liked_by_me, false);
    assert.equal(unliked.likes_count, 0);

    // Like again
    store.toggleFeedbackLike('b', created.id);

    // Update by owner 'a'
    const updated = store.updateFeedback(
      'a',
      created.id,
      'Updated content',
      'Bug Report',
      'maybe',
      'public',
    );
    assert.equal(updated.content, 'Updated content');
    assert.equal(updated.category, 'Bug Report');
    assert.equal(updated.recommendation, 'maybe');
    assert.equal(updated.likes_count, 1);

    // Update by non-owner 'b' throws 403
    assert.throws(() => store.updateFeedback('b', created.id, 'Hacked!'), {status: 403});

    // Delete by non-owner 'b' throws 403
    assert.throws(() => store.deleteFeedback('b', created.id), {status: 403});

    // Delete by owner 'a' succeeds
    store.deleteFeedback('a', created.id);
    const afterDelete = store.listFeedback('a');
    assert.ok(!afterDelete.some(f => f.id === created.id));

    const privateFeedback = store.addFeedback(
      'a',
      'Private note',
      'General Feedback',
      'no',
      'private',
    );
    assert.ok(store.listFeedback('a').some(f => f.id === privateFeedback.id));
    assert.ok(!store.listFeedback('b').some(f => f.id === privateFeedback.id));
  } finally { db.close(); }
});
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
