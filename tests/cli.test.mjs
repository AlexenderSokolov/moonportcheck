import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const cli = fileURLToPath(new URL('../bin/moonportcheck.mjs', import.meta.url));
const fixture = () => fs.mkdtemp(path.join(os.tmpdir(), 'moonportcheck-cli-'));
function invoke(...args) {
  const result = spawnSync(process.execPath, [cli, ...args], { encoding: 'utf8' });
  assert.equal(result.error, undefined);
  assert.equal(result.signal, null);
  assert.equal(result.stderr, '', result.stderr);
  return result;
}
async function manifest(entries) {
  const root = await fixture();
  const filename = path.join(root, 'paths.json');
  await fs.writeFile(filename, JSON.stringify(entries));
  return filename;
}

test('CLI help and version are standalone and match package version', async () => {
  assert.match(invoke('--help').stdout, /scan[\s\S]*check/);
  const version = JSON.parse(await fs.readFile(new URL('../package.json', import.meta.url), 'utf8')).version;
  assert.equal(invoke('--version').stdout.trim(), version);
});

test('CLI valid manifest, Chinese names and spaces pass', async () => {
  const filename = await manifest([{ path: '中文/file name.txt', kind: 'file' }, { path: '.hidden', kind: 'file' }]);
  const result = invoke('check', filename, '--format', 'json');
  assert.equal(result.status, 0, result.stdout);
  const report = JSON.parse(result.stdout);
  assert.equal(report.complete, true);
  assert.equal(report.source, 'manifest');
  assert.deepEqual(report.diagnostics, []);
  assert.equal(report.summary.entries, 2);
});

test('CLI invalid paths in valid JSON are findings, not malformed input', async () => {
  const filename = await manifest([{ path: 'CON.txt', kind: 'file' }, { path: '', kind: 'file' }]);
  const result = invoke('check', filename, '--format', 'json');
  assert.equal(result.status, 1, result.stdout);
  assert.ok(JSON.parse(result.stdout).diagnostics.some((issue) => issue.code === 'NAME_RESERVED'));
  assert.match(invoke('check', filename).stdout, /NAME_RESERVED/);
});

test('CLI malformed JSON, schema, arguments and UTF-8 exit 2; read failures exit 3', async () => {
  const root = await fixture();
  for (const [name, contents, code] of [
    ['json', '{', 'INPUT_JSON'],
    ['schema', '[{"path":"x","kind":"symlink"}]', 'INPUT_SCHEMA'],
    ['utf8', Buffer.from([0xff]), 'INPUT_ENCODING'],
  ]) {
    const filename = path.join(root, name);
    await fs.writeFile(filename, contents);
    const result = invoke('check', filename, '--format', 'json');
    assert.equal(result.status, 2, result.stdout);
    assert.match(result.stdout, new RegExp(code));
    assert.doesNotThrow(() => JSON.parse(result.stdout));
  }
  const badArgs = invoke('check', 'file', '--unknown', '--format', 'json');
  assert.equal(badArgs.status, 2);
  assert.match(badArgs.stdout, /ARGUMENT_ERROR/);
  assert.doesNotThrow(() => JSON.parse(badArgs.stdout));
  const missing = invoke('check', path.join(root, 'missing'), '--format', 'json');
  assert.equal(missing.status, 3);
  assert.match(missing.stdout, /INPUT_IO_ERROR/);
  assert.ok(!missing.stdout.includes(root));
});

test('CLI scan includes hidden and nested files and agrees with equivalent manifest', async () => {
  const root = await fixture();
  await fs.mkdir(path.join(root, 'data'));
  await fs.writeFile(path.join(root, 'data', 'ok.txt'), '');
  await fs.writeFile(path.join(root, '.hidden'), '');
  const scanned = invoke('scan', root, '--format', 'json');
  assert.equal(scanned.status, 0, scanned.stdout);
  const report = JSON.parse(scanned.stdout);
  assert.equal(report.source, 'scan');
  assert.equal(report.complete, true);
  assert.equal(report.summary.entries, 3);
  const filename = await manifest([{ path: 'data', kind: 'directory' }, { path: 'data/ok.txt', kind: 'file' }, { path: '.hidden', kind: 'file' }]);
  const checked = JSON.parse(invoke('check', filename, '--format', 'json').stdout);
  assert.deepEqual(report.diagnostics, checked.diagnostics);
  assert.deepEqual(report.summary, checked.summary);
});

test('CLI junction or symlink scan is incomplete and exit 3 takes precedence over findings', async () => {
  const root = await fixture();
  const outside = await fixture();
  await fs.mkdir(path.join(root, 'Data'));
  await fs.symlink(outside, path.join(root, 'link'), process.platform === 'win32' ? 'junction' : 'dir');
  // A Windows filesystem cannot reliably create every invalid name; Linux verifies both in one real scan.
  if (process.platform !== 'win32') await fs.writeFile(path.join(root, 'CON.txt'), '');
  const result = invoke('scan', root, '--format', 'json');
  assert.equal(result.status, 3, result.stdout);
  const report = JSON.parse(result.stdout);
  assert.equal(report.complete, false);
  assert.ok(report.summary.scan_issues > 0);
  assert.match(result.stdout, /SCAN_LINK_SKIPPED/);
  if (process.platform !== 'win32') assert.ok(report.diagnostics.some((issue) => issue.code === 'NAME_RESERVED'));
});

test('CLI Linux scan detects actual bad names and non-UTF-8 names', { skip: process.platform === 'win32' }, async () => {
  const root = await fixture();
  await fs.writeFile(path.join(root, 'CON.txt'), '');
  await fs.writeFile(path.join(root, 'name.'), '');
  await fs.writeFile(path.join(root, 'bad\\name'), '');
  await fs.mkdir(path.join(root, 'Data'));
  await fs.mkdir(path.join(root, 'data'));
  let result = invoke('scan', root, '--format', 'json');
  assert.equal(result.status, 1, result.stdout);
  const codes = JSON.parse(result.stdout).diagnostics.map((issue) => issue.code);
  for (const code of ['NAME_RESERVED', 'NAME_TRAILING_DOT_SPACE', 'NAME_INVALID_CHAR', 'PATH_CASE_COLLISION']) assert.ok(codes.includes(code), code);
  await fs.writeFile(Buffer.concat([Buffer.from(root + '/'), Buffer.from([0xff])]), '');
  result = invoke('scan', root, '--format', 'json');
  assert.equal(result.status, 3, result.stdout);
  assert.equal(JSON.parse(result.stdout).complete, false);
  assert.match(result.stdout, /SCAN_NAME_ENCODING/);
});

test('CLI report order is deterministic across shuffled input', async () => {
  const entries = [{ path: 'Data/a', kind: 'file' }, { path: 'data/b', kind: 'file' }, { path: 'NUL', kind: 'file' }, { path: 'NUL', kind: 'file' }];
  const first = invoke('check', await manifest(entries), '--format', 'json');
  const second = invoke('check', await manifest(entries.toReversed()), '--format', 'json');
  assert.equal(first.status, 1);
  assert.equal(second.stdout, first.stdout);
});
