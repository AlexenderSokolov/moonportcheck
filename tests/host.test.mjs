import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { parseArguments, readConfig, readManifest, scan } from '../lib/host.mjs';

const directory = () => ({ isDirectory: () => true, isFile: () => false, isSymbolicLink: () => false });
const file = () => ({ isDirectory: () => false, isFile: () => true, isSymbolicLink: () => false });
const special = () => ({ isDirectory: () => false, isFile: () => false, isSymbolicLink: () => false });
const ioFailure = (code) => Object.assign(new Error('secret absolute host path'), { code });
const fixture = () => fs.mkdtemp(path.join(os.tmpdir(), 'moonportcheck-host-'));

test('arguments are strict; JSON format is retained for malformed requests', () => {
  assert.deepEqual(parseArguments(['scan', 'tree', '--format', 'json']), { mode: 'scan', target: 'tree', format: 'json', excludes: [], config: null });
  assert.deepEqual(parseArguments(['check', '--format', 'text', 'paths.json']), { mode: 'check', target: 'paths.json', format: 'text', excludes: [], config: null });
  assert.deepEqual(parseArguments(['--help']), { mode: 'help' });
  assert.deepEqual(parseArguments(['--version']), { mode: 'version' });
  assert.deepEqual(parseArguments(['scan', 'tree', '--exclude', '*.tmp', '--exclude', 'cache/', '--config', 'mc.json', '--format', 'json']), { mode: 'scan', target: 'tree', format: 'json', excludes: ['*.tmp', 'cache/'], config: 'mc.json' });
  for (const args of [[], ['scan'], ['bogus', 'tree'], ['check', 'one', 'two'], ['check', 'one', '--wat'], ['check', 'one', '--format'], ['check', 'one', '--format', 'xml'], ['check', 'one', '--format', 'text', '--format', 'text'], ['--help', 'tree'], ['scan', 'tree', '--config'], ['scan', 'tree', '--config', 'a', '--config', 'b'], ['scan', 'tree', '--exclude'], ['rules', '--exclude', 'x'], ['rules', '--config', 'mc.json'], ['explain', 'NAME_RESERVED', '--config', 'mc.json'], ['explain', 'NAME_RESERVED', '--exclude', 'x'], ['check', 'one', '--exclude', '\ud800']]) {
    const result = parseArguments(args);
    assert.equal(result.mode, 'error', JSON.stringify(args));
    assert.equal(result.exit_code, 2);
    assert.equal(result.code, 'ARGUMENT_ERROR');
  }
  assert.equal(parseArguments(['check', 'one', '--unknown', '--format', 'json']).format, 'json');
});

test('manifest and config reads strict UTF-8 and classify read failures', async () => {
  const root = await fixture();
  const good = path.join(root, 'good.json');
  const bad = path.join(root, 'bad.json');
  const goodConfig = path.join(root, 'good.config');
  const badConfig = path.join(root, 'bad.config');
  await fs.writeFile(good, '[{"path":"中文.txt","kind":"file"}]');
  await fs.writeFile(bad, Buffer.from([0xc3, 0x28]));
  await fs.writeFile(goodConfig, '{"schema_version":1,"exclude":["**/cache"]}');
  await fs.writeFile(badConfig, Buffer.from([0xff, 0xfe]));
  assert.match(await readManifest(good), /中文/);
  assert.match(await readConfig(goodConfig), /schema_version/);
  await assert.rejects(readManifest(bad), { code: 'INPUT_ENCODING', exitCode: 2 });
  await assert.rejects(readConfig(badConfig), { code: 'INPUT_ENCODING', exitCode: 2 });
  await assert.rejects(readManifest(path.join(root, 'missing')), { code: 'INPUT_IO_ERROR', exitCode: 3 });
  await assert.rejects(readConfig(path.join(root, 'missing-config')), { code: 'INPUT_IO_ERROR', exitCode: 3 });
});

test('real scan includes hidden files and empty directories; root is not an entry', async () => {
  const root = await fixture();
  await fs.mkdir(path.join(root, 'empty'));
  await fs.mkdir(path.join(root, '中文'));
  await fs.writeFile(path.join(root, '.hidden'), 'contents are irrelevant');
  await fs.writeFile(path.join(root, '中文', 'file name.txt'), 'ok');
  const result = await scan(root);
  assert.deepEqual(result.scan_issues, []);
  assert.deepEqual(result.entries, [
    { path: '.hidden', kind: 'file' },
    { path: 'empty', kind: 'directory' },
    { path: '中文', kind: 'directory' },
    { path: '中文/file name.txt', kind: 'file' },
  ]);
});

test('real links or Windows junctions are never traversed, including the root', async () => {
  const root = await fixture();
  const outside = await fixture();
  await fs.writeFile(path.join(outside, 'secret.txt'), 'never enumerate this');
  const link = path.join(root, 'link');
  await fs.symlink(outside, link, process.platform === 'win32' ? 'junction' : 'dir');
  const result = await scan(root);
  assert.deepEqual(result.entries, []);
  assert.deepEqual(result.scan_issues.map(({ code, path }) => ({ code, path })), [{ code: 'SCAN_LINK_SKIPPED', path: 'link' }]);
  const rootResult = await scan(link);
  assert.deepEqual(rootResult.entries, []);
  assert.equal(rootResult.scan_issues[0].code, 'SCAN_LINK_SKIPPED');
  assert.equal(rootResult.scan_issues[0].path, '.');
});

