import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { collectEvidenceMetadata, stepsPassed } from './evidence.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const stamp = new Date().toISOString().replace(/[:.]/g, '-');
const output = path.join(root, 'artifacts', `acceptance-${process.platform}-${stamp}`);
await fs.mkdir(output, { recursive: true });
const steps = [];
function execute(label, command, args) {
  const start = performance.now();
  const result = spawnSync(command, args, { cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024, env: process.env });
  const log = `${result.stdout || ''}${result.stderr || ''}${result.error ? '\n' + result.error.message : ''}`;
  return { label, command: [command, ...args], elapsed_ms: Math.round(performance.now() - start), exit_code: result.status, signal: result.signal, log };
}
const commands = [
  ['checks', process.platform === 'win32' ? 'pwsh' : 'bash', process.platform === 'win32' ? ['-NoProfile', '-File', 'run_check.ps1'] : ['run_check.sh']],
  ['demo', process.execPath, ['scripts/demo.mjs']],
  ['benchmark', process.execPath, ['scripts/bench.mjs']],
  ['consumer', process.execPath, ['scripts/consumer-smoke.mjs']],
  ['package', process.execPath, ['scripts/package.mjs']],
  ['unpack', process.execPath, ['scripts/unpack.mjs']],
];
for (const [label, command, args] of commands) {
  console.log(`Acceptance: ${label}`);
  const result = execute(label, command, args);
  await fs.writeFile(path.join(output, `${label}.log`), result.log, 'utf8');
  const { log, ...record } = result;
  steps.push(record);
  if (result.exit_code !== 0 || result.signal) {
    process.stderr.write(log);
    break;
  }
}
const excluded = new Set(['.git', '.toolchains', '_build', 'target', 'artifacts', 'dist', 'node_modules']);
const sources = [];
async function inventory(directory, relative = '') {
  for (const entry of (await fs.readdir(directory, { withFileTypes: true })).sort((a,b) => a.name < b.name ? -1 : 1)) {
    if (excluded.has(entry.name)) continue;
    const next = relative ? `${relative}/${entry.name}` : entry.name;
    if (entry.isDirectory()) await inventory(path.join(directory, entry.name), next);
    else if (entry.isFile()) {
      const bytes = await fs.readFile(path.join(directory, entry.name));
      sources.push({ path: next, bytes: bytes.length, sha256: createHash('sha256').update(bytes).digest('hex') });
    }
  }
}
await inventory(root);
const sourceText = JSON.stringify(sources, null, 2) + '\n';
await fs.writeFile(path.join(output, 'source-manifest.json'), sourceText);
const toolchain = execute('toolchain', 'moon', ['version', '--all']);
await fs.writeFile(path.join(output, 'toolchain.log'), toolchain.log);
const { log: toolchainLog, ...toolchainRecord } = toolchain;
steps.push(toolchainRecord);
if (toolchain.exit_code !== 0 || toolchain.signal) process.stderr.write(toolchainLog);
const metadata = await collectEvidenceMetadata(root);
const passed = stepsPassed(steps, [...commands.map(([label]) => label), 'toolchain']);
const evidence = {
  schema_version: 2, ...metadata, passed,
  generated_at: new Date().toISOString(),
  source_manifest_sha256: createHash('sha256').update(sourceText).digest('hex'),
  source_files: sources.length, toolchain_lock: JSON.parse(await fs.readFile(path.join(root, 'scripts/toolchain.lock.json'), 'utf8')),
  steps,
};
await fs.writeFile(path.join(output, 'evidence.json'), JSON.stringify(evidence, null, 2) + '\n');
console.log(JSON.stringify({ passed, evidence: path.join(output, 'evidence.json') }, null, 2));
process.exitCode = passed ? 0 : 1;
