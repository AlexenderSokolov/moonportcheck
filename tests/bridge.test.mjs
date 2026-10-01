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

test('snapshot mode builds a canonical snapshot and exits by completeness', () => {
  const complete = run({ mode: 'snapshot', format: 'json', entries: [{ path: 'b', kind: 'file' }, { path: 'a', kind: 'directory' }, { path: 'a/x', kind: 'file' }], scan_issues: [], exclude_patterns: ['*.tmp', 'cache/'] });
  assert.equal(complete.exit_code, 0);
  const doc = JSON.parse(complete.output);
  assert.equal(doc.format, 'moonportcheck-snapshot');
  assert.equal(doc.version, 1);
  assert.equal(doc.complete, true);
  assert.deepEqual(doc.scope, ['*.tmp', 'cache/']);
  assert.deepEqual(doc.entries.map(e => [e.path, e.kind]), [['a', 'directory'], ['a/x', 'file'], ['b', 'file']]);
  assert.deepEqual(doc.scan_issues, []);
  const partial = run({ mode: 'snapshot', format: 'json', entries: [{ path: 'x', kind: 'file' }], scan_issues: [{ code: 'SCAN_IO_ERROR', path: 'closed', message: 'Cannot enumerate directory (EACCES).' }], exclude_patterns: [] });
  assert.equal(partial.exit_code, 3);
  assert.equal(JSON.parse(partial.output).complete, false);
  const badEntry = run({ mode: 'snapshot', format: 'json', entries: [{ path: 'x', kind: 'symlink' }], scan_issues: [] });
  assert.equal(badEntry.exit_code, 2);
  const badIssue = run({ mode: 'snapshot', format: 'json', entries: [], scan_issues: [null] });
  assert.equal(badIssue.exit_code, 2);
});

test('check imports a snapshot with inherited scope and shrink-only extras', () => {
  const exported = run({ mode: 'snapshot', format: 'json', entries: [{ path: 'cache/x.bin', kind: 'file' }, { path: 'ok.txt', kind: 'file' }], scan_issues: [], exclude_patterns: ['cache/'] });
  assert.equal(exported.exit_code, 0);
  const inherited = run({ mode: 'check', format: 'json', manifest_text: exported.output });
  assert.equal(inherited.exit_code, 0, inherited.output);
  const report = JSON.parse(inherited.output);
  assert.equal(report.source, 'snapshot');
  assert.deepEqual(report.scope, ['cache/']);
  assert.equal(report.summary.entries, 1);
  assert.equal(report.excluded_entries, 1);
  const narrowed = run({ mode: 'check', format: 'json', manifest_text: exported.output, exclude_patterns: ['ok.txt'] });
  assert.equal(narrowed.exit_code, 0, narrowed.output);
  const narrowedReport = JSON.parse(narrowed.output);
  assert.deepEqual(narrowedReport.scope, ['cache/', 'ok.txt']);
  assert.equal(narrowedReport.summary.entries, 0);
});

