// Invoked by actions/github-script. No credentials, remote writes, or shell interpolation.
function buildVersion(current, runs) {
  const created = new Date(current.created_at);
  if (!Number.isFinite(created.getTime())) throw new Error('Invalid workflow creation time');
  const local = new Date(created.getTime() + 8 * 60 * 60 * 1000);
  const year = local.getUTCFullYear(), month = local.getUTCMonth() + 1, day = local.getUTCDate();
  const start = new Date(Date.UTC(year, month - 1, day) - 8 * 60 * 60 * 1000);
  const end = new Date(start.getTime() + 24 * 60 * 60 * 1000 - 1000);
  const sameDay = new Map([...runs, current].filter(run =>
    run.workflow_id === current.workflow_id && run.event === 'push' &&
    run.run_number <= current.run_number &&
    new Date(run.created_at) >= start && new Date(run.created_at) <= end
  ).map(run => [run.id, run]));
  const count = sameDay.size;
  if (count < 1 || count > 9999) throw new Error('Invalid daily workflow count');
  return { version: `${year}.${month}.${day}.${count}`, start, end };
}

async function main({ github, context, core }) {
  if (context.eventName !== 'push' || !context.ref.startsWith('refs/heads/')) {
    throw new Error('iOS builds must be triggered by a branch commit push');
  }
  const { data: current } = await github.rest.actions.getWorkflowRun({ ...context.repo, run_id: context.runId });
  if (current.head_sha !== context.sha) throw new Error('Workflow commit does not match checkout');
  const { start, end } = buildVersion(current, []);
  const query = {
    ...context.repo, workflow_id: current.workflow_id, event: 'push',
    created: `${start.toISOString()}..${new Date(Math.min(end.getTime(), new Date(current.created_at).getTime())).toISOString()}`, per_page: 100,
  };
  // GitHub limits filtered workflow-run results to 1000; fail explicitly rather than reuse a version.
  const first = await github.rest.actions.listWorkflowRuns({ ...query, page: 1 });
  if (first.data.total_count > 1000) throw new Error('Daily workflow query exceeds GitHub\'s 1000-run limit');
  const runs = [...first.data.workflow_runs];
  for (let page = 2; runs.length < first.data.total_count; page++) {
    const response = await github.rest.actions.listWorkflowRuns({ ...query, page });
    if (!response.data.workflow_runs.length) throw new Error('Incomplete workflow-run history');
    runs.push(...response.data.workflow_runs);
  }
  const { version } = buildVersion(current, runs);
  core.setOutput('version', version);
  core.setOutput('tag', `ios-${version}`);
  core.info(`iOS ${version} · ${context.sha} · Asia/Shanghai`);
}

module.exports = main;
module.exports.buildVersion = buildVersion;
