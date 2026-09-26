import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
function run(command, args) {
  const r = spawnSync(command, args, { cwd: root, encoding: 'utf8' });
  if (r.error) throw r.error;
  if (r.status !== 0) throw new Error(`${command} ${args.join(' ')} failed:\n${r.stdout}\n${r.stderr}`);
  return r.stdout.trim();
}
const tracked = run('git', ['ls-files', '--', '*.mbti']).split('\n').filter(Boolean);
const normalized = f => fs.readFileSync(path.join(root, f), 'utf8').replaceAll('\r\n', '\n');
const before = tracked.map(normalized);
run('moon', ['info']);
if (tracked.some((f,i) => normalized(f) !== before[i])) throw new Error('Public interfaces changed. Review regenerated .mbti files, stage them with the source change, then rerun checks.');
run('git', ['diff', '--exit-code', '--', '*.mbti']);
if (run('git', ['ls-files', '--others', '--exclude-standard', '--', '*.mbti'])) throw new Error('New public interfaces are untracked; review and stage them.');
console.log(`Public API interfaces verified (${tracked.length} files).`);
