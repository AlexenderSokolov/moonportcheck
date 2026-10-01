// Minimal ZIP reader used by both packaging and unpacking: parses the central
// directory, locates each local entry and inflates it. Supports stored (0) and
// deflate (8) entries, UTF-8 names. Pure Node, no filesystem side effects.
import { inflateRawSync } from 'node:zlib';
import assert from 'node:assert/strict';

const CRC_TABLE = (() => {
  const table = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
    table[n] = c >>> 0;
  }
  return table;
})();
export function crc32(buffer) {
  let crc = 0xFFFFFFFF;
  for (let i = 0; i < buffer.length; i++) crc = CRC_TABLE[(crc ^ buffer[i]) & 0xFF] ^ (crc >>> 8);
  return (crc ^ 0xFFFFFFFF) >>> 0;
}

export function parseZipEntries(zip) {
  // Locate the End Of Central Directory record from the tail.
  const magic = Buffer.from('PK\x05\x06', 'latin1');
  let eocd = -1;
  const from = Math.max(0, zip.length - 65557);
  for (let i = zip.length - 22; i >= from; i--) {
    if (zip[i] === 0x50 && zip[i + 1] === 0x4B && zip[i + 2] === 0x05 && zip[i + 3] === 0x06) { eocd = i; break; }
  }
  assert.ok(eocd >= 0, 'EOCD not found');
  const fileCount = zip.readUInt16LE(eocd + 10);
  const centralOffset = zip.readUInt32LE(eocd + 16);
  const entries = new Map();
  let cursor = centralOffset;
  for (let i = 0; i < fileCount; i++) {
    assert.equal(zip.readUInt32LE(cursor), 0x02014B50, 'bad central header');
    const method = zip.readUInt16LE(cursor + 10);
    const compressedSize = zip.readUInt32LE(cursor + 20);
    const uncompressedSize = zip.readUInt32LE(cursor + 24);
    const nameLength = zip.readUInt16LE(cursor + 28);
    const extraLength = zip.readUInt16LE(cursor + 30);
    const commentLength = zip.readUInt16LE(cursor + 32);
    const localOffset = zip.readUInt32LE(cursor + 42);
    const name = zip.subarray(cursor + 46, cursor + 46 + nameLength).toString('utf8');
    cursor += 46 + nameLength + extraLength + commentLength;
    assert.equal(zip.readUInt32LE(localOffset), 0x04034B50, `bad local header for ${name}`);
    const localNameLength = zip.readUInt16LE(localOffset + 26);
    const localExtraLength = zip.readUInt16LE(localOffset + 28);
    const dataStart = localOffset + 30 + localNameLength + localExtraLength;
    const compressed = zip.subarray(dataStart, dataStart + compressedSize);
    const storedCrc = zip.readUInt32LE(localOffset + 14);
    let data;
    if (method === 0) data = Buffer.from(compressed);
    else if (method === 8) data = inflateRawSync(compressed);
    else throw new Error(`unsupported zip method ${method} for ${name}`);
    assert.equal(data.length, uncompressedSize, `uncompressed size mismatch for ${name}`);
    assert.equal(crc32(data), storedCrc, `crc32 mismatch for ${name}`);
    entries.set(name, { crc32: storedCrc, data });
  }
  return entries;
}