test('check of a snapshot reports findings and rejects bad profile or malformed docs', () => {
  const text = run({ mode: 'snapshot', format: 'json', entries: [{ path: 'CON.txt', kind: 'file' }, { path: 'ok.bin', kind: 'file' }], scan_issues: [], exclude_patterns: [] }).output;
  const result = run({ mode: 'check', format: 'json', manifest_text: text });
  assert.equal(result.exit_code, 1, result.output);
  const report = JSON.parse(result.output);
  assert.equal(report.source, 'snapshot');
  assert.equal(report.summary.entries, 2);
  assert.ok(report.diagnostics.some(d => d.code === 'NAME_RESERVED'));
  const badProfile = run({ mode: 'check', format: 'json', manifest_text: '{"format":"moonportcheck-snapshot","version":1,"profile":"other","complete":true,"scope":[],"entries":[{"path":"x","kind":"file"}],"scan_issues":[]}' });
  assert.equal(badProfile.exit_code, 2);
  assert.match(badProfile.output, /INPUT_SCHEMA/);
  const malformed = run({ mode: 'check', format: 'json', manifest_text: '{"format":"moonportcheck-snapshot","version":1,"profile":"portable-windows-v1","complete":true,"scope":[],"entries":[{"path":"b","kind":"file"},{"path":"a","kind":"file"}],"scan_issues":[]}' });
  assert.equal(malformed.exit_code, 2);
  const plain = run({ mode: 'check', format: 'json', manifest_text: '[{"path":"x","kind":"file"}]' });
  assert.equal(plain.exit_code, 0);
  assert.equal(JSON.parse(plain.output).source, 'manifest');
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

const snapshotText = (entries, issues, exclude) => run({ mode: 'snapshot', format: 'json', entries, scan_issues: issues, exclude_patterns: exclude }).output;

test('diff mode compares snapshots with the documented exit codes', () => {
  const before = snapshotText([{ path: 'a.txt', kind: 'file' }, { path: 'dir', kind: 'directory' }], [], []);
  const after = snapshotText([{ path: 'dir', kind: 'directory' }], [], []);
  const changed = run({ mode: 'diff', format: 'json', before_text: before, after_text: after });
  assert.equal(changed.exit_code, 1, changed.output);
  const doc = JSON.parse(changed.output);
  assert.equal(doc.format, 'moonportcheck-diff');
  assert.equal(doc.version, 1);
  assert.equal(doc.complete, true);
  assert.deepEqual(doc.changes.map(c => [c.kind, c.path]), [['removed', 'a.txt']]);
  const same = run({ mode: 'diff', format: 'json', before_text: before, after_text: before });
  assert.equal(same.exit_code, 0, same.output);
  assert.deepEqual(JSON.parse(same.output).changes, []);
  const text = run({ mode: 'diff', format: 'text', before_text: before, after_text: after });
  assert.equal(text.exit_code, 1, text.output);
  assert.match(text.output, /- a\.txt \(removed, file\)/);
});

test('diff mode exits 3 on incomplete input and 2 on mismatch or bad input', () => {
  const partial = snapshotText([{ path: 'x.txt', kind: 'file' }], [{ code: 'SCAN_LINK_SKIPPED', path: 'x.txt', message: 'Not followed.' }], []);
  const full = snapshotText([{ path: 'x.txt', kind: 'file' }], [], []);
  const incomplete = run({ mode: 'diff', format: 'json', before_text: partial, after_text: full });
  assert.equal(incomplete.exit_code, 3, incomplete.output);
  assert.equal(JSON.parse(incomplete.output).complete, false);
  const textPartial = run({ mode: 'diff', format: 'text', before_text: partial, after_text: full });
  assert.equal(textPartial.exit_code, 3);
  assert.match(textPartial.output, /INCOMPLETE/);
  const scopedA = snapshotText([{ path: 'x.txt', kind: 'file' }], [], ['*.tmp']);
  const scopedB = snapshotText([{ path: 'x.txt', kind: 'file' }], [], []);
  const mismatch = run({ mode: 'diff', format: 'json', before_text: scopedA, after_text: scopedB });
  assert.equal(mismatch.exit_code, 2);
  assert.match(mismatch.output, /INPUT_SCHEMA/);
  const badJson = run({ mode: 'diff', format: 'json', before_text: '{', after_text: full });
  assert.equal(badJson.exit_code, 2);
  const arrayDoc = run({ mode: 'diff', format: 'json', before_text: '[{"path":"x","kind":"file"}]', after_text: full });
  assert.equal(arrayDoc.exit_code, 2);
});

const scanJson = (extra) => run({ mode: 'scan', format: 'json', ...extra }).output;

test('baseline mode builds from a complete report and rejects incomplete ones', () => {
  const report = scanJson({ entries: [{ path: 'CON.txt', kind: 'file' }], scan_issues: [], exclude_patterns: [] });
  const created = run({ mode: 'baseline', format: 'json', report_text: report });
  assert.equal(created.exit_code, 0, created.output);
  const doc = JSON.parse(created.output);
  assert.equal(doc.format, 'moonportcheck-baseline');
  assert.deepEqual(doc.groups.map(g => [g.code, g.anchor]), [['NAME_RESERVED', 'CON.txt']]);
  const incompleteReport = scanJson({ entries: [{ path: 'CON.txt', kind: 'file' }], scan_issues: [{ code: 'SCAN_IO_ERROR', path: 'x', message: 'bad' }], exclude_patterns: [] });
  const rejected = run({ mode: 'baseline', format: 'json', report_text: incompleteReport });
  assert.equal(rejected.exit_code, 2, rejected.output);
  assert.match(rejected.output, /INPUT_INCOMPLETE/);
  const bad = run({ mode: 'baseline', format: 'json', report_text: '{' });
  assert.equal(bad.exit_code, 2);
});

const baselineFrom = (entries, exclude) => run({ mode: 'baseline', format: 'json', report_text: scanJson({ entries, scan_issues: [], exclude_patterns: exclude }) }).output;

test('scan --baseline gates exits for new, worsened and mismatched baselines', () => {
  const baselineText = baselineFrom([{ path: 'CON.txt', kind: 'file' }], []);
  const same = run({ mode: 'scan', format: 'json', baseline_text: baselineText, fail_on: true, entries: [{ path: 'CON.txt', kind: 'file' }], scan_issues: [], exclude_patterns: [] });
  assert.equal(same.exit_code, 0, same.output);
  const fresh = run({ mode: 'scan', format: 'json', baseline_text: baselineText, fail_on: true, entries: [{ path: 'CON.txt', kind: 'file' }, { path: 'sub/CON.txt', kind: 'file' }], scan_issues: [], exclude_patterns: [] });
  assert.equal(fresh.exit_code, 1, fresh.output);
  const allFindings = run({ mode: 'scan', format: 'json', baseline_text: baselineText, entries: [{ path: 'CON.txt', kind: 'file' }], scan_issues: [], exclude_patterns: [] });
  assert.equal(allFindings.exit_code, 1, allFindings.output);
  const broken = run({ mode: 'scan', format: 'json', baseline_text: baselineText, fail_on: true, entries: [], scan_issues: [{ code: 'SCAN_IO_ERROR', path: 'x', message: 'bad' }], exclude_patterns: [] });
  assert.equal(broken.exit_code, 3, broken.output);
  const badBaseline = run({ mode: 'scan', format: 'json', baseline_text: '{', fail_on: true, entries: [], scan_issues: [], exclude_patterns: [] });
  assert.equal(badBaseline.exit_code, 2);
  assert.match(badBaseline.output, /INPUT_JSON/);
  const scopedBaseline = baselineFrom([], ['*.tmp']);
  const scopeMismatch = run({ mode: 'scan', format: 'json', baseline_text: scopedBaseline, entries: [], scan_issues: [], exclude_patterns: [] });
  assert.equal(scopeMismatch.exit_code, 2, scopeMismatch.output);
  assert.match(scopeMismatch.output, /scope/);
});

test('diff --format markdown renders a table and check --report sarif emits 2.1.0', () => {
  const snap = (entries) => run({ mode: 'snapshot', format: 'json', entries, scan_issues: [], exclude_patterns: [] }).output;
  const before = snap([{ path: 'a.txt', kind: 'file' }]);
  const after = snap([{ path: 'b.txt', kind: 'file' }]);
  const md = run({ mode: 'diff', format: 'markdown', before_text: before, after_text: after });
  assert.equal(md.exit_code, 1, md.output);
  assert.match(md.output, /^# MoonPortCheck diff/);
  assert.match(md.output, /\| added \| `b\.txt` \| added as `file` \|/);
  assert.match(md.output, /\| removed \| `a\.txt` \| removed as `file` \|/);
  const rs = run({ mode: 'check', format: 'json', report: 'sarif', manifest_text: JSON.stringify([{ path: 'CON.txt', kind: 'file' }]), exclude_patterns: [] });
  assert.equal(rs.exit_code, 1, rs.output);
  const doc = JSON.parse(rs.output);
  assert.equal(doc.version, '2.1.0');
  assert.equal(doc.runs[0].tool.driver.name, 'MoonPortCheck');
  assert.equal(doc.runs[0].invocations[0].executionSuccessful, true);
  const hit = doc.runs[0].results.find(r => r.ruleId === 'NAME_RESERVED');
  assert.ok(hit);
  assert.equal(hit.locations[0].physicalLocation.artifactLocation.uri, 'CON.txt');
  assert.equal(JSON.stringify(doc).includes('startLine'), false);
});

test('check and scan --format markdown report the same conclusion as json', () => {
  const manifestText = JSON.stringify([{ path: 'CON.txt', kind: 'file' }, { path: 'b.txt', kind: 'file' }, { path: 'b.txt', kind: 'directory' }]);
  const json = run({ mode: 'check', format: 'json', manifest_text: manifestText, exclude_patterns: [] });
  const md = run({ mode: 'check', format: 'markdown', manifest_text: manifestText, exclude_patterns: [] });
  assert.equal(md.exit_code, json.exit_code);
  assert.equal(md.exit_code, 1);
  assert.match(md.output, /^# MoonPortCheck report/);
  assert.match(md.output, /\| `NAME_RESERVED` \| `CON\.txt` \|/);
  assert.match(md.output, /\| `PATH_KIND_CONFLICT` \|/);
  for (const code of JSON.parse(json.output).diagnostics.map(d => d.code)) {
    assert.ok(md.output.includes(`\`${code}\``), `markdown carries ${code}`);
  }
  const empty = run({ mode: 'check', format: 'markdown', manifest_text: '[]', exclude_patterns: [] });
  assert.equal(empty.exit_code, 0, empty.output);
  const scanMd = run({ mode: 'scan', format: 'markdown', entries: [{ path: 'CON.txt', kind: 'file' }], scan_issues: [], exclude_patterns: [] });
  assert.equal(scanMd.exit_code, 1);
  assert.match(scanMd.output, /^# MoonPortCheck report/);
});
