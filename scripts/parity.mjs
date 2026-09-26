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
assert.equal(lines.length, 25);
const reports = lines.map(line => JSON.parse(line));
for (let i = 0; i < 22; i += 2) assert.equal(lines[i], lines[i + 1], 'input order changed report');
assert.equal(reports[0].summary.entries, 0);
assert.equal(reports[2].diagnostics.length, 0);
assert.ok(reports[4].diagnostics.some(d => d.code === 'NAME_RESERVED'));
assert.ok(reports[22].diagnostics.some(d => d.code === 'PATH_KIND_CONFLICT'));
assert.equal(lines[23], lines[24], 'catalog input order changed rendering');
assert.equal(reports[23].length, 15);
console.log(JSON.stringify({ parity: 'pass', targets: ['js', 'wasm-gc'], reports: reports.length, bytes: js.length, sha256: createHash('sha256').update(js).digest('hex') }, null, 2));
