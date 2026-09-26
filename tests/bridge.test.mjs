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
  assert.deepEqual(report.diagnostics.map(d => d.code), ['NAME_RESERVED', 'SCAN_IO_ERROR']);
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
