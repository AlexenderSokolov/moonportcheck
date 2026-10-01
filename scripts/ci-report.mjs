// M14 "Actions 摘要示例": render one real scan/check/diff in every supported
// format, keep every report under artifacts/reports, and append a Markdown
// summary to the runner's step summary when GITHUB_STEP_SUMMARY is set.
// This is a report-obtainability sample, not a claim that Code Scanning
// accepted the SARIF file.
import { spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const bin = path.join(root, 'bin', 'moonportcheck.mjs');

function runCli(args) {
  const child = spawnSync(process.execPath, [bin, ...args], { encoding: 'utf8', cwd: root });
  if (child.error) throw child.error;
  if (process.env.MPC_REPORT_VERBOSE !== undefined && child.status !== 0 && child.stderr) {
    process.stderr.write(child.stderr);
  }
  return child;
}

// A small cross-platform fixture: the extension form of a reserved device name
// is creatable on Windows and Linux, so the demo needs no OS-specific casing.
const fixture = mkdtempSync(path.join(tmpdir(), 'moonport-report-'));
writeFileSync(path.join(fixture, 'CON.txt'), 'x');
mkdirSync(path.join(fixture, '目录'));
writeFileSync(path.join(fixture, '目录', '结果.csv'), 'rows');

const outDir = path.join(root, 'artifacts', 'reports');
mkdirSync(outDir, { recursive: true });

const scanJson = runCli(['scan', fixture, '--format', 'json']);
const scanText = runCli(['scan', fixture, '--format', 'text']);
const scanMd = runCli(['scan', fixture, '--format', 'markdown']);
if (![scanJson.status, scanText.status, scanMd.status].every(code => code === 1)) {
  throw new Error(`scan exit codes differ: json=${scanJson.status} text=${scanText.status} md=${scanMd.status}`);
}
writeFileSync(path.join(outDir, 'scan.json'), scanJson.stdout);
writeFileSync(path.join(outDir, 'scan.txt'), scanText.stdout);
writeFileSync(path.join(outDir, 'scan.md'), scanMd.stdout);

const manifestFile = path.join(outDir, 'manifest.json');
writeFileSync(manifestFile, JSON.stringify([{ path: 'CON.txt', kind: 'file' }]));
const sarif = runCli(['check', manifestFile, '--report', 'sarif']);
if (sarif.status !== 1) throw new Error(`sarif exit ${sarif.status}`);
writeFileSync(path.join(outDir, 'check.sarif'), sarif.stdout);

const snapshotFile = path.join(outDir, 'snapshot.json');
writeFileSync(snapshotFile, runCli(['snapshot', fixture]).stdout);
const diffMd = runCli(['diff', snapshotFile, snapshotFile, '--format', 'markdown']);
if (diffMd.status !== 0) throw new Error(`diff markdown exit ${diffMd.status}`);
writeFileSync(path.join(outDir, 'diff.md'), diffMd.stdout);

const sarifPretty = JSON.stringify(JSON.parse(sarif.stdout), null, 2);
const summary = [
  '# MoonPortCheck reports',
  '',
  `Fixture: \`${fixture}\``,
  '',
  'Every format reports the same conclusion: scan finds `NAME_RESERVED` and',
  'exits `1` in text, JSON and Markdown; the SARIF check exits `1` too.',
  '',
  '## scan.json',
  '```json',
  scanJson.stdout.slice(0, 700),
  '```',
  '',
  '## scan.md',
  '',
  scanMd.stdout.slice(0, 1400),
  '',
  '## check.sarif (pretty-printed SARIF 2.1.0)',
  '```json',
  sarifPretty.slice(0, 1400),
  '```',
  '',
].join('\n');
writeFileSync(path.join(outDir, 'summary.md'), summary);
if (process.env.GITHUB_STEP_SUMMARY !== undefined) {
  writeFileSync(process.env.GITHUB_STEP_SUMMARY, summary + '\n', { flag: 'a' });
}

console.log(JSON.stringify({ reports: 'ok', dir: outDir }, null, 2));
