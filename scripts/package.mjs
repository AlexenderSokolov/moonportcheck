// M16 candidate packaging: build a reproducible ZIP with the CLI, LICENSE,
// usage README and a CHECKSUMS.txt of every packaged file, plus an outer
// SHA256SUMS stream. Pure Node: stored entries with fixed timestamps make the
// archive byte-deterministic; crc32 and the central directory are written by
// hand so no external compression tool is needed on either OS.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync, mkdirSync, readdirSync, statSync } from 'node:fs';
import { join, posix } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { candidateArchiveName, ZIP_FIXED_DATE, ZIP_FIXED_TIME } from './zip-util.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const version = JSON.parse(readFileSync(join(root, 'package.json'), 'utf8')).version;
const head = spawnSync('git', ['rev-parse', '--short', 'HEAD'], { cwd: root, encoding: 'utf8' });
assert.equal(head.status, 0, 'candidate packaging requires a Git HEAD');
const shortSha = head.stdout.trim();
const platform = process.platform;

const packageFiles = ['bin/moonportcheck.mjs', 'lib/host.mjs', 'dist/bridge.js', 'package.json', 'LICENSE', 'README.md', 'PROJECT.md', 'CHANGELOG.md',
  ...readdirSync(join(root, 'docs')).filter(name => name.endsWith('.md')).sort().map(name => `docs/${name}`),
  ...readdirSync(join(root, 'examples')).filter(name => name.endsWith('.json')).sort().map(name => `examples/${name}`),
];
for (const relative of packageFiles) {
  assert.ok(statSync(join(root, relative)).isFile(), `${relative}: build the CLI and run from the repo root first`);
}

const CRC_TABLE = (() => {
  const table = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
    table[n] = c >>> 0;
  }
  return table;
})();
function crc32(buffer) {
  let crc = 0xFFFFFFFF;
  for (let i = 0; i < buffer.length; i++) crc = CRC_TABLE[(crc ^ buffer[i]) & 0xFF] ^ (crc >>> 8);
  return (crc ^ 0xFFFFFFFF) >>> 0;
}
function u16(value) { const b = Buffer.alloc(2); b.writeUInt16LE(value, 0); return b; }
function u32(value) { const b = Buffer.alloc(4); b.writeUInt32LE(value >>> 0, 0); return b; }

function buildZip(files) {
  const chunks = [];
  const central = [];
  let offset = 0;
  for (const { name, data } of files) {
    const nameBytes = Buffer.from(name, 'utf8');
    const crc = crc32(data);
    const local = Buffer.concat([
      Buffer.from('PK\x03\x04', 'latin1'),
      u16(20), u16(0x0800), u16(0), u16(ZIP_FIXED_TIME), u16(ZIP_FIXED_DATE),
      u32(crc), u32(data.length), u32(data.length),
      u16(nameBytes.length), u16(0),
      nameBytes,
      data,
    ]);
    chunks.push(local);
    central.push(Buffer.concat([
      Buffer.from('PK\x01\x02', 'latin1'),
      u16(20), u16(20), u16(0x0800), u16(0), u16(ZIP_FIXED_TIME), u16(ZIP_FIXED_DATE),
      u32(crc), u32(data.length), u32(data.length),
      u16(nameBytes.length), u16(0), u16(0), u16(0), u16(0),
      u32(0), u32(offset),
      nameBytes,
    ]));
    offset += local.length;
  }
  const centralStart = offset;
  const centralBuffer = Buffer.concat(central);
  const eocd = Buffer.concat([
    Buffer.from('PK\x05\x06', 'latin1'),
    u16(0), u16(0), u16(files.length), u16(files.length),
    u32(centralBuffer.length), u32(centralStart),
    u16(0),
  ]);
  return Buffer.concat([...chunks, centralBuffer, eocd]);
}

const entries = [];
for (const relative of packageFiles) {
  entries.push({ name: posix.join(...relative.split(/[\\/]/)), data: readFileSync(join(root, relative)) });
}
const checksumLines = entries
  .map(({ name, data }) => `${createHash('sha256').update(data).digest('hex')}  ${name}`)
  .sort()
  .join('\n');
entries.push({ name: 'CHECKSUMS.txt', data: Buffer.from(`${checksumLines}\n`, 'utf8') });

const zip = buildZip(entries);
const artifactDir = join(root, 'artifacts', 'candidate');
mkdirSync(artifactDir, { recursive: true });
const archiveName = candidateArchiveName(version, platform, shortSha);
const archivePath = join(artifactDir, archiveName);
writeFileSync(archivePath, zip);

const allFiles = [...entries];
const sha256 = (buffer) => createHash('sha256').update(buffer).digest('hex');
const sums = [...allFiles.map(({ name, data }) => `${sha256(data)}  ${name}`), `${sha256(zip)}  ${archiveName}`].sort().join('\n');
writeFileSync(join(artifactDir, 'SHA256SUMS.txt'), `${sums}\n`, 'utf8');

// Read the archive back and verify every entry inflates to its source bytes.
import { parseZipEntries } from './zip-util.mjs';
const seen = parseZipEntries(zip);
assert.equal(seen.size, entries.length, 'read-back entry count');
for (const { name, data } of entries) {
  assert.ok(seen.has(name), `missing ${name}`);
  const round = seen.get(name);
  assert.equal(round.crc32, crc32(data), `crc mismatch for ${name}`);
  assert.equal(round.data.equals(data), true, `content mismatch for ${name}`);
}

console.log(JSON.stringify({
  package: 'ok',
  version,
  sha: shortSha,
  platform,
  archive_path: archivePath,
  archive_sha256: sha256(zip),
  archive_bytes: zip.length,
  entries: allFiles.map(({ name }) => name),
}, null, 2));
