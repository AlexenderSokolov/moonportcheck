import test from 'node:test';
import assert from 'node:assert/strict';
import { run_request } from '../dist/bridge.js';

const run = request => JSON.parse(run_request(JSON.stringify(request)));
test('partial scan takes precedence over valid findings on every OS', () => {
  const result = run({ mode: 'scan', format: 'json', entries: [{ path: 'CON.txt', kind: 'file' }], scan_issues: [{ code: 'SCAN_IO_ERROR', path: 'closed', message: 'Cannot enumerate directory (EACCES).' }] });
  const report = JSON.parse(result.output);
  assert.equal(result.exit_code, 3);
  assert.equal(report.complete, false);
  assert.equal(report.source, 'scan');
  assert.equal(report.summary.files, 1);
  assert.equal(report.summary.scan_issues, 1);
  assert.equal(report.schema_version, 2);
  assert.deepEqual(report.diagnostics.map(d => d.code), ['NAME_RESERVED']);
  assert.deepEqual(report.scan_issues.map(d => d.code), ['SCAN_IO_ERROR']);
  assert.equal(report.summary.diagnostic_groups, 1);
  assert.equal(report.scan_issues[0].path, 'closed');
  assert.equal(report.scan_issues[0].members, undefined, 'scan failures must not invent entry kinds');
});
test('empty inaccessible scan cannot pass as an empty directory', () => {
  const result = run({ mode: 'scan', format: 'text', entries: [], scan_issues: [{ code: 'SCAN_IO_ERROR', path: '.', message: 'Cannot enumerate directory (EACCES).' }] });
  assert.equal(result.exit_code, 3);
  assert.match(result.output, /INCOMPLETE/);
});
test('protocol errors return usable structured input errors', () => {
  for (const value of [null, [], {}, { mode: 'unknown', format: 'json' }, { mode: 'check', format: 'json' }, { mode: 'scan', format: 'json', entries: [], scan_issues: [null] }]) {
    const response = run(value);
    assert.equal(response.exit_code, 2);
    assert.equal(JSON.parse(response.output).complete, false);
  }
  assert.equal(JSON.parse(run_request('{')).exit_code, 2);
});

test('scope mode validates config plus CLI exclusions and returns a merged scope', () => {
  const ok = run({ mode: 'scope', format: 'json', config_text: '{"schema_version":1,"exclude":["cache/","*.tmp"]}', cli_exclude: ['*.tmp', 'build'] });
  assert.equal(ok.exit_code, 0);
  assert.deepEqual(JSON.parse(ok.output), { patterns: ['*.tmp', 'build', 'cache/'] });
  const empty = run({ mode: 'scope', format: 'json' });
  assert.equal(empty.exit_code, 0);
  assert.deepEqual(JSON.parse(empty.output), { patterns: [] });
  for (const [request, code] of [
    [{ mode: 'scope', format: 'json', config_text: '{"schema_version":2,"exclude":[]}' }, 'INPUT_CONFIG'],
    [{ mode: 'scope', format: 'json', config_text: 'no' }, 'INPUT_CONFIG'],
    [{ mode: 'scope', format: 'json', config_text: '{"schema_version":1,"exclude":["a[b]"]}' }, 'PATTERN_INVALID'],
    [{ mode: 'scope', format: 'json', config_text: '{"schema_version":1,"exclude":[false]}' }, 'INPUT_CONFIG'],
    [{ mode: 'scope', format: 'json', cli_exclude: ['bad\\pattern'] }, 'PATTERN_INVALID'],
    [{ mode: 'scope', format: 'json', cli_exclude: [5] }, 'INPUT_SCHEMA'],
  ]) {
    const response = run(request);
    assert.equal(response.exit_code, 2, JSON.stringify(request));
    assert.equal(JSON.parse(response.output).error.code, code, JSON.stringify(request));
  }
});

test('excluded mode queries the same MoonBit matcher used for pruning', () => {
  const exclude = ['cache/', '*.tmp'];
  assert.equal(run({ mode: 'excluded', format: 'json', patterns: exclude, path: 'cache', kind: 'directory' }).output, 'true');
  assert.equal(run({ mode: 'excluded', format: 'json', patterns: exclude, path: 'cache/x.bin', kind: 'file' }).output, 'true');
  assert.equal(run({ mode: 'excluded', format: 'json', patterns: exclude, path: 'a.tmp', kind: 'file' }).output, 'true');
  assert.equal(run({ mode: 'excluded', format: 'json', patterns: exclude, path: 'notes/a.tmp', kind: 'file' }).output, 'false');
  assert.equal(run({ mode: 'excluded', format: 'json', patterns: exclude, path: 'src/a.txt', kind: 'file' }).output, 'false');
  assert.equal(run({ mode: 'excluded', format: 'json', patterns: [], path: 'x', kind: 'file' }).output, 'false');
  assert.equal(run({ mode: 'excluded', format: 'json', patterns: ['*'], path: 'x', kind: 'symlink' }).exit_code, 2);
});

test('check accepts exclusions and carries scope fields into schema 2', () => {
  const result = run({ mode: 'check', format: 'json', exclude_patterns: ['**/cache'], manifest_text: '[{"path":"cache","kind":"directory"},{"path":"cache/x","kind":"file"},{"path":"README","kind":"file"}]' });
  assert.equal(result.exit_code, 0, result.output);
  const report = JSON.parse(result.output);
  assert.deepEqual(report.scope, ['**/cache']);
  assert.equal(report.excluded_entries, 2);
  assert.deepEqual(report.pruned_directories, ['cache']);
  assert.equal(report.summary.entries, 1);
});

test('scan accepts exclusions and incomplete scans still exit 3', () => {
  const result = run({ mode: 'scan', format: 'json', exclude_patterns: ['*.tmp'], scan_issues: [{ code: 'SCAN_IO_ERROR', path: 'closed', message: 'Cannot enumerate directory (EACCES).' }], entries: [{ path: 'a.tmp', kind: 'file' }, { path: 'b.txt', kind: 'file' }] });
  assert.equal(result.exit_code, 3, result.output);
  const report = JSON.parse(result.output);
  assert.equal(report.complete, false);
  assert.equal(report.excluded_entries, 1);
  assert.deepEqual(report.scope, ['*.tmp']);
  assert.equal(report.summary.entries, 1);
});
