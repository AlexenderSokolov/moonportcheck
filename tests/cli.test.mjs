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

test('CLI rule catalog explains every audit and scan code with remediation', () => {
  const listed = invoke('rules', '--format', 'json');
  assert.equal(listed.status, 0, listed.stdout);
  const catalog = JSON.parse(listed.stdout);
  assert.equal(catalog.length, 15);
  const codes = catalog.map(r => r.code);
  assert.deepEqual(codes, [...new Set(codes)].sort());
  for (const rule of catalog) {
    assert.ok(rule.reason.length > 0);
    assert.ok(rule.suggestion.length > 0);
    assert.ok(rule.examples.length > 0);
    const explained = invoke('explain', rule.code, '--format', 'json');
    assert.equal(explained.status, 0);
    assert.deepEqual(JSON.parse(explained.stdout), [rule]);
  }
  assert.match(invoke('rules').stdout, /PATH_KIND_CONFLICT/);
  assert.match(invoke('explain', 'NAME_RESERVED').stdout, /CON/);
});

test('CLI unknown rule and malformed catalog commands fail with input errors', () => {
  for (const args of [['explain', 'MISSING'], ['rules', 'extra'], ['explain'], ['explain', 'NAME_RESERVED', 'extra']]) {
    const result = invoke(...args, '--format', 'json');
    assert.equal(result.status, 2, JSON.stringify(args));
    assert.equal(JSON.parse(result.stdout).complete, false);
  }
  assert.equal(JSON.parse(invoke('explain', 'MISSING', '--format', 'json').stdout).error.code, 'RULE_UNKNOWN');
});

test('schema 2 reports retain all original members while bounding source examples', async () => {
  const entries = [{ path: 'artifact', kind: 'file' }, { path: 'artifact/report.txt', kind: 'file' }, { path: 'artifact/report.txt', kind: 'file' }];
  const report = JSON.parse(invoke('check', await manifest(entries), '--format', 'json').stdout);
  assert.equal(report.schema_version, 2);
  assert.deepEqual(report.scope, []);
  assert.equal(report.excluded_entries, 0);
  assert.deepEqual(report.pruned_directories, []);
  const conflict = report.diagnostics.find(d => d.code === 'PATH_KIND_CONFLICT');
  assert.equal(conflict.anchor, 'artifact');
  assert.deepEqual(JSON.parse(conflict.group_key), ['PATH_KIND_CONFLICT', 'artifact']);
  assert.deepEqual(conflict.members, [{ path: 'artifact', kind: 'file', count: 1 }, { path: 'artifact/report.txt', kind: 'file', count: 2 }]);
  assert.equal(conflict.source_total, 2);
  assert.equal(conflict.sources_truncated, false);
  assert.deepEqual(conflict.source_examples, conflict.members);
  const many = Array.from({ length: 20 }, (_, i) => ({ path: `A/${String(i).padStart(2, '0')}`, kind: 'file' }));
  many.push({ path: 'a/z', kind: 'file' });
  const grouped = JSON.parse(invoke('check', await manifest(many), '--format', 'json').stdout).diagnostics[0];
  assert.equal(grouped.members.length, 21);
  assert.equal(grouped.source_total, 21);
  assert.equal(grouped.source_examples.length, 5);
  assert.equal(grouped.sources_truncated, true);
  assert.ok(grouped.source_examples.some(m => m.path.startsWith('A/')));
  assert.ok(grouped.source_examples.some(m => m.path.startsWith('a/')));
});

test('CLI check --exclude filters entries and reports the scope', async () => {
  const filename = await manifest([
    { path: 'a.tmp', kind: 'file' },
    { path: 'cache', kind: 'directory' },
    { path: 'cache/x', kind: 'file' },
    { path: 'README', kind: 'file' },
  ]);
  const result = invoke('check', filename, '--exclude', '*.tmp', '--exclude', 'cache/', '--format', 'json');
  assert.equal(result.status, 0, result.stdout);
  const report = JSON.parse(result.stdout);
  assert.deepEqual(report.scope, ['*.tmp', 'cache/']);
  assert.equal(report.excluded_entries, 3);
  assert.deepEqual(report.pruned_directories, ['cache']);
  assert.equal(report.summary.entries, 1);
  assert.deepEqual(report.diagnostics, []);
});

