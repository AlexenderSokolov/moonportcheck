import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const expressionKeywords = new Set(['return', 'throw', 'case', 'delete', 'void', 'typeof', 'new', 'yield', 'await', 'in', 'instanceof', 'else', 'do']);
const controlKeywords = new Set(['if', 'while', 'for', 'with', 'switch', 'catch']);

function regexEnd(line, start) {
  let characterClass = false;
  for (let i = start + 1; i < line.length; i++) {
    const c = line[i];
    if (c === '\\') i++;
    else if (c === '[') characterClass = true;
    else if (c === ']') characterClass = false;
    else if (c === '/' && !characterClass) return i;
  }
  return -1;
}

export function countCodeLines(source) {
  let block = false, quote = '', count = 0, expressionStart = true, previousToken = '';
  const parentheses = [];
  for (const line of source.split(/\r?\n/)) {
    if (!block && !quote && line.trimStart().startsWith('#|')) { count++; continue; }
    let code = false;
    for (let i = 0; i < line.length; i++) {
      const c = line[i], next = line[i + 1];
      if (block) {
        if (c === '*' && next === '/') { block = false; i++; }
      } else if (quote) {
        code = true;
        if (c === '\\') i++;
        else if (c === quote) { quote = ''; expressionStart = false; previousToken = 'literal'; }
      } else if (c === '/' && next === '/') break;
      else if (c === '/' && next === '*') { block = true; i++; }
      else if (!/\s/.test(c)) {
        code = true;
        if (c === '"' || c === "'" || c === '`') quote = c;
        else if (c === '\\') i++;
        else if (c === '/' && expressionStart && regexEnd(line, i) !== -1) {
          i = regexEnd(line, i);
          while (/[a-z]/i.test(line[i + 1] || '') && i + 1 < line.length) i++;
          expressionStart = false;
          previousToken = 'literal';
        } else if (/[a-zA-Z_$]/.test(c)) {
          const start = i;
          while (i + 1 < line.length && /[a-zA-Z0-9_$]/.test(line[i + 1])) i++;
          previousToken = line.slice(start, i + 1);
          expressionStart = expressionKeywords.has(previousToken);
        } else if (/[0-9]/.test(c)) {
          while (i + 1 < line.length && /[a-zA-Z0-9_.]/.test(line[i + 1])) i++;
          expressionStart = false;
          previousToken = 'literal';
        } else if (c === '(') {
          parentheses.push(controlKeywords.has(previousToken));
          expressionStart = true;
          previousToken = c;
        } else if (c === ')') {
          expressionStart = parentheses.pop() === true;
          previousToken = c;
        } else if ((c === '+' || c === '-') && next === c) {
          i++;
          previousToken = c + c;
        } else {
          expressionStart = c !== ']' && c !== '.';
          previousToken = c;
        }
      }
    }
    if (code) count++;
  }
  return count;
}

export function classifySource(relative) {
  const name = relative.replaceAll('\\', '/');
  if (name.split('/').some(p => ['.git', '.toolchains', '_build', 'target', 'artifacts', 'dist', 'node_modules', 'scripts', 'docs', 'examples', 'fixtures'].includes(p))) return null;
  if (name.startsWith('cmd/parity/')) return null;
  if (/(?:_test|_wbtest)\.mbt$/.test(name)) return 'tests_moonbit';
  if (name.startsWith('tests/') && name.endsWith('.test.mjs')) return 'tests_node';
  if (name.endsWith('.mbt')) return 'moonbit';
  if (/^(lib|bin)\/.+\.mjs$/.test(name)) return 'node';
  return null;
}

export function collectStats(root) {
  const files = [];
  const excluded = new Set(['.git', '.toolchains', '_build', 'target', 'artifacts', 'dist', 'node_modules', 'scripts', 'docs', 'examples', 'fixtures']);
  function walk(directory, relative = '') {
    for (const entry of fs.readdirSync(directory, { withFileTypes: true }).sort((a,b) => a.name < b.name ? -1 : a.name > b.name ? 1 : 0)) {
      if (excluded.has(entry.name)) continue;
      const rel = relative ? `${relative}/${entry.name}` : entry.name;
      const full = path.join(directory, entry.name);
      if (entry.isDirectory()) walk(full, rel);
      else if (entry.isFile()) {
        const category = classifySource(rel);
        if (category) {
          const text = fs.readFileSync(full, 'utf8');
          files.push({ path: rel, category, physical_lines: text.trimEnd().split(/\r?\n/).length, code_lines: countCodeLines(text) });
        }
      }
    }
  }
  walk(root);
  const totals = { moonbit: 0, node: 0, tests_moonbit: 0, tests_node: 0 };
  for (const f of files) totals[f.category] += f.code_lines;
  return { schema_version: 1, method: 'Handwritten runtime sources and tests; excludes blank/comment-only lines, tooling, generated code, fixtures and documentation.', totals, total_code_lines: Object.values(totals).reduce((a,b) => a+b,0), files };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  if (args.length !== 0 && !(args.length === 2 && args[0] === '--min' && /^\d+$/.test(args[1]))) throw new Error('Usage: node scripts/code-stats.mjs [--min N]');
  const stats = collectStats(fileURLToPath(new URL('../', import.meta.url)));
  console.log(JSON.stringify(stats, null, 2));
  if (stats.total_code_lines < Number(args[1] ?? 0)) process.exitCode = 1;
}
