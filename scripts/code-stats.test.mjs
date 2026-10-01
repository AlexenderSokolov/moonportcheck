import test from 'node:test';
import assert from 'node:assert/strict';
import { countCodeLines, classifySource } from './code-stats.mjs';

test('code counter excludes blank and comment-only lines, not trailing-comment code', () => {
  assert.equal(countCodeLines('// comment\n\nfn f { // note\n  1\n}\n'), 3);
  assert.equal(countCodeLines('/* header\n * detail\n */\nconst x = 1;\n'), 1);
  assert.equal(countCodeLines('/* comment */ const x = 1;\nconst y = 2; /* tail */'), 2);
});

test('literal comment markers remain code and do not hide later lines', () => {
  assert.equal(countCodeLines('const url = "https://example.test";\nconst b = "/*";\nrun();'), 3);
  assert.equal(countCodeLines('const text = `first\n// literal\nlast`;\n// real comment'), 3);
  assert.equal(countCodeLines('#| MoonBit literal // text\nlet x = "quoted \\\" value"'), 2);
});

test('regular expression quotes and character classes do not turn later comments into code', () => {
  assert.equal(countCodeLines('const invalid = /[\"]/;\n// comment\nrun();'), 2);
  assert.equal(countCodeLines("const quoted = /['`]/g;\n/* comment */\nrun();"), 2);
  assert.equal(countCodeLines('const slash = /[/\"]/;\n// comment\nrun();'), 2);
});

test('regular expression escapes protect slashes, brackets, and quote characters', () => {
  for (const literal of [String.raw`/\/["']/`, String.raw`/[\]"/]/`, String.raw`/\"/`]) {
    assert.equal(countCodeLines(`const escaped = ${literal};\n// comment\nrun();`), 2, literal);
  }
});

test('division remains ordinary code before comments, strings, and another division', () => {
  const source = String.raw`const ratio = total / divisor; // " comment
const a = total / divisor / scale;
const b = total / "//".length;
// comment
run();`;
  assert.equal(countCodeLines(source), 4);
  assert.equal(countCodeLines('total /= divisor; // " comment\n// comment\nrun();'), 2);
});

test('expressions distinguish regex after return and operators from division after operands', () => {
  const source = String.raw`function match(value) { return /["/]/.test(value); }
const selected = ready ? /['/]/ : /["/]/;
const quotient = fn() / divisor;
const indexed = values[0] / divisor;
// comment
run();`;
  assert.equal(countCodeLines(source), 5);
  assert.equal(countCodeLines('if (ready && (valid)) /[\"]/g.test(value);\n// comment\nrun();'), 2);
  assert.equal(countCodeLines('value++ / divisor; // \" comment\n// comment\nrun();'), 2);
});

test('only runtime sources and real tests count toward the product gate', () => {
  assert.equal(classifySource('audit.mbt'), 'moonbit');
  assert.equal(classifySource('src/bridge/bridge.mbt'), 'moonbit');
  assert.equal(classifySource('audit_test.mbt'), 'tests_moonbit');
  assert.equal(classifySource('lib/host.mjs'), 'node');
  assert.equal(classifySource('tests/host.test.mjs'), 'tests_node');
  for (const file of ['scripts/bench.mjs', 'scripts/code-stats.test.mjs', 'cmd/parity/main.mbt', 'dist/bridge.js', 'pkg.generated.mbti', 'docs/example.mbt', 'tests/fixtures/expanded.mbt']) {
    assert.equal(classifySource(file), null, file);
  }
});
