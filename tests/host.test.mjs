import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { parseArguments, readManifest, scan } from '../lib/host.mjs';

const directory = () => ({ isDirectory: () => true, isFile: () => false, isSymbolicLink: () => false });
const file = () => ({ isDirectory: () => false, isFile: () => true, isSymbolicLink: () => false });
const special = () => ({ isDirectory: () => false, isFile: () => false, isSymbolicLink: () => false });
const ioFailure = (code) => Object.assign(new Error('secret absolute host path'), { code });
const fixture = () => fs.mkdtemp(path.join(os.tmpdir(), 'moonportcheck-host-'));

test('arguments are strict; JSON format is retained for malformed requests', () => {
  assert.deepEqual(parseArguments(['scan', 'tree', '--format', 'json']), { mode: 'scan', target: 'tree', format: 'json' });
  assert.deepEqual(parseArguments(['check', '--format', 'text', 'paths.json']), { mode: 'check', target: 'paths.json', format: 'text' });
  assert.deepEqual(parseArguments(['--help']), { mode: 'help' });
  assert.deepEqual(parseArguments(['--version']), { mode: 'version' });
  for (const args of [[], ['scan'], ['bogus', 'tree'], ['check', 'one', 'two'], ['check', 'one', '--wat'], ['check', 'one', '--format'], ['check', 'one', '--format', 'xml'], ['check', 'one', '--format', 'text', '--format', 'text'], ['--help', 'tree']]) {
    const result = parseArguments(args);
    assert.equal(result.mode, 'error', JSON.stringify(args));
    assert.equal(result.exit_code, 2);
    assert.equal(result.code, 'ARGUMENT_ERROR');
  }
  assert.equal(parseArguments(['check', 'one', '--unknown', '--format', 'json']).format, 'json');
});

test('manifest reads strict UTF-8 and classifies read failures', async () => {
  const root = await fixture();
  const good = path.join(root, 'good.json');
  const bad = path.join(root, 'bad.json');
  await fs.writeFile(good, '[{"path":"中文.txt","kind":"file"}]');
  await fs.writeFile(bad, Buffer.from([0xc3, 0x28]));
  assert.match(await readManifest(good), /中文/);
  await assert.rejects(readManifest(bad), { code: 'INPUT_ENCODING', exitCode: 2 });
  await assert.rejects(readManifest(path.join(root, 'missing')), { code: 'INPUT_IO_ERROR', exitCode: 3 });
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
