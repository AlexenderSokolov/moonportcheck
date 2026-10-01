import test from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import {
  projectVersion, executionMetadata, stepsPassed, collectEvidenceMetadata,
} from './evidence.mjs';

const version = '0.2.0-rc.1';
const runtime = { platform: 'linux', architecture: 'x64', node: 'v24.15.0', os_release: '6.8.0' };
const git = { own_repository: true, head: 'a'.repeat(40), status: '', status_ok: true };

test('version comes from package metadata and agrees with the MoonBit module', () => {
  assert.equal(projectVersion({ version }, `name = "example/lib"\nversion = "${version}"\n`), version);
  assert.throws(() => projectVersion({ version }, 'version = "0.1.0"'), /version mismatch/i);
});

test('missing, malformed, or ambiguous project versions fail closed', () => {
  for (const packageMetadata of [{}, { version: null }, { version: '' }]) {
    assert.throws(() => projectVersion(packageMetadata, `version = "${version}"`), /version/i);
  }
  for (const moduleText of ['', 'version = 2', `version = "${version}"\nversion = "${version}"`]) {
    assert.throws(() => projectVersion({ version }, moduleText), /version/i);
  }
});

test('local evidence records actual runtime and tested checkout without inventing CI state', () => {
  const result = executionMetadata({ version, git, runtime, env: {} });
  assert.equal(result.version, version);
  assert.equal(result.execution_environment, 'local');
  assert.equal(result.tested_sha, git.head);
  assert.equal(result.source_commit, git.head);
  assert.equal(result.source_state, 'committed_clean');
  assert.equal(result.platform, runtime.platform);
  assert.equal(result.architecture, runtime.architecture);
  assert.equal(result.node, runtime.node);
  assert.equal(result.os_release, runtime.os_release);
  assert.equal(result.github_actions, null);
  assert.equal(result.public_release, 'not_published_by_acceptance');
  assert.equal(Object.hasOwn(result, 'hosted_ci'), false);
  assert.equal(Object.hasOwn(result, 'passed'), false);
});

test('GitHub evidence distinguishes tested checkout from PR head and locates this run', () => {
  const result = executionMetadata({ version, git, runtime, env: {
    GITHUB_ACTIONS: 'true', GITHUB_HEAD_SHA: 'b'.repeat(40), GITHUB_RUN_ID: '12345',
    GITHUB_SERVER_URL: 'https://github.com', GITHUB_REPOSITORY: 'owner/project',
    GITHUB_TOKEN: 'secret-must-not-appear', UNRELATED: 'also-private',
  } });
  assert.equal(result.execution_environment, 'github_actions');
  assert.equal(result.tested_sha, git.head);
  assert.equal(result.github_actions.head_sha, 'b'.repeat(40));
  assert.equal(result.github_actions.run_id, '12345');
  assert.equal(result.github_actions.run_url, 'https://github.com/owner/project/actions/runs/12345');
  assert.equal(Object.hasOwn(result.github_actions, 'conclusion'), false);
  assert.doesNotMatch(JSON.stringify(result), /secret-must-not-appear|also-private/);
});

test('enterprise run URLs preserve server path and tolerate trailing slash', () => {
  const result = executionMetadata({ version, git, runtime, env: {
    GITHUB_ACTIONS: 'true', GITHUB_RUN_ID: '456', GITHUB_REPOSITORY: 'team/repo',
    GITHUB_SERVER_URL: 'https://github.example.test/',
  } });
  assert.equal(result.github_actions.run_url, 'https://github.example.test/team/repo/actions/runs/456');
  assert.equal(result.github_actions.head_sha, null);
});

test('incomplete or unsafe run identity does not fabricate a run URL', () => {
  for (const env of [
    { GITHUB_RUN_ID: '1', GITHUB_REPOSITORY: 'owner/repo' },
    { GITHUB_SERVER_URL: 'https://github.com', GITHUB_REPOSITORY: 'owner/repo' },
    { GITHUB_SERVER_URL: 'file:///private', GITHUB_REPOSITORY: 'owner/repo', GITHUB_RUN_ID: '1' },
    { GITHUB_SERVER_URL: 'https://user:password@github.com', GITHUB_REPOSITORY: 'owner/repo', GITHUB_RUN_ID: '1' },
    { GITHUB_SERVER_URL: 'https://github.com', GITHUB_REPOSITORY: '../repo', GITHUB_RUN_ID: '1' },
  ]) {
    const result = executionMetadata({ version, git, runtime, env: { GITHUB_ACTIONS: 'true', ...env } });
    assert.equal(result.github_actions.run_url, null);
    assert.doesNotMatch(JSON.stringify(result), /password/);
  }
});

test('environment variables alone cannot falsely mark a local process as Actions', () => {
  const result = executionMetadata({ version, git, runtime, env: {
    GITHUB_ACTIONS: 'false', GITHUB_RUN_ID: '123', GITHUB_REPOSITORY: 'owner/repo',
    GITHUB_SERVER_URL: 'https://github.com',
  } });
  assert.equal(result.execution_environment, 'local');
  assert.equal(result.github_actions, null);
});

test('dirty, unavailable, and unborn repositories never claim a clean committed source', () => {
  const states = [
    [{ ...git, status: ' M audit.mbt\n' }, 'modified_worktree'],
    [{ ...git, status_ok: false }, 'unknown_worktree_state'],
    [{ ...git, head: null }, 'uncommitted_new_project'],
    [{ own_repository: false, head: null }, 'no_project_repository'],
  ];
  for (const [state, expected] of states) {
    const result = executionMetadata({ version, git: state, runtime, env: {} });
    assert.equal(result.source_state, expected);
    assert.equal(result.tested_sha, state.head);
  }
});

test('acceptance requires every requested command, including toolchain capture, to succeed', () => {
  const labels = ['checks', 'demo', 'benchmark', 'consumer', 'toolchain'];
  const successful = labels.map(label => ({ label, exit_code: 0, signal: null }));
  assert.equal(stepsPassed(successful, labels), true);
  assert.equal(stepsPassed(successful.slice(0, -1), labels), false);
  assert.equal(stepsPassed([], labels), false);
  for (const failure of [{ exit_code: 1 }, { exit_code: null }, { signal: 'SIGTERM' }]) {
    assert.equal(stepsPassed(successful.map(step => step.label === 'toolchain' ? { ...step, ...failure } : step), labels), false);
  }
});

test('metadata collection reads the current checkout using its actual project files', async () => {
  const root = fileURLToPath(new URL('../', import.meta.url));
  const result = await collectEvidenceMetadata(root, {});
  assert.match(result.version, /^\d+\.\d+\.\d+/);
  assert.equal(result.node, process.version);
  assert.equal(result.platform, process.platform);
  assert.equal(result.execution_environment, 'local');
  assert.equal(result.source_commit, result.tested_sha);
});
