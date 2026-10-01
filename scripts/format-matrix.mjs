// Format-consistency gate for M14: every report format reaches the same
// conclusion (same exit code) for the same input, and Markdown/SARIF carry the
// same diagnostic codes as the JSON report. Runs against the built bridge.
import assert from 'node:assert/strict';
import { run_request } from '../dist/bridge.js';

const run = (request) => JSON.parse(run_request(JSON.stringify(request)));

const FINDINGS = JSON.stringify([
  { path: 'CON.txt', kind: 'file' },
  { path: '结果.txt ', kind: 'file' },
  { path: 'b.txt', kind: 'file' },
  { path: 'b.txt', kind: 'directory' },
]);
const CLEAN = JSON.stringify([{ path: 'ok.txt', kind: 'file' }]);

function codeSet(jsonOutput) {
  return JSON.parse(jsonOutput).diagnostics.map(d => d.code).sort();
}
function sarifCodes(sarifOutput) {
  return JSON.parse(sarifOutput).runs[0].results.map(r => r.ruleId).sort();
}

// check — findings, conclusion must be identical in every format
{
  const formats = [
    { format: 'text' },
    { format: 'json' },
    { format: 'markdown' },
    { format: 'json', report: 'sarif' },
  ];
  const outputBy = new Map();
  for (const spec of formats) {
    const request = { mode: 'check', manifest_text: FINDINGS, exclude_patterns: [] };
    if (spec.format) request.format = spec.format;
    if (spec.report) request.report = spec.report;
    const result = run(request);
    assert.equal(result.exit_code, 1, `findings exit for ${spec.format} ${spec.report ?? ''}: ${result.output.slice(0, 120)}`);
    outputBy.set(`${spec.format}:${spec.report ?? ''}`, result.output);
  }
  const jsonCodes = codeSet(outputBy.get('json:'));
  assert.ok(jsonCodes.includes('NAME_RESERVED'));
  assert.ok(jsonCodes.includes('NAME_TRAILING_DOT_SPACE'));
  assert.ok(jsonCodes.includes('PATH_KIND_CONFLICT'));
  const md = outputBy.get('markdown:');
  for (const code of jsonCodes) {
    assert.ok(md.includes(`\`${code}\``), `markdown carries ${code}`);
  }
  assert.deepEqual(sarifCodes(outputBy.get('json:sarif')), jsonCodes, 'SARIF rule ids equal JSON diagnostic codes');
}

// check — clean report exits 0 in every format
for (const format of ['text', 'json', 'markdown']) {
  const result = run({ mode: 'check', format, manifest_text: CLEAN, exclude_patterns: [] });
  assert.equal(result.exit_code, 0, `clean exit for ${format}`);
}
{
  const result = run({ mode: 'check', format: 'json', report: 'sarif', manifest_text: CLEAN, exclude_patterns: [] });
  assert.equal(result.exit_code, 0, 'clean exit for sarif');
}

// scan — incomplete is exit 3 in every format and no format hides the issues
{
  const scanIssues = [{ code: 'SCAN_IO_ERROR', path: 'closed', message: 'Cannot enumerate directory.' }];
  for (const format of ['text', 'json', 'markdown']) {
    const result = run({ mode: 'scan', format, entries: [{ path: 'CON.txt', kind: 'file' }], scan_issues: scanIssues, exclude_patterns: [] });
    assert.equal(result.exit_code, 3, `incomplete scan exit for ${format}`);
  }
  const sarif = run({ mode: 'scan', format: 'json', report: 'sarif', entries: [{ path: 'CON.txt', kind: 'file' }], scan_issues: scanIssues, exclude_patterns: [] });
  assert.equal(sarif.exit_code, 3, 'incomplete scan exit for sarif');
  assert.equal(JSON.parse(sarif.output).runs[0].invocations[0].executionSuccessful, false);
}

console.log(JSON.stringify({ format_matrix: 'pass', targets: ['js'] }));
