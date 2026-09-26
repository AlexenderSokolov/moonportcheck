// A fresh cache proves that the immutable upstream URLs remain usable. A fresh
// POSIX /tmp installation also avoids Windows mount permission emulation.
import { createHash } from 'node:crypto';
import { appendFileSync, createReadStream, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const lock = JSON.parse(readFileSync(join(root, 'scripts/toolchain.lock.json'), 'utf8'));
const platform = process.platform === 'win32' ? 'windows-x86_64' : 'linux-x86_64';
const directory = mkdtempSync(join(tmpdir(), 'moonport-cold-install-'));
const home = join(directory, 'home');
const cache = join(directory, 'cache');
mkdirSync(cache);
const artifacts = join(root, 'artifacts');
mkdirSync(artifacts, { recursive: true });
const evidenceDirectory = mkdtempSync(join(artifacts, `cold-install-${platform}-`));
const env = { ...process.env, MOONPORT_TOOLCHAIN_HOME: home, MOONPORT_TOOLCHAIN_CACHE: cache };
const evidence = {
  schema_version: 1, platform, node: process.version, home, cache,
  cache_files_before: readdirSync(cache), compiler_expected: lock.compiler,
  started_at: new Date().toISOString(), archive_results: [], steps: [], passed: false,
};

function run(action) {
  const result = spawnSync(process.execPath, [join(root, 'scripts/toolchain.mjs'), action], {
    cwd: root, env, encoding: 'utf8', timeout: 600000, maxBuffer: 16 * 1024 * 1024,
  });
  const output = (result.stdout ?? '') + (result.stderr ?? '') + (result.error?.message ?? '');
  writeFileSync(join(evidenceDirectory, `${action}.log`), output);
  evidence.steps.push({ action, status: result.status, error: result.error?.message ?? null });
  if (result.status !== 0) throw new Error(`${action} failed: ${output}`);
  return output.trim();
}

try {
  run('install');
  evidence.versions = run('version');
  for (const spec of [lock.platforms[platform].binary, lock.platforms[platform].core]) {
    const hash = createHash('sha256');
    for await (const chunk of createReadStream(join(cache, spec.file))) hash.update(chunk);
    const actual = hash.digest('hex');
    evidence.archive_results.push({ url: spec.url, expected: spec.sha256, actual, matches: actual === spec.sha256 });
    if (actual !== spec.sha256) throw new Error('Downloaded archive hash changed after installation.');
  }
  evidence.bundles = lock.core_targets.map((target) => ({
    target, verified: existsSync(join(home, 'lib/core/_build', target, 'release/bundle/core.core')),
  }));
  evidence.passed = evidence.bundles.every((bundle) => bundle.verified);
  if (evidence.passed && process.env.GITHUB_ENV) {
    appendFileSync(process.env.GITHUB_ENV, `MOONPORT_TOOLCHAIN_HOME=${home}\nMOONPORT_TOOLCHAIN_CACHE=${cache}\n`);
  }
} catch (error) {
  evidence.passed = false;
  evidence.error = error.message;
  console.error(error.message);
  process.exitCode = 1;
} finally {
  evidence.finished_at = new Date().toISOString();
  writeFileSync(join(evidenceDirectory, 'evidence.json'), `${JSON.stringify(evidence, null, 2)}\n`);
  console.log(`Cold-install evidence: ${evidenceDirectory}`);
  if (!evidence.passed) process.exitCode = 1;
}
