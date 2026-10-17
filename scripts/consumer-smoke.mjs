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
const registryConsumer = process.env.MOONPORT_CONSUMER_REGISTRY === '1';

// Current MoonBit resolves local modules through moon.work, not the deprecated
// path-dependency field. This consumer has its own module/package/workspace and
// imports only the public library; no source files are copied into it.
writeFileSync(join(consumer, 'moon.mod'), `name = "moonportcheck-smoke/consumer"\nversion = "0.1.0"\nimport {\n  "${moduleName}@${moduleVersion}",\n}\n`);
writeFileSync(join(consumer, 'moon.work'), registryConsumer ? 'members = [ "." ]\n'
  : `members = [ ".", ${JSON.stringify(root.replaceAll('\\', '/'))} ]\n`);
writeFileSync(join(consumer, 'moon.pkg'), `import {\n  "${moduleName}",\n}\noptions(\n  is_main: true,\n)\n`);
const entries = [{ path: '中文/ok.txt', kind: 'file' }, { path: 'CON.txt', kind: 'file' }];
const manifest = JSON.stringify(entries);
writeFileSync(join(consumer, 'main.mbt'), `///|\nfn main {\n  let parsed = match @moonportcheck.parse_manifest(${JSON.stringify(manifest)}) {\n    Ok(entries) => entries\n    Err(_) => abort("Valid manifest rejected")\n  }\n  let explicit : Array[@moonportcheck.PathEntry] = [\n    { path: "中文/ok.txt", kind: @moonportcheck.File },\n    { path: "CON.txt", kind: @moonportcheck.File },\n  ]\n  let report = @moonportcheck.audit(parsed)\n  let direct = @moonportcheck.audit(explicit)\n  if @moonportcheck.render_json(report) != @moonportcheck.render_json(direct) {\n    abort("Parsed and constructed inputs disagree")\n  }\n  if @moonportcheck.render_text(report).length() == 0 {\n    abort("Text rendering is empty")\n  }\n  println(@moonportcheck.render_json(report))\n}\n`);
const commands = [
  ['check', '--target', 'js', '--deny-warn'],
  ['build', '--target', 'js', '--deny-warn'],
  ['run', '.', '--target', 'js', '--deny-warn'],
  ['check', '--target', 'wasm-gc', '--deny-warn'],
  ['build', '--target', 'wasm-gc', '--deny-warn'],
  ['run', '.', '--target', 'wasm-gc', '--deny-warn'],
];
if (registryConsumer) invoke(moon, ['update'], { cwd: consumer });
const specText = readFileSync(join(root, 'examples/delivery/swap/spec.json'), 'utf8');
const deliveryConsumer = `
  let spec = match @moonportcheck.parse_delivery_spec(${JSON.stringify(specText)}) {
    Ok(spec) => spec
    Err(_) => abort("Public spec parser rejected swap")
  }
  let plan = match @moonportcheck.plan_delivery(spec) {
    Ok(plan) => plan
    Err(_) => abort("Public planning failed")
  }
  if plan.status != "ready" { abort("Swap is not ready") }
  let encoded = @moonportcheck.render_delivery_plan_json(plan)
  let decoded = match @moonportcheck.parse_delivery_plan(encoded) {
    Ok(plan) => plan
    Err(_) => abort("Public plan round trip failed")
  }
  if @moonportcheck.render_delivery_plan_json(decoded) != encoded {
    abort("Plan round trip differs")
  }
  let audit = @moonportcheck.audit_delivery_plan(spec, decoded)
  if !audit.valid { abort("Public auditor rejected swap") }
  let expected = [("a", "b"), ("b", "a"), (".moonportcheck-stage-0", ".moonportcheck-stage-0")]
  if audit.final_entries.length() != expected.length() { abort("Final entry count differs") }
  for item in expected {
    if !audit.final_entries.any(entry => entry.path == item.0 && entry.origin.root == "target" && entry.origin.path == item.1) {
      abort("Public identity result differs")
    }
  }
  let wrong_operations : Array[@moonportcheck.DeliveryOperation] = decoded.operations.map(op => {
    kind: op.kind, source: op.source, from: op.from, to: op.to,
    origin: { root: "target", path: "wrong-initial-origin" },
  })
  let wrong : @moonportcheck.DeliveryPlan = {
    status: decoded.status, basis: decoded.basis, operations: wrong_operations,
    temporary_paths: decoded.temporary_paths, diagnostics: [],
  }
  let rejected = @moonportcheck.audit_delivery_plan(spec, wrong)
  if rejected.valid || rejected.first_failed_step != 0 {
    abort("Public auditor accepted an external plan with wrong identity")
  }
  println(encoded)
  println(@moonportcheck.render_delivery_audit_json(audit))
  println(@moonportcheck.render_delivery_audit_json(rejected))
`;
const mainPath = join(consumer, 'main.mbt');
const legacyMain = readFileSync(mainPath, 'utf8');
assert.ok(legacyMain.endsWith('}\n'));
writeFileSync(mainPath, legacyMain.slice(0, -2) + deliveryConsumer + '}\n');
const consumerRuns = commands.map((args) => {
  const result = invoke(moon, args, { cwd: consumer });
  const target = args[args.indexOf('--target') + 1];
  writeFileSync(join(work, `consumer-${target}-${args[0]}.stdout.log`), result.stdout);
  writeFileSync(join(work, `consumer-${target}-${args[0]}.stderr.log`), result.stderr);
  return { command: args.join(' '), exit_code: result.status, stdout: result.stdout };
});
const jsOutput = consumerRuns[2].stdout;
assert.equal(consumerRuns[5].stdout, jsOutput, 'external consumer JS/wasm-gc output differs');
const [consumedReport, deliveryPlan, deliveryAudit, wrongAudit] = jsOutput.trim().split(/\r?\n/).map(line => JSON.parse(line));
assert.equal(deliveryPlan.status, 'ready');
assert.equal(deliveryAudit.valid, true);
assert.equal(wrongAudit.valid, false);
assert.equal(wrongAudit.first_failed_step, 0);
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
  local_dependency: registryConsumer ? null : { module: moduleName, source: root, mechanism: 'moon.mod import plus independent moon.work local member' },
  registry_dependency: registryConsumer ? { module: moduleName, version: moduleVersion, mechanism: 'versioned moon.mod import with only the independent consumer in moon.work' } : null,
  consumer: { commands: consumerRuns.map(({ command, exit_code }) => ({ command, exit_code })), entries: consumedReport.summary.entries, diagnostic_codes: consumedReport.diagnostics.map((item) => item.code),
    delivery: { plan_roundtrip: true, swap_identity_verified: true, wrong_identity_rejected_at: wrongAudit.first_failed_step, js_wasm_gc_equal: true } },
  copied_cli: { files: packageFiles, compiler_on_path: false, source_in_package: false, portable_exit: valid.status, findings_exit: invalid.status, version: version.stdout.trim() },
};
writeFileSync(join(work, 'evidence.json'), `${JSON.stringify(evidence, null, 2)}\n`);
process.stdout.write(`${JSON.stringify(evidence, null, 2)}\n`);
