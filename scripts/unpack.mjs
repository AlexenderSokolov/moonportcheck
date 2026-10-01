// M16 dual-OS unpack-and-run: extract the exact current candidate archive with the
// shared pure-Node reader, then execute the packaged CLI from the extracted
// tree under a runtime PATH that contains only Node's directory. Proves the
// candidate is self-contained (no compiler, no MOON_HOME) on the current OS.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { basename, dirname, join, posix, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { candidateArchiveName, parseZipEntries } from './zip-util.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const candidateDir = join(root, 'artifacts', 'candidate');

const expectedVersion = JSON.parse(readFileSync(join(root, 'package.json'), 'utf8')).version;
function currentArchive() {
  const head = spawnSync('git', ['rev-parse', '--short', 'HEAD'], { cwd: root, encoding: 'utf8' });
  assert.equal(head.status, 0, 'candidate verification requires a Git HEAD');
  return join(candidateDir, candidateArchiveName(expectedVersion, process.platform, head.stdout.trim()));
}

const archivePath = process.argv[2] ? resolve(process.argv[2]) : currentArchive();
const zip = readFileSync(archivePath);
const sha256 = createHash('sha256').update(zip).digest('hex');
const entries = parseZipEntries(zip);
const checksums = entries.get('CHECKSUMS.txt');
assert.ok(checksums, 'candidate must contain CHECKSUMS.txt');
const checked = new Set();
for (const line of checksums.data.toString('utf8').trim().split('\n')) {
  const match = /^([a-f0-9]{64})  (.+)$/.exec(line);
  assert.ok(match, `invalid checksum line ${line}`);
  const [, digest, name] = match;
  assert.ok(!checked.has(name), `duplicate checksum for ${name}`);
  assert.ok(entries.has(name), `checksum names missing entry ${name}`);
  assert.equal(createHash('sha256').update(entries.get(name).data).digest('hex'), digest, `sha256 mismatch for ${name}`);
  checked.add(name);
}
assert.equal(checked.size, entries.size - 1, 'checksums must cover every payload file');
assert.equal(JSON.parse(entries.get('package.json').data.toString('utf8')).version, expectedVersion, 'packaged version must match current source');

const work = join(root, 'artifacts', `unpack-${process.platform}-${Date.now()}`);
const target = join(work, 'pkg');
for (const [name, { data }] of entries) {
  const safe = posix.normalize(name);
  assert.ok(safe === name && !safe.startsWith('/') && !safe.startsWith('..') && !safe.includes('\0') && !safe.includes('\\') && !safe.includes(':'), `unsafe entry name ${name}`);
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
assert.equal(version, expectedVersion, 'running CLI must report current source version');
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
assert.ok(JSON.parse(invoke(['rules', '--format', 'json']).stdout).length > 0);
assert.equal(JSON.parse(invoke(['explain', 'NAME_RESERVED', '--format', 'json']).stdout)[0].code, 'NAME_RESERVED');
assert.equal(JSON.parse(invoke(['check', manifest, '--format', 'sarif'], 1).stdout).version, '2.1.0');
const delivery = join(work, 'delivery');
mkdirSync(delivery);
writeFileSync(join(delivery, 'ok.txt'), '');
writeFileSync(join(delivery, 'ignore.tmp'), '');
const config = join(work, 'config.json');
writeFileSync(config, JSON.stringify({ schema_version: 1, exclude: ['*.tmp'] }));
const scanned = JSON.parse(invoke(['scan', delivery, '--config', config, '--format', 'json']).stdout);
assert.equal(scanned.summary.entries, 1);
assert.equal(scanned.excluded_entries, 1);
assert.equal(JSON.parse(invoke(['scan', delivery, '--format', 'sarif']).stdout).version, '2.1.0');
const snapshot = join(work, 'snapshot.json');
writeFileSync(snapshot, invoke(['snapshot', delivery]).stdout);
assert.equal(JSON.parse(invoke(['check', snapshot, '--format', 'json']).stdout).source, 'snapshot');
assert.equal(JSON.parse(invoke(['diff', snapshot, snapshot, '--format', 'json']).stdout).changes.length, 0);
const reportFile = join(work, 'report.json');
writeFileSync(reportFile, invoke(['scan', delivery, '--format', 'json']).stdout);
const baselineFile = join(work, 'baseline.json');
writeFileSync(baselineFile, invoke(['baseline', 'create', reportFile]).stdout);
invoke(['scan', delivery, '--baseline', baselineFile, '--fail-on', 'new']);

console.log(JSON.stringify({
  unpack: 'ok',
  platform: process.platform,
  archive: basename(archivePath),
  sha256,
  entries: [...entries.keys()],
  version,
  findings_exit: 1,
  clean_exit: 0,
  public_commands: ['scan', 'check', 'snapshot', 'diff', 'baseline create', 'rules', 'explain'],
}, null, 2));
