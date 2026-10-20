const { test } = require('node:test');
const assert = require('node:assert/strict');
const allocate = require('../ci-version.cjs');
const { buildVersion } = allocate;

const run = (id, number, time, overrides = {}) => ({
  id, run_number: number, workflow_id: 9, event: 'push', created_at: time, head_sha: 'abc', ...overrides,
});

test('Shanghai midnight resets the count, with no zero-padded components', () => {
  const previous = run(1, 101, '2026-01-01T15:59:59Z');
  const current = run(2, 102, '2026-01-01T16:00:00Z');
  assert.equal(buildVersion(current, [previous, current]).version, '2026.1.2.1');
});

test('count failures and cancellations across branches, exclude other workflows and future runs', () => {
  const current = run(4, 104, '2026-10-20T12:00:00Z');
  const runs = [
    run(1, 101, '2026-10-20T01:00:00Z', { conclusion: 'failure', head_branch: 'dev' }),
    run(2, 102, '2026-10-20T02:00:00Z', { conclusion: 'cancelled', head_branch: 'main' }),
    run(3, 103, '2026-10-20T03:00:00Z'), current, current,
    run(5, 105, '2026-10-20T13:00:00Z'),
    run(6, 90, '2026-10-20T03:00:00Z', { workflow_id: 10 }),
    run(7, 91, '2026-10-20T03:00:00Z', { event: 'pull_request' }),
  ];
  assert.equal(buildVersion(current, runs).version, '2026.10.20.4');
  assert.equal(buildVersion({ ...current, run_attempt: 2 }, runs).version, '2026.10.20.4');
});

test('include current run even if GitHub list indexing is delayed', () => {
  const current = run(2, 102, '2026-10-20T12:00:00Z');
  assert.equal(buildVersion(current, [run(1, 101, '2026-10-20T02:00:00Z')]).version, '2026.10.20.2');
});

test('paginate the daily workflow API and emit one shared version', async () => {
  const current = run(2, 102, '2026-10-20T12:00:00Z');
  const output = {};
  const pages = [];
  const github = { rest: { actions: {
    getWorkflowRun: async () => ({ data: current }),
    listWorkflowRuns: async query => {
      pages.push(query);
      return { data: { total_count: 2, workflow_runs: query.page === 1 ? [current] : [run(1, 101, '2026-10-20T02:00:00Z')] } };
    },
  } } };
  await allocate({ github, context: { repo: {}, eventName: 'push', ref: 'refs/heads/dev', sha: 'abc', runId: 2 },
    core: { setOutput: (key, value) => { output[key] = value; }, info() {} } });
  assert.equal(output.version, '2026.10.20.2');
  assert.equal(pages.length, 2);
  assert.equal(pages[0].created, '2026-10-19T16:00:00.000Z..2026-10-20T12:00:00.000Z');
});

test('refuse tag pushes and mismatched workflow commits', async () => {
  await assert.rejects(allocate({ context: { eventName: 'push', ref: 'refs/tags/ios-x' } }), /branch commit/);
  const github = { rest: { actions: { getWorkflowRun: async () => ({ data: { head_sha: 'wrong' } }) } } };
  await assert.rejects(allocate({ github, context: { repo: {}, eventName: 'push', ref: 'refs/heads/dev', sha: 'abc' } }), /does not match/);
});

test('refuse truncated GitHub history instead of allocating a duplicate number', async () => {
  const current = run(2, 102, '2026-10-20T12:00:00Z');
  const github = { rest: { actions: {
    getWorkflowRun: async () => ({ data: current }),
    listWorkflowRuns: async () => ({ data: { total_count: 1001, workflow_runs: [] } }),
  } } };
  await assert.rejects(allocate({ github, context: { repo: {}, eventName: 'push', ref: 'refs/heads/dev', sha: 'abc' } }), /1000-run limit/);
});
