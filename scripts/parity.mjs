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
assert.equal(lines.length, 61);
const reports = lines.map(line => JSON.parse(line));
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
assert.deepEqual(reports.slice(49), [false, true, true, false, true, true, true, false, false, true, false, true]);
console.log(JSON.stringify({ parity: 'pass', targets: ['js', 'wasm-gc'], reports: reports.length, bytes: js.length, sha256: createHash('sha256').update(js).digest('hex') }, null, 2));
