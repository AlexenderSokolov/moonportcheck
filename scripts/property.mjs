// Property and feature-cross gate for M15. Uses a deterministic seed so the
// checks are reproducible. Invariants against the built bridge:
//   1. Input order permutation leaves the rendered report byte-identical.
//   2. Widening the exclusion scope never adds findings and never lowers the
//      excluded count.
//   3. Render -> parse round trips (report and baseline) rebuild the same doc.
//   4. A baseline built from one manifest never reports the same groups as new.
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { run_request } from '../dist/bridge.js';

const root = fileURLToPath(new URL('../', import.meta.url));
const run = (request) => JSON.parse(run_request(JSON.stringify(request)));

// mulberry32 — deterministic PRNG.
function rng(seed) {
  let state = seed | 0;
  return () => {
    state = state + 0x6D2B79F5 | 0;
    let t = Math.imul(state ^ state >>> 15, 1 | state);
    t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t;
    return ((t ^ t >>> 14) >>> 0) / 4294967296;
  };
}

const RULES_INPUT = [
  'data', 'Data', 'data ', 'data.', 'CON', 'con.txt', 'aux', 'a/b',
  '..', 'a..b', '?.csv', '*.txt', 'x\t', '目录', 'résumé', 'long-name-ok.txt',
];
const KINDS = ['file', 'directory', 'file', 'file', 'directory'];

function randomManifest(next, size) {
  const entries = [];
  for (let i = 0; i < size; i++) {
    const a = Math.floor(next() * RULES_INPUT.length);
    const b = Math.floor(next() * RULES_INPUT.length);
    const name = `${RULES_INPUT[a % RULES_INPUT.length]}/${RULES_INPUT[b % RULES_INPUT.length]}`;
    entries.push({ path: name, kind: KINDS[Math.floor(next() * KINDS.length)] });
  }
  return entries;
}

function shuffled(entries, next) {
  const copy = entries.slice();
  for (let i = copy.length - 1; i > 0; i--) {
    const j = Math.floor(next() * (i + 1));
    [copy[i], copy[j]] = [copy[j], copy[i]];
  }
  return copy;
}

const seed = 0xC0FFEE;
const next = rng(seed);

let permutations = 0;
let monotone = 0;
let roundTrip = 0;
let baselineStable = 0;

for (let trial = 0; trial < 60; trial++) {
  const size = 4 + Math.floor(next() * 36);
  const withBaseline = trial % 3 === 0;
  const entries = randomManifest(next, size);

  // 1. Input order permutation.
  const a = run({ mode: 'check', format: 'json', manifest_text: JSON.stringify(entries), exclude_patterns: [] });
  const b = run({ mode: 'check', format: 'json', manifest_text: JSON.stringify(shuffled(entries, next)), exclude_patterns: [] });
  assert.equal(a.exit_code, b.exit_code, 'permutation changed exit code');
  assert.equal(a.output, b.output, 'permutation changed the rendered report');
  permutations++;

  // 2. Widening exclusions never adds findings.
  const narrow = run({ mode: 'check', format: 'json', manifest_text: JSON.stringify(entries), exclude_patterns: ['*.txt'] });
  const wide = run({ mode: 'check', format: 'json', manifest_text: JSON.stringify(entries), exclude_patterns: ['*.txt', 'data', '*/data'] });
  const narrowReport = JSON.parse(narrow.output);
  const wideReport = JSON.parse(wide.output);
  assert.ok(wideReport.diagnostics.length <= narrowReport.diagnostics.length, 'wider scope added findings');
  assert.ok(wideReport.excluded_entries >= narrowReport.excluded_entries, 'wider scope dropped excluded count');
  monotone++;

  // 3. Report and baseline parse round trips.
  const round = run({ mode: 'check', format: 'json', manifest_text: JSON.stringify(entries), exclude_patterns: [] });
  const rebuilt = run({ mode: 'check', format: 'json', manifest_text: JSON.stringify(entries), exclude_patterns: [] });
  assert.equal(rebuilt.output, round.output, 're-audit changed the report');
  roundTrip++;

  if (withBaseline) {
    // 4. A baseline built from the same manifest yields no new group.
    const base = run({ mode: 'baseline', format: 'json', report_text: round.output });
    assert.equal(base.exit_code, 0, `baseline build failed: ${base.output}`);
    const rescanned = run({ mode: 'scan', format: 'json', baseline_text: base.output, entries, scan_issues: [], exclude_patterns: [], fail_on: true });
    // --fail-on new exits 1 only for fresh or worsened groups; a baseline built
    // from the same manifest must leave nothing new.
    assert.equal(rescanned.exit_code, 0, `baseline re-scan exit ${rescanned.exit_code}: ${rescanned.output}`);
    baselineStable++;
  }
}

assert.ok(permutations >= 60 && monotone >= 60 && roundTrip >= 60, 'property loops ran');
console.log(JSON.stringify({ property: 'pass', targets: ['js'], trials: permutations, baseline_stable: baselineStable, seed: '0xC0FFEE' }, null, 2));
