import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { performance } from 'node:perf_hooks';
import { fileURLToPath } from 'node:url';

const count = 100_000;
const cases = ['ordinary-100k', 'grouped-conflicts-100k'];
const script = fileURLToPath(import.meta.url);

function memory() {
  const { rss, heapTotal, heapUsed, external, arrayBuffers } = process.memoryUsage();
  return { rss_bytes: rss, heap_total_bytes: heapTotal, heap_used_bytes: heapUsed, external_bytes: external, array_buffers_bytes: arrayBuffers };
}

async function measure(name) {
  assert.ok(cases.includes(name), 'Unknown benchmark case');
  const { run_request } = await import('../dist/bridge.js');
  const entries = Array.from({ length: count }, (_, index) => {
    if (name === 'ordinary-100k') {
      return { path: `dataset-${Math.floor(index / 1000)}/result-${String(index).padStart(6, '0')}.csv`, kind: 'file' };
    }
    // 100 case-folded names, 2 spellings each, 500 copies per spelling.
    // Pairwise diagnostics would explode; the expected grouped result is 300.
    const spelling = Math.floor(index / 100) % 2 === 0 ? 'Case' : 'case';
    return { path: `results/${spelling}-${index % 100}.csv`, kind: 'file' };
  });
  const manifest_text = JSON.stringify(entries);
  const request = JSON.stringify({ mode: 'check', format: 'json', manifest_text });
  const before = memory();
  const started = performance.now();
  const responseText = run_request(request);
  const elapsed_ms = performance.now() - started;
  const after = memory();
  const response = JSON.parse(responseText);
  const report = JSON.parse(response.output);
  assert.equal(report.complete, true);
  assert.equal(report.source, 'manifest');
  assert.equal(report.summary.entries, count);
  assert.equal(report.summary.scan_issues, 0);
  if (name === 'ordinary-100k') {
    assert.equal(response.exit_code, 0);
    assert.deepEqual(report.diagnostics, []);
  } else {
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
  }
  return {
    name,
    entries: count,
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
  process.stdout.write(`${JSON.stringify(await measure(process.argv[3]))}\n`);
} else {
  assert.equal(process.argv.length, 2, 'Usage: node scripts/bench.mjs');
  const results = cases.map((name) => {
    // Separate processes prevent the first case's retained heap and peak RSS
    // from contaminating the second case's measurements.
    const result = spawnSync(process.execPath, [script, '--case', name], {
      encoding: 'utf8', maxBuffer: 8 * 1024 * 1024,
    });
    if (result.error) throw result.error;
    assert.equal(result.signal, null, `${name}: terminated by signal`);
    assert.equal(result.status, 0, `${name}: ${result.stderr}`);
    return JSON.parse(result.stdout);
  });
  process.stdout.write(`${JSON.stringify({
    schema_version: 1,
    node: process.version,
    platform: process.platform,
    arch: process.arch,
    measurement: 'One fresh process per case. elapsed_ms measures run_request only (JSON parse, audit, render); memory snapshots bracket it. Peak RSS includes process startup, input preparation and result validation. Values are observations, not performance guarantees.',
    cases: results,
  }, null, 2)}\n`);
}
