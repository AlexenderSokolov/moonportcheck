// M16 dual-OS unpack-and-run: extract the newest candidate archive with the
// shared pure-Node reader, then execute the packaged CLI from the extracted
// tree under a runtime PATH that contains only Node's directory. Proves the
// candidate is self-contained (no compiler, no MOON_HOME) on the current OS.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdirSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { dirname, join, posix, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { parseZipEntries } from './zip-util.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const candidateDir = join(root, 'artifacts', 'candidate');

function newestArchive() {
  const zips = readdirSync(candidateDir).filter((name) => name.endsWith('.zip'));
  assert.ok(zips.length > 0, 'no candidate archive under artifacts/candidate');
  zips.sort();
  return resolve(candidateDir, zips[zips.length - 1]);
}

const archivePath = process.argv[2] ? resolve(process.argv[2]) : newestArchive();
const zip = readFileSync(archivePath);
const sha256 = createHash('sha256').update(zip).digest('hex');
const entries = parseZipEntries(zip);

const work = join(root, 'artifacts', `unpack-${process.platform}-${Date.now()}`);
const target = join(work, 'pkg');
for (const [name, { data }] of entries) {
  const safe = posix.normalize(name).replace(/^([/\\])+/, '');
  assert.ok(!safe.startsWith('..') && !safe.includes('\0'), `unsafe entry name ${name}`);
  const destination = resolve(target, ...safe.split('/'));
  mkdirSync(dirname(destination), { recursive: true });
  writeFileSync(destination, data);
}

// Run the extracted CLI with only Node's directory on PATH and no MOON_HOME.
const runtimeEnv = Object.fromEntries(Object.entries(process.env).filter(([key]) => key.toLowerCase() !== 'path' && key !== 'MOON_HOME'));
runtimeEnv.PATH = dirname(process.execPath);
const cli = join(target, 'bin', 'moonportcheck.mjs');

function invoke(args, expected = 0) {
  const result = spawnSync(process.execPath, [cli, ...args], { cwd: target, env: runtimeEnv, encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 });
  if (result.error) throw result.error;
  assert.equal(result.signal, null, `unexpected signal for ${args.join(' ')}`);
  assert.equal(result.status, expected, `expected exit ${expected} for ${args.join(' ')}\n${result.stdout}\n${result.stderr}`);
  return result;
}

const version = invoke(['--version']).stdout.trim();
const manifest = join(work, 'hostile.json');
writeFileSync(manifest, JSON.stringify([{ path: 'CON.txt', kind: 'file' }, { path: '中文/ok.txt', kind: 'file' }]));
const findings = invoke(['check', manifest, '--format', 'json'], 1);
const report = JSON.parse(findings.stdout);
assert.equal(report.complete, true);
assert.deepEqual(report.diagnostics.map((item) => item.code), ['NAME_RESERVED']);
const clean = join(work, 'clean.json');
writeFileSync(clean, JSON.stringify([{ path: '中文/ok.txt', kind: 'file' }]));
const pass = invoke(['check', clean, '--format', 'markdown']);
assert.ok(pass.stdout.includes('# MoonPortCheck report'));

console.log(JSON.stringify({
  unpack: 'ok',
  platform: process.platform,
  archive: posix.basename(archivePath),
  sha256,
  entries: [...entries.keys()],
  version,
  findings_exit: 1,
  clean_exit: 0,
}, null, 2));
