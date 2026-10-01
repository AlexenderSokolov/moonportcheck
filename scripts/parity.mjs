import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
function run(target) {
  const child = spawnSync('moon', ['run', '--target', target, '--release', '--deny-warn', 'cmd/parity'], { cwd: root, maxBuffer: 16 * 1024 * 1024 });
  if (child.error) throw child.error;
  assert.equal(child.status, 0, child.stderr.toString());
  return child.stdout;
}
const wasm = run('wasm-gc');
const js = run('js');
assert.deepEqual(js, wasm, 'serialized reports differ between JS and wasm-gc');
const lines = js.toString('utf8').trimEnd().split('\n');
assert.equal(lines.length, 72);
const reports = lines.map(line => JSON.parse(line));
assert.deepEqual(reports[71], reports[69], 'baseline create round-trip rebuilds the identical document');
for (let i = 0; i < 22; i += 2) assert.equal(lines[i], lines[i + 1], 'input order changed report');
assert.equal(reports[0].summary.entries, 0);
assert.equal(reports[2].diagnostics.length, 0);
assert.ok(reports[4].diagnostics.some(d => d.code === 'NAME_RESERVED'));
assert.ok(reports[22].diagnostics.some(d => d.code === 'PATH_KIND_CONFLICT'));
assert.equal(lines[23], lines[24], 'catalog input order changed rendering');
assert.equal(reports[23].length, 15);
for (let i = 25; i < 47; i += 2) {
  assert.equal(lines[i], lines[i + 1], 'input order changed detailed report');
  assert.equal(reports[i].schema_version, 2);
}
const kindConflict = reports[47].diagnostics.find(d => d.code === 'PATH_KIND_CONFLICT');
assert.equal(kindConflict.members.length, 2);
assert.equal(kindConflict.members[1].count, 2);
assert.equal(reports[48].complete, false);
assert.equal(reports[48].scan_issues.length, 1);
assert.deepEqual(reports.slice(49, 61), [false, true, true, false, true, true, true, false, false, true, false, true]);
assert.equal(lines[61], lines[62], 'scope input order changed report');
assert.equal(reports[61].schema_version, 2);
assert.deepEqual(reports[61].scope, ['*.tmp', 'cache/']);
assert.equal(reports[61].excluded_entries, 3);
assert.deepEqual(reports[61].pruned_directories, ['cache']);
assert.equal(reports[61].diagnostics.length, 0);
assert.equal(reports[61].summary.entries, 2);
assert.equal(lines[63], lines[64], 'scope input order changed report');
assert.deepEqual(reports[63].scope, ['**']);
assert.equal(reports[63].excluded_entries, 2);
assert.deepEqual(reports[63].pruned_directories, ['ok']);
assert.ok(reports[63].diagnostics.some(d => d.code === 'PATH_ABSOLUTE'));
assert.equal(reports[63].summary.entries, 1);
assert.equal(lines[65], lines[66], 'snapshot render must be stable after a parse round trip');
assert.equal(reports[65].format, 'moonportcheck-snapshot');
assert.equal(reports[65].version, 1);
assert.equal(reports[65].profile, 'portable-windows-v1');
assert.equal(reports[65].complete, false);
assert.deepEqual(reports[65].scope, ['*.tmp', 'cache/']);
assert.deepEqual(reports[65].entries.map(e => `${e.path}:${e.kind}`), ['results.tmp:file', '数据:directory', '目录/a.txt:file']);
assert.equal(reports[65].scan_issues.length, 1);
assert.equal(reports[67].source, 'snapshot');
assert.equal(reports[67].complete, true);
assert.deepEqual(reports[67].scope, ['*.tmp', 'cache/', 'results.tmp']);
assert.equal(reports[67].summary.entries, 1);
assert.equal(reports[67].summary.files, 1);
assert.equal(reports[67].summary.diagnostic_groups, 1);
assert.equal(reports[67].excluded_entries, 3);
assert.deepEqual(reports[67].pruned_directories, ['cache']);
assert.ok(reports[67].diagnostics.some(d => d.code === 'NAME_RESERVED'));
assert.equal(reports[68].format, 'moonportcheck-diff');
assert.equal(reports[68].version, 1);
assert.equal(reports[68].complete, true);
assert.deepEqual(reports[68].changes.map(c => [c.kind, c.path, c.paired_with, c.before_kind, c.after_kind]), [
  ['added', 'new.tmp', '', '', 'file'],
  ['kind', 'C.txt', '', 'file', 'directory'],
  ['case', 'A.txt', 'a.txt', 'file', 'file'],
]);
assert.equal(reports[69].format, 'moonportcheck-baseline');
assert.equal(reports[69].schema_version, 1);
assert.equal(reports[69].profile, 'portable-windows-v1');
assert.equal(reports[69].rules_version, '1');
assert.deepEqual(reports[69].scope, ['*.tmp', 'cache/', 'results.tmp']);
assert.deepEqual(reports[69].groups, [
  { code: 'NAME_RESERVED', anchor: 'CON.txt', members: [{ path: 'CON.txt', kind: 'file', count: 1 }], source_total: 1 },
]);
assert.equal(reports[70].format, 'moonportcheck-baseline-diff');
assert.deepEqual(reports[70].changes.map(c => [c.code, c.anchor, c.status, c.source_total]), [
  ['NAME_RESERVED', 'CON.txt', 'resolved', 0],
]);
assert.deepEqual(reports[70].changes[0].members, []);
console.log(JSON.stringify({ parity: 'pass', targets: ['js', 'wasm-gc'], reports: reports.length, bytes: js.length, sha256: createHash('sha256').update(js).digest('hex') }, null, 2));
