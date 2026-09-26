import assert from 'node:assert/strict';
import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { delimiter, dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const root = fileURLToPath(new URL('../', import.meta.url));
const platform = process.platform === 'win32' && process.arch === 'x64' ? 'windows-x86_64'
  : process.platform === 'linux' && process.arch === 'x64' ? 'linux-x86_64' : null;
assert.ok(platform, 'The pinned toolchain supports Windows x64 and Linux x64.');
const toolchain = resolve(root, process.env.MOONPORT_TOOLCHAIN_HOME ?? join(root, '.toolchains', platform));
const moon = join(toolchain, 'bin', process.platform === 'win32' ? 'moon.exe' : 'moon');
const env = { ...process.env, MOON_HOME: toolchain, PATH: `${join(toolchain, 'bin')}${delimiter}${process.env.PATH}` };
const packageFiles = ['bin/moonportcheck.mjs', 'lib/host.mjs', 'dist/bridge.js', 'package.json'];
for (const relative of packageFiles) assert.ok(statSync(join(root, relative)).isFile(), `${relative}: build the CLI first`);

function invoke(program, args, { cwd = root, environment = env, expected = 0 } = {}) {
  const result = spawnSync(program, args, { cwd, env: environment, encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 });
  if (result.error) throw result.error;
  assert.equal(result.signal, null, `${program}: unexpected signal`);
  assert.equal(result.status, expected, `${program} ${args.join(' ')}\n${result.stdout}\n${result.stderr}`);
  return result;
}

invoke(process.execPath, [join(root, 'scripts/toolchain.mjs'), 'verify']);
const artifacts = join(root, 'artifacts');
mkdirSync(artifacts, { recursive: true });
const work = mkdtempSync(join(artifacts, 'consumer-smoke-'));
const consumer = join(work, 'consumer');
const packaged = join(work, 'cli-package');
mkdirSync(consumer);
mkdirSync(packaged);
const moduleName = 'AlexenderSokolov/moonportcheck';
const moduleVersion = JSON.parse(readFileSync(join(root, 'package.json'), 'utf8')).version;

// Current MoonBit resolves local modules through moon.work, not the deprecated
// path-dependency field. This consumer has its own module/package/workspace and
// imports only the public library; no source files are copied into it.
writeFileSync(join(consumer, 'moon.mod'), `name = "moonportcheck-smoke/consumer"\nversion = "0.1.0"\nimport {\n  "${moduleName}@${moduleVersion}",\n}\n`);
writeFileSync(join(consumer, 'moon.work'), `members = [ ".", ${JSON.stringify(root.replaceAll('\\', '/'))} ]\n`);
writeFileSync(join(consumer, 'moon.pkg'), `import {\n  "${moduleName}",\n}\noptions(\n  is_main: true,\n)\n`);
const entries = [{ path: '中文/ok.txt', kind: 'file' }, { path: 'CON.txt', kind: 'file' }];
const manifest = JSON.stringify(entries);
writeFileSync(join(consumer, 'main.mbt'), `///|\nfn main {\n  let parsed = match @moonportcheck.parse_manifest(${JSON.stringify(manifest)}) {\n    Ok(entries) => entries\n    Err(_) => abort("Valid manifest rejected")\n  }\n  let explicit : Array[@moonportcheck.PathEntry] = [\n    { path: "中文/ok.txt", kind: @moonportcheck.File },\n    { path: "CON.txt", kind: @moonportcheck.File },\n  ]\n  let report = @moonportcheck.audit(parsed)\n  let direct = @moonportcheck.audit(explicit)\n  if @moonportcheck.render_json(report) != @moonportcheck.render_json(direct) {\n    abort("Parsed and constructed inputs disagree")\n  }\n  if @moonportcheck.render_text(report).length() == 0 {\n    abort("Text rendering is empty")\n  }\n  println(@moonportcheck.render_json(report))\n}\n`);
const commands = [
  ['check', '--target', 'js', '--deny-warn'],
  ['build', '--target', 'js', '--deny-warn'],
  ['run', '.', '--target', 'js', '--deny-warn'],
];
const consumerRuns = commands.map((args) => {
  const result = invoke(moon, args, { cwd: consumer });
  writeFileSync(join(work, `consumer-${args[0]}.stdout.log`), result.stdout);
  writeFileSync(join(work, `consumer-${args[0]}.stderr.log`), result.stderr);
  return { command: args.join(' '), exit_code: result.status, stdout: result.stdout };
});
const consumedReport = JSON.parse(consumerRuns.at(-1).stdout);
assert.equal(consumedReport.complete, true);
assert.equal(consumedReport.summary.entries, 2);
assert.deepEqual(consumedReport.diagnostics.map((item) => item.code), ['NAME_RESERVED']);

for (const relative of packageFiles) {
  const destination = join(packaged, relative);
  mkdirSync(dirname(destination), { recursive: true });
  copyFileSync(join(root, relative), destination);
}
// The copied package receives no compiler or source directory. Its process PATH
// contains only Node's directory; MOON_HOME is absent.
const runtimeEnv = Object.fromEntries(Object.entries(process.env).filter(([key]) => key.toLowerCase() !== 'path' && key !== 'MOON_HOME'));
runtimeEnv.PATH = dirname(process.execPath);
const validManifest = join(work, 'portable.json');
const invalidManifest = join(work, 'findings.json');
writeFileSync(validManifest, JSON.stringify([{ path: '中文/file name.txt', kind: 'file' }]));
writeFileSync(invalidManifest, manifest);
const cli = join(packaged, 'bin', 'moonportcheck.mjs');
const valid = invoke(process.execPath, [cli, 'check', validManifest, '--format', 'json'], { cwd: packaged, environment: runtimeEnv });
const invalid = invoke(process.execPath, [cli, 'check', invalidManifest, '--format', 'json'], { cwd: packaged, environment: runtimeEnv, expected: 1 });
assert.deepEqual(JSON.parse(valid.stdout).diagnostics, []);
assert.equal(JSON.parse(valid.stdout).summary.entries, 1);
assert.equal(consumedReport.schema_version, 1, 'the original library API must remain schema 1');
const cliReport = JSON.parse(invalid.stdout);
assert.equal(cliReport.schema_version, 2, 'the v0.2 CLI uses the documented new schema');
assert.deepEqual(cliReport.diagnostics.map(({ code, severity, paths, occurrences, message }) => ({ code, severity, paths, occurrences, message })), consumedReport.diagnostics);
const version = invoke(process.execPath, [cli, '--version'], { cwd: packaged, environment: runtimeEnv });
assert.equal(version.stdout.trim(), moduleVersion);
const evidence = {
  schema_version: 1,
  node: process.version,
  artifacts: work,
  local_dependency: { module: moduleName, source: root, mechanism: 'moon.mod import plus independent moon.work local member' },
  consumer: { commands: consumerRuns.map(({ command, exit_code }) => ({ command, exit_code })), entries: consumedReport.summary.entries, diagnostic_codes: consumedReport.diagnostics.map((item) => item.code) },
  copied_cli: { files: packageFiles, compiler_on_path: false, source_in_package: false, portable_exit: valid.status, findings_exit: invalid.status, version: version.stdout.trim() },
};
writeFileSync(join(work, 'evidence.json'), `${JSON.stringify(evidence, null, 2)}\n`);
process.stdout.write(`${JSON.stringify(evidence, null, 2)}\n`);
