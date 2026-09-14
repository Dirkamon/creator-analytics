// Local-only multi-session regression. Clones an empty disposable database and
// removes only the uniquely named clones it creates. Never accepts a remote URL.
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
const require = createRequire(new URL('../../apps/web/package.json', import.meta.url));
const postgres = require('postgres');
const connection = { host: '127.0.0.1', port: 55479, username: 'postgres', max: 1,
  prepare: false, connect_timeout: 5, onnotice() {}, connection: { statement_timeout: 30000 } };
const control = postgres({ ...connection, database: 'template1' });
const source = postgres({ ...connection, database: 'postgres' });
const report = [];
const regression = await readFile(new URL('./039_scheduling_preferences_regression.sql', import.meta.url), 'utf8');
const fixture = regression.slice(regression.indexOf('insert into public.organizations'), regression.indexOf('savepoint fresh_inventory;'));
assert(fixture.startsWith('insert into public.organizations') && fixture.includes('__039_NEW_'));
const refresh = `select public.refresh_schedule_proposals(date_trunc('week',now() at time zone 'America/Denver')::date+14,7) as n`;
const save = (sql, revision, enabled) => sql`select public.save_scheduling_preferences(${revision},14,3,14,3,${enabled},'concurrency@example.invalid') as revision`;
const pending = promise => Promise.resolve(promise).then(value => ({ value }), error => ({ error }));

async function waitForAdvisory(pid) {
  const deadline = Date.now() + 6000;
  do {
    const [row] = await control`select wait_event_type,wait_event from pg_stat_activity where pid=${pid}`;
    if (row?.wait_event_type === 'Lock' && row.wait_event === 'advisory') return;
    await new Promise(resolve => setTimeout(resolve, 40));
  } while (Date.now() < deadline);
  throw new Error(`Session ${pid} never waited for the shared advisory lock`);
}

async function test(name, body) {
  const database = `pref039_concurrency_${randomUUID().replaceAll('-', '')}`;
  assert(/^pref039_concurrency_[a-f0-9]{32}$/.test(database));
  await control.unsafe(`create database ${database} template postgres`);
  const a = postgres({ ...connection, database });
  const b = postgres({ ...connection, database });
  const observer = postgres({ ...connection, database });
  try {
    await observer.unsafe(`begin; ${fixture} commit;`);
    const [{ revision }] = await observer`select revision from public.scheduling_preferences`;
    const [{ pid }] = await b`select pg_backend_pid() as pid`;
    await body({ a, b, observer, revision, pid });
    report.push({ name, status: 'PASS' });
    console.log(`PASS: ${name}`);
  } finally {
    for (const client of [a, b]) await client.unsafe('rollback').catch(() => {});
    await Promise.all([a.end(), b.end(), observer.end()]);
    // Exact generated clone only, never postgres or a user-supplied database.
    await control.unsafe(`drop database ${database}`);
  }
}

try {
  const [baseline] = await source`select (select count(*)::int from public.posts) posts,
    (select count(*)::int from public.schedule_change_proposals) proposals,
    (select enabled from public.scheduling_preferences) enabled`;
  assert.deepEqual(baseline, { posts: 0, proposals: 0, enabled: false }, 'Not the empty disposable local source');
  await source.end();

  await test('simultaneous settings saves reject the stale revision', async ({ a, b, observer, revision, pid }) => {
    await a.unsafe('begin');
    await save(a, revision, true);
    const queued = pending(save(b, revision, false));
    await waitForAdvisory(pid);
    await a.unsafe('commit');
    assert.equal((await queued).error?.code, 'P4101');
    const [state] = await observer`select revision,enabled,(select count(*)::int from public.scheduling_preferences_audit) audits from public.scheduling_preferences`;
    assert.deepEqual(state, { revision: revision + 1, enabled: true, audits: 1 });
  });

  await test('simultaneous generation is serialized and does not duplicate proposals', async ({ a, b, observer, pid }) => {
    await a.unsafe('begin');
    const [{ n }] = await a.unsafe(refresh);
    assert(n >= 2);
    const queued = pending(b.unsafe(refresh));
    await waitForAdvisory(pid);
    await a.unsafe('commit');
    const result = await queued;
    assert.ifError(result.error);
    assert.equal(result.value[0].n, 0);
    const [counts] = await observer`select count(*)::int n,count(distinct buffer_post_id)::int distinct_posts from public.schedule_change_proposals`;
    assert.deepEqual(counts, { n, distinct_posts: n });
  });

  await test('settings save waits for generation then refuses unresolved proposals', async ({ a, b, observer, revision, pid }) => {
    await a.unsafe('begin');
    const [{ n }] = await a.unsafe(refresh);
    assert(n >= 2);
    const queued = pending(save(b, revision, false));
    await waitForAdvisory(pid);
    await a.unsafe('commit');
    assert.equal((await queued).error?.code, 'P4102');
    const [state] = await observer`select revision,(select count(*)::int from public.scheduling_preferences_audit) audits from public.scheduling_preferences`;
    assert.deepEqual(state, { revision, audits: 0 });
  });

  await test('generation waits for a save and uses its committed revision', async ({ a, b, observer, revision, pid }) => {
    await a.unsafe('begin');
    await save(a, revision, true);
    const queued = pending(b.unsafe(refresh));
    await waitForAdvisory(pid);
    await a.unsafe('commit');
    const result = await queued;
    assert.ifError(result.error);
    assert(result.value[0].n >= 2);
    const [check] = await observer`select bool_and(preferences_revision=${revision + 1}) correct_revision from public.schedule_change_proposals`;
    assert.equal(check.correct_revision, true);
  });

  await test('generation racing activation selects the new path after the save commits', async ({ a, b, observer, revision, pid }) => {
    await observer`update public.scheduling_preferences set enabled=false`;
    await a.unsafe('begin');
    await save(a, revision, true);
    const queued = pending(b.unsafe(refresh));
    await waitForAdvisory(pid);
    await a.unsafe('commit');
    const result = await queued;
    assert.ifError(result.error);
    assert(result.value[0].n >= 2);
    const [check] = await observer`select bool_and(preferences_revision=${revision + 1} and abs(extract(epoch from(proposed_due_at_utc-current_due_at_utc)))<=43200) safe from public.schedule_change_proposals`;
    assert.equal(check.safe, true);
  });

  await test('generation racing deactivation selects the existing path after the save commits', async ({ a, b, observer, revision, pid }) => {
    await observer.unsafe('begin');
    await observer`update public.scheduling_preferences set enabled=false`;
    const [{ n: expected }] = await observer.unsafe(refresh);
    await observer.unsafe('rollback');
    await a.unsafe('begin');
    await save(a, revision, false);
    const queued = pending(b.unsafe(refresh));
    await waitForAdvisory(pid);
    await a.unsafe('commit');
    const result = await queued;
    assert.ifError(result.error);
    assert.equal(result.value[0].n, expected);
    const [settings] = await observer`select enabled,revision from public.scheduling_preferences`;
    assert.deepEqual(settings, { enabled: false, revision: revision + 1 });
  });

  console.log(JSON.stringify({ tests: report, temporaryDatabasesRemoved: true }));
} finally {
  await source.end().catch(() => {});
  await control.end();
}
