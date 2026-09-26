import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const cli = fileURLToPath(new URL('../bin/moonportcheck.mjs', import.meta.url));
const examples = [
  {
    name: 'Portable names: Chinese, spaces, and hidden directories',
    file: 'portable.json',
    exit: 0,
    entries: 5,
    codes: [],
  },
  {
    name: 'Windows delivery problems',
    file: 'windows-problems.json',
    exit: 1,
    entries: 4,
    codes: ['NAME_RESERVED', 'NAME_TRAILING_DOT_SPACE', 'PATH_CASE_COLLISION'],
  },
  {
    name: 'Duplicates, implicit directories, and file/directory conflicts',
    file: 'hierarchy-conflicts.json',
    exit: 1,
    entries: 7,
    codes: ['PATH_CASE_COLLISION', 'PATH_DUPLICATE', 'PATH_KIND_CONFLICT'],
  },
];

for (const example of examples) {
  const result = spawnSync(process.execPath, [
    cli, 'check', `examples/${example.file}`, '--format', 'json',
  ], { cwd: root, encoding: 'utf8' });
  if (result.error) throw result.error;
  assert.equal(result.signal, null, `${example.file}: CLI terminated by a signal`);
  assert.equal(result.status, example.exit,
    `${example.file}: unexpected exit code\n${result.stderr}\n${result.stdout}`);
  const report = JSON.parse(result.stdout);
  assert.equal(report.schema_version, 1);
  assert.equal(report.profile, 'portable-windows-v1');
  assert.equal(report.source, 'manifest');
  assert.equal(report.complete, true);
  assert.equal(report.summary.entries, example.entries);
  assert.equal(report.summary.scan_issues, 0);
  assert.deepEqual([...new Set(report.diagnostics.map(item => item.code))].sort(),
    [...example.codes].sort(), `${example.file}: unexpected diagnostic codes`);
  if (example.file === 'hierarchy-conflicts.json') {
    const duplicate = report.diagnostics.find(item => item.code === 'PATH_DUPLICATE');
    assert.equal(duplicate.occurrences, 3, 'Duplicate multiplicity must be preserved');
    assert.deepEqual(duplicate.paths, ['duplicate.txt']);
  }
  console.log(`\n${example.name} (${example.file})`);
  console.log(`  exit=${result.status}; entries=${report.summary.entries}; complete=${report.complete}`);
  for (const diagnostic of report.diagnostics) {
    console.log(`  ${diagnostic.code}: ${diagnostic.paths.map(path => JSON.stringify(path)).join(', ')} (occurrences=${diagnostic.occurrences})`);
  }
  if (report.diagnostics.length === 0) console.log('  No findings in the covered profile.');
}
console.log('\nPASS: all 3 demonstrations matched the actual CLI exit codes and diagnostics.');