test('POSIX raw names preserve backslashes, leading BOM and invalid UTF-8 evidence', { skip: process.platform === 'win32' }, async () => {
  const root = await fixture();
  await fs.writeFile(path.join(root, 'bad\\name'), '');
  await fs.writeFile(path.join(root, '\uFEFFname'), '');
  await fs.writeFile(Buffer.concat([Buffer.from(root + '/'), Buffer.from([0xff, 0xfe])]), '');
  const result = await scan(root);
  assert.deepEqual(result.entries.map((entry) => entry.path), ['bad\\name', '\uFEFFname']);
  assert.equal(result.scan_issues.length, 1);
  assert.equal(result.scan_issues[0].code, 'SCAN_NAME_ENCODING');
  assert.match(result.scan_issues[0].path, /fffe/);
});

test('per-child lstat failures retain discovered entries and sanitize error messages', async () => {
  const root = path.resolve('virtual-tree');
  const calls = [];
  const result = await scan(root, { fs: {
    async lstat(name) {
      calls.push(name);
      if (name === root) return directory();
      if (name.endsWith('unreadable')) throw ioFailure('EACCES');
      return file();
    },
    async readdir() { return [Buffer.from('good'), Buffer.from('unreadable')]; },
    async readFile() { assert.fail('scan must not read file contents'); },
  } });
  assert.equal(calls.length, 3);
  assert.deepEqual(result.entries, [{ path: 'good', kind: 'file' }]);
  assert.equal(result.scan_issues[0].code, 'SCAN_IO_ERROR');
  assert.equal(result.scan_issues[0].path, 'unreadable');
  assert.match(result.scan_issues[0].message, /EACCES/);
  assert.doesNotMatch(JSON.stringify(result), /secret|virtual-tree/);
});

test('directory enumeration failures, unsupported types and malformed names are incomplete', async () => {
  const root = path.resolve('virtual-tree');
  const result = await scan(root, { fs: {
    async lstat(name) {
      if (name.endsWith('special')) return special();
      return directory();
    },
    async readdir(name) {
      if (name !== root) throw ioFailure('EPERM');
      return [Buffer.from('locked'), Buffer.from('special'), Buffer.from([0xff]), '\ud800'];
    },
  } });
  assert.deepEqual(result.entries, [{ path: 'locked', kind: 'directory' }]);
  assert.deepEqual(result.scan_issues.map((issue) => issue.code).sort(), ['SCAN_IO_ERROR', 'SCAN_NAME_ENCODING', 'SCAN_NAME_ENCODING', 'SCAN_TYPE_UNSUPPORTED']);
});

test('root missing or not a directory is incomplete', async () => {
  const root = await fixture();
  const ordinaryFile = path.join(root, 'file');
  await fs.writeFile(ordinaryFile, '');
  assert.equal((await scan(path.join(root, 'missing'))).scan_issues[0].code, 'SCAN_IO_ERROR');
  assert.equal((await scan(ordinaryFile)).scan_issues[0].code, 'SCAN_TYPE_UNSUPPORTED');
});

test('scan order does not depend on filesystem enumeration order', async () => {
  const root = path.resolve('virtual-tree');
  async function ordered(names) {
    return scan(root, { fs: {
      async lstat(name) { return name === root ? directory() : file(); },
      async readdir() { return names.map((name) => Buffer.from(name)); },
    } });
  }
  assert.deepEqual(await ordered(['z', 'A', 'b']), await ordered(['b', 'z', 'A']));
});

test('scan records an excluded directory but never enumerates its subtree', async () => {
  const root = path.resolve('virtual-tree');
  const readdirCalls = [];
  const entriesOf = (name) => {
    if (name === root) return ['a', 'cache', 'z'].map((item) => Buffer.from(item));
    if (name.endsWith('\\a') || name.endsWith('/a')) return [Buffer.from('a.txt')];
    throw ioFailure('EPERM');
  };
  const result = await scan(root, {
    excludeMatch: (relative, kind) => relative === 'cache' && kind === 'directory',
    fs: {
      async lstat(name) {
        if (name === root) return directory();
        const leaf = name.slice(Math.max(name.lastIndexOf('\\'), name.lastIndexOf('/')) + 1);
        return leaf === 'a' || leaf === 'cache' ? directory() : file();
      },
      async readdir(name) {
        readdirCalls.push(name);
        return entriesOf(name);
      },
    },
  });
  const sorted = (entries) => entries.slice().sort((l, r) => (l.path < r.path ? -1 : l.path > r.path ? 1 : 0));
  assert.deepEqual(sorted(result.entries), sorted([
    { path: 'a', kind: 'directory' },
    { path: 'a/a.txt', kind: 'file' },
    { path: 'cache', kind: 'directory' },
    { path: 'z', kind: 'file' },
  ]));
  assert.deepEqual(result.scan_issues, []);
  assert.ok(readdirCalls.some((name) => /[\\/]a$/.test(name)), 'sibling tree was enumerated');
  assert.ok(!readdirCalls.some((name) => /[\\/]cache$/.test(name)), 'excluded subtree was pruned');
});
