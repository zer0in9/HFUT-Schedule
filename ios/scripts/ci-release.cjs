const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

// Only the final job receives contents:write. Commit text is data, never executable code.
module.exports = async function ({ github, context, core, assetDirectory = 'release-assets',
  readCommitMessage = sha => execFileSync('git', ['log', '-1', '--format=%B', sha], { encoding: 'utf8' }) }) {
  const version = process.env.IOS_VERSION;
  if (!/^\d{4}\.[1-9]\d?\.[1-9]\d?\.[1-9]\d*$/.test(version || '')) throw new Error('Invalid release version');
  const tag = `ios-${version}`;
  const filename = `HFUTSchedule-${version}.ipa`;
  const ipa = path.join(assetDirectory, filename);
  const data = fs.readFileSync(ipa);
  const body = readCommitMessage(context.sha).trimEnd();
  let tagExists = false;
  try {
    const ref = (await github.rest.git.getRef({ ...context.repo, ref: `tags/${tag}` })).data;
    if (ref.object.sha !== context.sha || ref.object.type !== 'commit') throw new Error('Release tag already points to a different commit');
    tagExists = true;
  } catch (error) { if (error.status !== 404) throw error; }
  let release;
  try {
    release = (await github.rest.repos.getReleaseByTag({ ...context.repo, tag })).data;
  } catch (error) {
    if (error.status !== 404) throw error;
  }
  if (release) {
    if ((!tagExists && release.target_commitish !== context.sha) || !release.prerelease) {
      throw new Error('Existing release does not belong to this commit prerelease');
    }
    // Rerunning a completed workflow must not replace a published asset or move its tag.
    if (!release.draft) {
      const assets = await github.paginate(github.rest.repos.listReleaseAssets, { ...context.repo, release_id: release.id, per_page: 100 });
      if (!assets.some(asset => asset.name === filename && asset.size > 0)) throw new Error('Published prerelease is missing its IPA');
      core.info(`Already published ${release.html_url}`);
      return;
    }
  } else {
    release = (await github.rest.repos.createRelease({
      ...context.repo, tag_name: tag, target_commitish: context.sha,
      name: `iOS ${version}`, body, draft: true, prerelease: true, make_latest: 'false',
    })).data;
  }
  const assets = await github.paginate(github.rest.repos.listReleaseAssets, { ...context.repo, release_id: release.id, per_page: 100 });
  const existing = assets.find(asset => asset.name === filename);
  if (existing) await github.rest.repos.deleteReleaseAsset({ ...context.repo, asset_id: existing.id });
  await github.rest.repos.uploadReleaseAsset({
    ...context.repo, release_id: release.id, name: filename, data,
    headers: { 'content-type': 'application/octet-stream', 'content-length': data.length },
  });
  const published = await github.rest.repos.updateRelease({
    ...context.repo, release_id: release.id, name: `iOS ${version}`, body,
    draft: false, prerelease: true, make_latest: 'false',
  });
  core.info(`Published ${published.data.html_url}`);
};
