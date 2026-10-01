import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import { spawnSync } from 'node:child_process';

export function projectVersion(packageMetadata, moduleText) {
  const version = packageMetadata?.version;
  if (typeof version !== 'string' || !version.trim()) {
    throw new Error('package.json must contain a nonempty version string');
  }
  const matches = [...moduleText.matchAll(/^\s*version\s*=\s*"([^"\r\n]+)"\s*(?:#.*)?$/gm)];
  if (matches.length !== 1) throw new Error('moon.mod must contain exactly one version assignment');
  if (matches[0][1] !== version) {
    throw new Error(`Project version mismatch: package.json=${version}, moon.mod=${matches[0][1]}`);
  }
  return version;
}

function actionsIdentity(env) {
  let server = null;
  try {
    const parsed = new URL(env.GITHUB_SERVER_URL);
    if (['https:', 'http:'].includes(parsed.protocol) && !parsed.username && !parsed.password && !parsed.search && !parsed.hash) {
      server = parsed.href.replace(/\/+$/, '');
    }
  } catch { /* Missing or invalid identity cannot identify a public run. */ }
  const repository = typeof env.GITHUB_REPOSITORY === 'string' && /^[a-zA-Z0-9_-][a-zA-Z0-9_.-]*\/[a-zA-Z0-9_-][a-zA-Z0-9_.-]*$/.test(env.GITHUB_REPOSITORY)
    ? env.GITHUB_REPOSITORY : null;
  const runId = typeof env.GITHUB_RUN_ID === 'string' && /^\d+$/.test(env.GITHUB_RUN_ID) ? env.GITHUB_RUN_ID : null;
  const head = typeof env.GITHUB_HEAD_SHA === 'string' && /^[a-fA-F0-9]{40,64}$/.test(env.GITHUB_HEAD_SHA) ? env.GITHUB_HEAD_SHA : null;
  return {
    server_url: server, repository, run_id: runId, head_sha: head,
    run_url: server && repository && runId ? `${server}/${repository}/actions/runs/${runId}` : null,
  };
}

export function executionMetadata({ version, git, runtime, env = {} }) {
  const actions = env.GITHUB_ACTIONS === 'true';
  const sourceState = !git.own_repository ? 'no_project_repository'
    : !git.head ? 'uncommitted_new_project'
    : !git.status_ok ? 'unknown_worktree_state'
    : git.status ? 'modified_worktree' : 'committed_clean';
  return {
    product: 'MoonPortCheck', version,
    execution_environment: actions ? 'github_actions' : 'local',
    platform: runtime.platform, architecture: runtime.architecture,
    node: runtime.node, os_release: runtime.os_release,
    source_commit: git.head, tested_sha: git.head, source_state: sourceState,
    github_actions: actions ? actionsIdentity(env) : null,
    public_release: 'not_published_by_acceptance',
  };
}

export function stepsPassed(steps, expectedLabels) {
  return expectedLabels.length > 0 && steps.length === expectedLabels.length
    && expectedLabels.every((label, index) => steps[index].label === label
      && steps[index].exit_code === 0 && !steps[index].signal);
}

export async function collectEvidenceMetadata(root, env = process.env) {
  const [packageText, moduleText] = await Promise.all([
    fs.readFile(path.join(root, 'package.json'), 'utf8'),
    fs.readFile(path.join(root, 'moon.mod'), 'utf8'),
  ]);
  const version = projectVersion(JSON.parse(packageText), moduleText);
  function gitCommand(args) {
    return spawnSync('git', ['--no-optional-locks', ...args], { cwd: root, encoding: 'utf8' });
  }
  function comparable(directory) {
    const resolved = path.resolve(directory);
    return process.platform === 'win32' ? resolved.toLowerCase() : resolved;
  }
  const top = gitCommand(['rev-parse', '--show-toplevel']);
  const ownRepository = top.status === 0 && comparable(top.stdout.trim()) === comparable(root);
  const head = ownRepository ? gitCommand(['rev-parse', '--verify', 'HEAD']) : null;
  const status = ownRepository ? gitCommand(['status', '--porcelain']) : null;
  return executionMetadata({
    version, env,
    git: {
      own_repository: ownRepository, head: head?.status === 0 ? head.stdout.trim() : null,
      status: status?.stdout || '', status_ok: status?.status === 0,
    },
    runtime: { platform: process.platform, architecture: process.arch, node: process.version, os_release: os.release() },
  });
}
