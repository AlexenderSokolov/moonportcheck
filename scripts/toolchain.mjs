// Project-local installer. It never updates a global toolchain or shell profile.
import { createHash } from 'node:crypto';
import { createReadStream, existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, delimiter } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const lock = JSON.parse(readFileSync(join(root, 'scripts', 'toolchain.lock.json'), 'utf8'));
const platform = process.platform === 'win32' && process.arch === 'x64'
  ? 'windows-x86_64'
  : process.platform === 'linux' && process.arch === 'x64' ? 'linux-x86_64' : null;
if (!platform) throw new Error('This release supports Windows x64 and Linux x64 toolchains.');
const home = join(root, '.toolchains', platform);
const ext = process.platform === 'win32' ? '.exe' : '';
const moon = join(home, 'bin', `moon${ext}`);
const env = { ...process.env, MOON_HOME: home, PATH: `${join(home, 'bin')}${delimiter}${process.env.PATH}` };

function run(file, args, capture = false) {
  const result = spawnSync(file, args, { cwd: root, env, encoding: 'utf8', stdio: capture ? 'pipe' : 'inherit' });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${file} exited with ${result.status}: ${result.stderr ?? ''}`);
  return (result.stdout ?? '') + (result.stderr ?? '');
}

function verifyNode() {
  if (Number(process.versions.node.split('.')[0]) !== lock.node_major) {
    throw new Error(`Node.js ${lock.node_major}.x is required; found ${process.version}.`);
  }
}

function verify(requireBundles = true) {
  verifyNode();
  if (!existsSync(moon)) throw new Error('Project MoonBit is missing. Run scripts/toolchain.ps1 -Install or bash scripts/toolchain.sh install.');
  const compiler = run(join(home, 'bin', `moonc${ext}`), ['-v'], true).trim();
  if (compiler !== lock.compiler) throw new Error(`Compiler drift: expected ${lock.compiler}; got ${compiler}.`);
  const actualMoon = run(moon, ['version'], true).trim();
  if (!actualMoon.startsWith(`moon ${lock.moon}`)) throw new Error(`Moon build-tool drift: ${actualMoon}`);
  const coreMod = join(home, 'lib', 'core', 'moon.mod');
  if (!existsSync(coreMod) || !readFileSync(coreMod, 'utf8').includes(`version = "${lock.core}"`)) {
    throw new Error(`Matching core ${lock.core} is missing. Run the project toolchain installer.`);
  }
  if (requireBundles) {
    for (const target of lock.core_targets) {
      const bundle = join(home, 'lib', 'core', '_build', target, 'release', 'bundle');
      const index = join(bundle, 'all_pkgs.json');
      if (!existsSync(index) || !existsSync(join(bundle, 'core.core'))) {
        throw new Error(`Standard-library bundle ${target} is missing. Re-run the project toolchain installer.`);
      }
      const packages = JSON.parse(readFileSync(index, 'utf8')).packages;
      if (!Array.isArray(packages) || packages.length === 0 || packages.some((pkg) => !existsSync(pkg.artifact))) {
        throw new Error(`Standard-library interfaces for ${target} are incomplete. Re-run the project toolchain installer.`);
      }
    }
  }
}

async function sha256(path) {
  const hash = createHash('sha256');
  for await (const chunk of createReadStream(path)) hash.update(chunk);
  return hash.digest('hex');
}

async function archive(spec) {
  const cache = join(root, '.toolchains', 'downloads');
  mkdirSync(cache, { recursive: true });
  const path = join(cache, spec.file);
  if (!existsSync(path)) {
    console.log(`Downloading ${spec.url}`);
    const response = await fetch(spec.url);
    if (!response.ok) throw new Error(`Download failed: HTTP ${response.status} for ${spec.url}`);
    writeFileSync(path, Buffer.from(await response.arrayBuffer()));
  }
  const actual = await sha256(path);
  if (actual !== spec.sha256) {
    throw new Error(`Archive hash mismatch for ${spec.file}. Expected ${spec.sha256}, got ${actual}. Nothing was extracted. The official latest URL may have changed; restore the pinned archive to ${path}. Do not update the hash to bypass this error.`);
  }
  return path;
}

async function install() {
  verifyNode();
  const spec = lock.platforms[platform];
  // Verify BOTH archives before extracting either one.
  const binary = await archive(spec.binary);
  const core = await archive(spec.core);
  mkdirSync(home, { recursive: true });
  run('tar', ['-xf', binary, '-C', home]);
  mkdirSync(join(home, 'lib'), { recursive: true });
  run('tar', ['-xf', core, '-C', join(home, 'lib')]);
  verify(false);
  // moon info writes the canonical interface using wasm by default even when
  // --target js is supplied. Bundle wasm as well as the supported test targets.
  for (const target of lock.core_targets) {
    run(moon, ['-C', join(home, 'lib', 'core'), 'bundle', '--warn-list', '-a', '--target', target]);
  }
  verify();
  console.log(`Pinned MoonBit installed in ${home}`);
}

try {
  const action = process.argv[2] ?? 'verify';
  if (action === 'install') await install();
  else if (action === 'verify') verify();
  else if (action === 'version') {
    verify();
    console.log(run(moon, ['version', '--all'], true).trim());
    console.log(`node ${process.version}`);
  } else throw new Error(`Unknown toolchain action: ${action}`);
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
