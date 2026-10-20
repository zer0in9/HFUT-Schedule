const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const publish = require('../ci-release.cjs');

test('publish only after IPA upload, preserve full commit text as data', async t => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'hfut-release-test-'));
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  process.env.IOS_VERSION = '2026.10.20.2';
  fs.writeFileSync(path.join(directory, 'HFUTSchedule-2026.10.20.2.ipa'), 'synthetic IPA');
  const calls = [];
  const missing = async () => { throw Object.assign(new Error('Not found'), { status: 404 }); };
  const repos = {
    getReleaseByTag: missing, listReleaseAssets() {},
    createRelease: async request => { calls.push(['create', request]); return { data: { id: 1 } }; },
    uploadReleaseAsset: async request => { calls.push(['upload', request]); },
    updateRelease: async request => { calls.push(['publish', request]); return { data: { html_url: 'https://example.test/release' } }; },
  };
  const github = { rest: { repos, git: { getRef: missing } }, paginate: async () => [] };
  const message = '适配 iPad\n\nKeep `literal` and $(literal)\n多行提交信息\n';
  await publish({ github, context: { repo: {}, sha: 'abc' }, core: { info() {} }, assetDirectory: directory, readCommitMessage: () => message });
  assert.deepEqual(calls.map(call => call[0]), ['create', 'upload', 'publish']);
  assert.equal(calls[0][1].draft, true);
  assert.equal(calls[0][1].target_commitish, 'abc');
  assert.equal(calls[2][1].prerelease, true);
  assert.equal(calls[2][1].draft, false);
  assert.equal(calls[2][1].body, message.trimEnd());
  assert.equal(calls[1][1].name, 'HFUTSchedule-2026.10.20.2.ipa');
});

test('upload failure leaves the release unpublished', async t => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'hfut-release-test-'));
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  process.env.IOS_VERSION = '2026.10.20.3';
  fs.writeFileSync(path.join(directory, 'HFUTSchedule-2026.10.20.3.ipa'), 'synthetic');
  let published = false;
  const missing = async () => { throw Object.assign(new Error('Not found'), { status: 404 }); };
  const github = { rest: { git: { getRef: missing }, repos: {
    getReleaseByTag: missing, listReleaseAssets() {}, createRelease: async () => ({ data: { id: 1 } }),
    uploadReleaseAsset: async () => { throw new Error('Upload failed'); },
    updateRelease: async () => { published = true; },
  } }, paginate: async () => [] };
  await assert.rejects(publish({ github, context: { repo: {}, sha: 'abc' }, core: { info() {} }, assetDirectory: directory, readCommitMessage: () => 'commit' }), /Upload failed/);
  assert.equal(published, false);
});

test('rerun keeps a published asset and rejects a tag on another commit', async t => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'hfut-release-test-'));
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  process.env.IOS_VERSION = '2026.10.20.4';
  const name = 'HFUTSchedule-2026.10.20.4.ipa';
  fs.writeFileSync(path.join(directory, name), 'synthetic');
  let tagCommit = 'abc';
  const github = { rest: { git: { getRef: async () => ({ data: { object: { sha: tagCommit, type: 'commit' } } }) }, repos: {
    getReleaseByTag: async () => ({ data: { id: 1, draft: false, prerelease: true } }), listReleaseAssets() {},
  } }, paginate: async () => [{ name, size: 10 }] };
  const args = { github, context: { repo: {}, sha: 'abc' }, core: { info() {} }, assetDirectory: directory, readCommitMessage: () => 'commit' };
  await publish(args); // No mutation endpoints are provided: accidental rewriting fails this test.
  tagCommit = 'different';
  await assert.rejects(publish(args), /different commit/);
});

test('retry resumes an unpublished draft even before GitHub creates its tag', async t => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'hfut-release-test-'));
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  process.env.IOS_VERSION = '2026.10.20.5';
  const name = 'HFUTSchedule-2026.10.20.5.ipa';
  fs.writeFileSync(path.join(directory, name), 'synthetic');
  const calls = [];
  const github = { rest: {
    git: { getRef: async () => { throw Object.assign(new Error('No tag yet'), { status: 404 }); } },
    repos: {
      getReleaseByTag: async () => ({ data: { id: 1, draft: true, prerelease: true, target_commitish: 'abc' } }),
      listReleaseAssets() {},
      deleteReleaseAsset: async () => { calls.push('delete draft asset'); },
      uploadReleaseAsset: async () => { calls.push('upload'); },
      updateRelease: async () => { calls.push('publish'); return { data: { html_url: 'draft-resumed' } }; },
    },
  }, paginate: async () => [{ name, id: 7 }] };
  await publish({ github, context: { repo: {}, sha: 'abc' }, core: { info() {} }, assetDirectory: directory, readCommitMessage: () => 'commit' });
  assert.deepEqual(calls, ['delete draft asset', 'upload', 'publish']);
});
