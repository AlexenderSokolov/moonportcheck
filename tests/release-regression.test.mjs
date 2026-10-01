import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const cli = fileURLToPath(new URL('../bin/moonportcheck.mjs', import.meta.url));
const fixture = () => fs.mkdtemp(path.join(os.tmpdir(), 'moonportcheck-release-'));
function invoke(...args) {
  const result = spawnSync(process.execPath, [cli, ...args], { encoding: 'utf8' });
  assert.equal(result.error, undefined);
  assert.equal(result.signal, null);
  assert.equal(result.stderr, '');
  return result;
}

test('scan and check expose SARIF through the public CLI, including baseline policy', async () => {
  const root = await fixture();
  await fs.writeFile(path.join(root, 'CON.txt'), '');
  const scan = invoke('scan', root, '--format', 'sarif');
  assert.equal(scan.status, 1, scan.stdout);
  assert.equal(JSON.parse(scan.stdout).version, '2.1.0');
  const version = JSON.parse(await fs.readFile(new URL('../package.json', import.meta.url), 'utf8')).version;
  assert.equal(JSON.parse(scan.stdout).runs[0].tool.driver.version, version);
  assert.ok(JSON.parse(scan.stdout).runs[0].results.some(r => r.ruleId === 'NAME_RESERVED'));
  const compatible = invoke('scan', root, '--report', 'sarif');
  assert.equal(compatible.status, scan.status, compatible.stdout);
  assert.deepEqual(JSON.parse(compatible.stdout), JSON.parse(scan.stdout));
  const files = await fixture();
  const manifest = path.join(files, 'manifest.json');
  await fs.writeFile(manifest, JSON.stringify([{ path: 'CON.txt', kind: 'file' }]));
  const checked = invoke('check', manifest, '--format', 'sarif');
  assert.equal(checked.status, 1, checked.stdout);
  assert.equal(JSON.parse(checked.stdout).version, '2.1.0');
  const reportFile = path.join(files, 'report.json');
  await fs.writeFile(reportFile, invoke('scan', root, '--format', 'json').stdout);
  const baseline = invoke('baseline', 'create', reportFile);
  assert.equal(baseline.status, 0, baseline.stdout);
  const baselineFile = path.join(files, 'baseline.json');
  await fs.writeFile(baselineFile, baseline.stdout);
  const existing = invoke('scan', root, '--baseline', baselineFile, '--fail-on', 'new', '--format', 'sarif');
  assert.equal(existing.status, 0, existing.stdout);
  assert.ok(JSON.parse(existing.stdout).runs[0].results.some(r => r.ruleId === 'NAME_RESERVED'));
  assert.equal(JSON.parse(existing.stdout).properties.baseline.changes[0].status, 'existing');
  await fs.writeFile(path.join(root, 'NUL.txt'), '');
  const added = invoke('scan', root, '--baseline', baselineFile, '--fail-on', 'new', '--format', 'json');
  assert.equal(added.status, 1, added.stdout);
  assert.deepEqual(JSON.parse(added.stdout).baseline.changes.map(c => c.status), ['new', 'existing']);
  const newReport = path.join(files, 'classified.json');
  await fs.writeFile(newReport, added.stdout);
  assert.equal(invoke('baseline', 'create', newReport).status, 0, 'classified reports can create a new baseline');
  const cleanRoot = await fixture();
  const resolved = invoke('scan', cleanRoot, '--baseline', baselineFile, '--fail-on', 'new', '--format', 'json');
  assert.equal(resolved.status, 0, resolved.stdout);
  assert.equal(JSON.parse(resolved.stdout).baseline.changes[0].status, 'resolved');
  const partial = invoke('scan', path.join(root, 'missing'), '--baseline', baselineFile, '--fail-on', 'new', '--format', 'sarif');
  assert.equal(partial.status, 3, partial.stdout);
  assert.equal(JSON.parse(partial.stdout).runs[0].invocations[0].executionSuccessful, false);
});

test('snapshot parsing rejects contradictory completeness and duplicate paths', async () => {
  const root = await fixture();
  const base = { format: 'moonportcheck-snapshot', version: 1,
    profile: 'portable-windows-v1', complete: true, scope: [], entries: [], scan_issues: [] };
  for (const extra of [
    { entries: [{ path: 'x', kind: 'directory' }, { path: 'x', kind: 'file' }] },
    { scan_issues: [{ code: 'SCAN_IO_ERROR', path: 'x', message: 'Unreadable.' }] },
  ]) {
    const file = path.join(root, 'invalid.json');
    await fs.writeFile(file, JSON.stringify({ ...base, ...extra }));
    assert.equal(invoke('check', file, '--format', 'json').status, 2);
    assert.equal(invoke('diff', file, file, '--format', 'json').status, 2);
  }
});

test('diff ignores changes outside the inherited snapshot scope', async () => {
  const root = await fixture();
  const make = p => JSON.stringify({ format: 'moonportcheck-snapshot', version: 1,
    profile: 'portable-windows-v1', complete: true, scope: ['*.tmp'],
    entries: [{ path: p, kind: 'file' }], scan_issues: [] });
  const before = path.join(root, 'before.json');
  const after = path.join(root, 'after.json');
  await fs.writeFile(before, make('a.tmp'));
  await fs.writeFile(after, make('b.tmp'));
  const result = invoke('diff', before, after, '--format', 'json');
  assert.equal(result.status, 0, result.stdout);
  assert.deepEqual(JSON.parse(result.stdout).changes, []);
});

test('snapshot completeness cannot be inferred from an empty issue list', async () => {
  const root = await fixture();
  const snapshot = path.join(root, 'snapshot.json');
  await fs.writeFile(snapshot, JSON.stringify({ format: 'moonportcheck-snapshot', version: 1,
    profile: 'portable-windows-v1', complete: false, scope: [], entries: [], scan_issues: [] }));
  for (const format of ['json', 'markdown', 'sarif']) {
    const result = invoke('check', snapshot, '--format', format);
    assert.equal(result.status, 3, result.stdout);
    if (format === 'json') assert.equal(JSON.parse(result.stdout).complete, false);
    if (format === 'sarif') assert.equal(JSON.parse(result.stdout).runs[0].invocations[0].executionSuccessful, false);
  }
});

test('SARIF keeps malformed paths as evidence without navigable locations', async () => {
  const root = await fixture();
  const file = path.join(root, 'manifest.json');
  await fs.writeFile(file, JSON.stringify(['../outside', '/absolute', 'a//b', '', 'CON.txt'].map(p => ({ path: p, kind: 'file' }))));
  const result = invoke('check', file, '--format', 'sarif');
  assert.equal(result.status, 1, result.stdout);
  const results = JSON.parse(result.stdout).runs[0].results;
  for (const item of results.filter(r => r.ruleId.startsWith('PATH_'))) {
    assert.equal(item.locations, undefined, item.ruleId);
    assert.equal(item.relatedLocations, undefined, item.ruleId);
    assert.ok(item.properties, 'raw path evidence must remain available');
  }
  assert.equal(results.find(r => r.ruleId === 'NAME_RESERVED').locations[0].physicalLocation.artifactLocation.uri, 'CON.txt');
});