test('CLI --config supplies exclusions and unifies with repeated --exclude', async () => {
  const root = await fixture();
  const config = path.join(root, 'moonportcheck.json');
  await fs.writeFile(config, '{"schema_version":1,"exclude":["*.tmp","cache/"]}');
  const filename = await manifest([
    { path: 'a.tmp', kind: 'file' },
    { path: 'cache', kind: 'directory' },
    { path: 'cache/x', kind: 'file' },
    { path: 'notes/a.tmp', kind: 'file' },
    { path: 'README', kind: 'file' },
  ]);
  const result = invoke('check', filename, '--config', config, '--exclude', '*.tmp', '--format', 'json');
  assert.equal(result.status, 0, result.stdout);
  const report = JSON.parse(result.stdout);
  // Duplicate literal patterns collapse; the union of config and CLI stays.
  assert.deepEqual(report.scope, ['*.tmp', 'cache/']);
  assert.equal(report.excluded_entries, 3);
  assert.deepEqual(report.pruned_directories, ['cache']);
  assert.equal(report.summary.entries, 2);
});

test('CLI config errors exit 2 and read failures exit 3', async () => {
  const root = await fixture();
  const filename = await manifest([{ path: 'x', kind: 'file' }]);
  for (const [contents, code] of [
    ['{"schema_version":2,"exclude":[]}', 'INPUT_CONFIG'],
    ['{"exclude":[]}', 'INPUT_CONFIG'],
    ['{"schema_version":1,"exclude":["a[b]"]}', 'PATTERN_INVALID'],
    ['{"schema_version":1,"exclude":["*.tmp"],"extra":1}', 'INPUT_CONFIG'],
    ['not json', 'INPUT_CONFIG'],
    ['42', 'INPUT_CONFIG'],
    ['{"schema_version":1,"exclude":5}', 'INPUT_CONFIG'],
  ]) {
    const file = path.join(root, `config-${contents.length}-${Math.random()}`);
    await fs.writeFile(file, contents);
    const result = invoke('check', filename, '--config', file, '--format', 'json');
    assert.equal(result.status, 2, contents);
    assert.match(result.stdout, new RegExp(code), contents);
    assert.doesNotThrow(() => JSON.parse(result.stdout));
  }
  const missing = invoke('check', filename, '--config', path.join(root, 'absent'), '--format', 'json');
  assert.equal(missing.status, 3, missing.stdout);
  assert.match(missing.stdout, /INPUT_IO_ERROR/);
  // Under --format text the same error is rendered as text, not a JSON payload.
  const textFile = path.join(root, 'config-text');
  await fs.writeFile(textFile, '{"schema_version":2,"exclude":[]}');
  const textResult = invoke('check', filename, '--config', textFile, '--format', 'text');
  assert.equal(textResult.status, 2, textResult.stdout);
  assert.doesNotThrow(() => {
    if (textResult.stdout.trim().startsWith('{')) JSON.parse(textResult.stdout);
  });
  assert.match(textResult.stdout, /INPUT_CONFIG/);
  assert.match(textResult.stdout, /MoonPortCheck error/);
});

test('CLI scan and check agree under the same exclusions', async () => {
  const root = await fixture();
  await fs.mkdir(path.join(root, 'cache'));
  await fs.mkdir(path.join(root, 'build'));
  await fs.mkdir(path.join(root, 'src'));
  await fs.writeFile(path.join(root, 'cache', 'x.bin'), '');
  await fs.writeFile(path.join(root, 'build', 'ok.txt'), '');
  await fs.writeFile(path.join(root, 'src', 'a.txt'), '');
  const args = ['--exclude', 'cache/', '--exclude', 'build'];
  const scanned = invoke('scan', root, ...args, '--format', 'json');
  assert.equal(scanned.status, 0, scanned.stdout);
  const scanReport = JSON.parse(scanned.stdout);
  assert.equal(scanReport.source, 'scan');
  // A pruned directory is still recorded as an entry but its subtree is not.
  assert.deepEqual(scanReport.pruned_directories, ['build', 'cache']);
  const filename = await manifest([
    { path: 'build', kind: 'directory' },
    { path: 'cache', kind: 'directory' },
    { path: 'src', kind: 'directory' },
    { path: 'src/a.txt', kind: 'file' },
  ]);
  const checked = JSON.parse(invoke('check', filename, ...args, '--format', 'json').stdout);
  assert.deepEqual(scanReport.diagnostics, checked.diagnostics);
  assert.deepEqual(scanReport.summary, checked.summary);
  assert.deepEqual(scanReport.scope, checked.scope);
  assert.deepEqual(scanReport.pruned_directories, checked.pruned_directories);
  assert.equal(checked.excluded_entries, 2);
});
