import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { performance } from 'node:perf_hooks';
import { fileURLToPath } from 'node:url';
import fs from 'node:fs';
import path from 'node:path';

// Scale acceptance for M15: keep the 100k ordinary and grouped-conflict cases,
// and add deep paths, a long shared prefix, and one very large duplicate group.
// Values recorded (time, peak RSS, report volume) are observations, never
// committed as performance promises.
const cases = {
  'ordinary-100k': () => Array.from({ length: 100_000 }, (_, index) => ({
    path: `dataset-${Math.floor(index / 1000)}/result-${String(index).padStart(6, '0')}.csv`,
    kind: 'file',
  })),
  'grouped-conflicts-100k': () => Array.from({ length: 100_000 }, (_, index) => {
    // 100 case-folded names, 2 spellings each, 500 copies per spelling.
    // Pairwise diagnostics would explode; the expected grouped result is 300.
    const spelling = Math.floor(index / 100) % 2 === 0 ? 'Case' : 'case';
    return { path: `results/${spelling}-${index % 100}.csv`, kind: 'file' };
  }),
  'deep-paths-2000': () => Array.from({ length: 2000 }, (_, index) => ({
    path: `${Array.from({ length: 40 }, (_, depth) => `d${depth % 10}`).join('/')}/result-${String(index).padStart(5, '0')}.${'x'.repeat(30)}csv`,
    kind: 'file',
  })),
  'long-prefix-2000': () => Array.from({ length: 2000 }, (_, index) => ({
    path: `${'A'.repeat(1500)}/tail-${String(index).padStart(5, '0')}.csv`,
    kind: 'file',
  })),
  'single-duplicate-10k': () => Array.from({ length: 10_000 }, () => ({
    path: 'results/same-name.csv',
    kind: 'file',
  })),
};
const script = fileURLToPath(import.meta.url);

function memory() {
  const { rss, heapTotal, heapUsed, external, arrayBuffers } = process.memoryUsage();
  return { rss_bytes: rss, heap_total_bytes: heapTotal, heap_used_bytes: heapUsed, external_bytes: external, array_buffers_bytes: arrayBuffers };
}

function assertScale(name, entries, response, report) {
  assert.equal(report.complete, true);
  assert.equal(report.source, 'manifest');
  assert.equal(report.summary.entries, entries.length);
  assert.equal(report.summary.scan_issues, 0);
  if (name === 'ordinary-100k' || name === 'deep-paths-2000' || name === 'long-prefix-2000') {
    assert.equal(response.exit_code, 0);
    assert.deepEqual(report.diagnostics, []);
  } else if (name === 'grouped-conflicts-100k') {
    assert.equal(response.exit_code, 1);
    const duplicates = report.diagnostics.filter((item) => item.code === 'PATH_DUPLICATE');
    const collisions = report.diagnostics.filter((item) => item.code === 'PATH_CASE_COLLISION');
    assert.equal(duplicates.length, 200, 'Duplicate paths must be grouped');
    assert.equal(collisions.length, 100, 'Case collisions must be grouped');
    assert.equal(report.diagnostics.length, 300, 'Unexpected or pairwise diagnostics');
    for (const duplicate of duplicates) {
      assert.equal(duplicate.occurrences, 500, 'Duplicate counts must remain exact');
      assert.equal(duplicate.paths.length, 1);
    }
    for (const collision of collisions) assert.equal(collision.paths.length, 2);
  } else if (name === 'single-duplicate-10k') {
    assert.equal(response.exit_code, 1);
    assert.equal(report.diagnostics.length, 1, 'One large group');
    const group = report.diagnostics[0];
    assert.equal(group.code, 'PATH_DUPLICATE');
    assert.equal(group.occurrences, 10_000, 'Duplicate count must remain exact');
    assert.equal(group.members.length, 1);
  } else {
    throw new Error(`Unexpected case ${name}`);
  }
}

async function measure(name) {
  const { run_request } = await import('../dist/bridge.js');
  const entries = cases[name]();
  const manifest_text = JSON.stringify(entries);
  const request = JSON.stringify({ mode: 'check', format: 'json', manifest_text });
  const before = memory();
  const started = performance.now();
  const responseText = run_request(request);
  const elapsed_ms = performance.now() - started;
  const after = memory();
  const response = JSON.parse(responseText);
  const report = JSON.parse(response.output);
  assertScale(name, entries, response, report);
  return {
    name,
    entries: entries.length,
    manifest_utf8_bytes: Buffer.byteLength(manifest_text),
    request_utf8_bytes: Buffer.byteLength(request),
    response_utf8_bytes: Buffer.byteLength(responseText),
    exit_code: response.exit_code,
    diagnostic_groups: report.diagnostics.length,
    elapsed_ms,
    memory: { before, after, process_peak_rss_bytes: process.resourceUsage().maxRSS * 1024 },
  };
}

if (process.argv[2] === '--case') {
  assert.equal(process.argv.length, 4);
  assert.ok(process.argv[3] in cases, 'Unknown benchmark case');
  process.stdout.write(`${JSON.stringify(await measure(process.argv[3]))}\n`);
} else {
  assert.equal(process.argv.length, 2, 'Usage: node scripts/bench.mjs');
  const results = Object.keys(cases).map((name) => {
    // Separate processes prevent the first case's retained heap and peak RSS
    // from contaminating the next case's measurements.
    const result = spawnSync(process.execPath, [script, '--case', name], {
      encoding: 'utf8', maxBuffer: 8 * 1024 * 1024,
    });
    if (result.error) throw result.error;
    assert.equal(result.signal, null, `${name}: terminated by signal`);
    assert.equal(result.status, 0, `${name}: ${result.stderr}`);
    return JSON.parse(result.stdout);
  });
  const record = {
    schema_version: 1,
    node: process.version,
    platform: process.platform,
    arch: process.arch,
    measurement: 'One fresh process per case. elapsed_ms measures run_request only (JSON parse, audit, render); memory snapshots bracket it. Peak RSS includes process startup, input preparation and result validation. Values are observations, not performance guarantees.',
    cases: results,
  };
  process.stdout.write(`${JSON.stringify(record, null, 2)}\n`);
  fs.writeFileSync(path.join(fileURLToPath(new URL('../', import.meta.url)), 'artifacts', 'benchmark.json'), `${JSON.stringify(record, null, 2)}\n`);
}
