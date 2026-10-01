import test from 'node:test';
import assert from 'node:assert/strict';
import { copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const lock = JSON.parse(readFileSync(join(root, 'scripts/toolchain.lock.json'), 'utf8'));
const platform = process.platform === 'win32' ? 'windows-x86_64' : 'linux-x86_64';
const spec = lock.platforms[platform];
const archives = process.env.MOONPORT_TOOLCHAIN_CACHE || join(root, '.toolchains/downloads');

function fixture() {
  const dir = mkdtempSync(join(tmpdir(), 'moonport toolchain test '));
  mkdirSync(join(dir, 'scripts'));
  for (const file of ['toolchain.mjs', 'toolchain.lock.json']) {
    copyFileSync(join(root, 'scripts', file), join(dir, 'scripts', file));
  }
  const cache = join(dir, '.toolchains/downloads');
  mkdirSync(cache, { recursive: true });
  return { dir, cache, home: join(dir, '.toolchains', platform) };
}

function install(f, extra = {}) {
  const env = { ...process.env };
  delete env.MOONPORT_TOOLCHAIN_HOME;
  delete env.MOONPORT_TOOLCHAIN_CACHE;
  return spawnSync(process.execPath, [join(f.dir, 'scripts/toolchain.mjs'), 'install'], {
    cwd: f.dir, env: { ...env, ...extra }, encoding: 'utf8', timeout: 120000,
  });
}

test('rejects a corrupt binary before creating the installation directory', () => {
  const f = fixture();
  writeFileSync(join(f.cache, spec.binary.file), 'not the pinned archive');
  const result = install(f);
  assert.equal(result.status, 1);
  assert.match(result.stderr, /Archive hash mismatch/);
  assert.equal(existsSync(f.home), false);
});

test('explicit isolated cache and home override the project defaults', () => {
  const f = fixture();
  const selectedCache = join(f.dir, 'chosen cache');
  const selectedHome = join(f.dir, 'chosen home');
  mkdirSync(selectedCache);
  writeFileSync(join(f.cache, spec.binary.file), 'default poison');
  writeFileSync(join(selectedCache, spec.binary.file), 'selected poison');
  const result = install(f, {
    MOONPORT_TOOLCHAIN_HOME: selectedHome, MOONPORT_TOOLCHAIN_CACHE: selectedCache,
  });
  assert.equal(result.status, 1);
  assert.match(result.stderr, /Archive hash mismatch/);
  assert.ok(result.stderr.includes(join(selectedCache, spec.binary.file)), result.stderr);
  assert.equal(existsSync(selectedHome), false);
  assert.equal(existsSync(f.home), false);
});

test('a corrupt core prevents extraction of an otherwise valid binary archive', {
  skip: !existsSync(join(archives, spec.binary.file)) && 'pinned binary archive unavailable; cold-install covers download',
}, () => {
  const f = fixture();
  copyFileSync(join(archives, spec.binary.file), join(f.cache, spec.binary.file));
  writeFileSync(join(f.cache, spec.core.file), 'not the pinned core');
  const result = install(f);
  assert.equal(result.status, 1);
  assert.match(result.stderr, /Archive hash mismatch/);
  assert.ok(result.stderr.includes(spec.core.file));
  assert.equal(existsSync(f.home), false);
});

test('official Linux archive installs executable native commands on a POSIX filesystem', {
  skip: process.platform !== 'linux' ? 'POSIX permissions' :
    (!existsSync(join(archives, spec.binary.file)) || !existsSync(join(archives, spec.core.file))) && 'pinned archives unavailable',
}, () => {
  const f = fixture();
  for (const archive of [spec.binary, spec.core]) {
    copyFileSync(join(archives, archive.file), join(f.cache, archive.file));
  }
  const result = install(f);
  assert.equal(result.status, 0, result.stdout + result.stderr);
  for (const executable of ['moon', 'moonc', 'moonrun', 'moonfmt', 'mooninfo', 'internal/tcc']) {
    assert.notEqual(statSync(join(f.home, 'bin', executable)).mode & 0o100, 0, executable);
  }
  assert.equal(statSync(join(f.home, 'bin/moonlex.wasm')).mode & 0o111, 0);
});
