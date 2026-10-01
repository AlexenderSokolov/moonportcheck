import test from 'node:test';
import assert from 'node:assert/strict';
import { candidateArchiveName, crc32, parseZipEntries, ZIP_FIXED_DATE, ZIP_FIXED_TIME } from './zip-util.mjs';

test('candidate identity selects current commit even when older name sorts last', () => {
  const current = candidateArchiveName('0.2.0', 'win32', '3cdc9d4');
  const old = candidateArchiveName('0.2.0', 'win32', '9149176');
  assert.equal([old, current].sort().at(-1), old);
  assert.equal(current, 'moonportcheck-0.2.0-win32-3cdc9d4.zip');
  assert.notEqual(current, old);
});

test('fixed ZIP DOS timestamp decodes to a valid 1980-01-01 midnight', () => {
  assert.deepEqual({
    year: 1980 + (ZIP_FIXED_DATE >>> 9), month: (ZIP_FIXED_DATE >>> 5) & 15,
    day: ZIP_FIXED_DATE & 31, hour: ZIP_FIXED_TIME >>> 11,
    minute: (ZIP_FIXED_TIME >>> 5) & 63, second: (ZIP_FIXED_TIME & 31) * 2,
  }, { year: 1980, month: 1, day: 1, hour: 0, minute: 0, second: 0 });
});

function fixture(names = ['sample.txt']) {
  const locals = [];
  const centrals = [];
  let offset = 0;
  for (const name of names) {
    const bytes = Buffer.from(name);
    const data = Buffer.from('hello');
    const local = Buffer.alloc(30 + bytes.length + data.length);
    local.writeUInt32LE(0x04034b50);
    local.writeUInt16LE(20, 4);
    local.writeUInt16LE(0x0800, 6);
    local.writeUInt16LE(0x0021, 12);
    local.writeUInt32LE(crc32(data), 14);
    local.writeUInt32LE(data.length, 18);
    local.writeUInt32LE(data.length, 22);
    local.writeUInt16LE(bytes.length, 26);
    bytes.copy(local, 30);
    data.copy(local, 30 + bytes.length);
    const central = Buffer.alloc(46 + bytes.length);
    central.writeUInt32LE(0x02014b50);
    central.writeUInt16LE(20, 4);
    central.writeUInt16LE(20, 6);
    central.writeUInt16LE(0x0800, 8);
    central.writeUInt16LE(0x0021, 14);
    central.writeUInt32LE(crc32(data), 16);
    central.writeUInt32LE(data.length, 20);
    central.writeUInt32LE(data.length, 24);
    central.writeUInt16LE(bytes.length, 28);
    central.writeUInt32LE(offset, 42);
    bytes.copy(central, 46);
    offset += local.length;
    locals.push(local);
    centrals.push(central);
  }
  const central = Buffer.concat(centrals);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50);
  end.writeUInt16LE(names.length, 8);
  end.writeUInt16LE(names.length, 10);
  end.writeUInt32LE(central.length, 12);
  end.writeUInt32LE(offset, 16);
  return Buffer.concat([...locals, central, end]);
}

test('candidate ZIP reader verifies file bytes and central metadata', () => {
  const zip = fixture();
  assert.equal(parseZipEntries(zip).get('sample.txt').data.toString(), 'hello');
  const corrupt = Buffer.from(zip);
  corrupt[14] ^= 1;
  assert.throws(() => parseZipEntries(corrupt), /central crc mismatch/);
  const changedName = Buffer.from(zip);
  changedName[30] = 120;
  assert.throws(() => parseZipEntries(changedName), /local name mismatch/);
});

test('candidate ZIP reader rejects ambiguous duplicate entries', () => {
  assert.throws(() => parseZipEntries(fixture(['sample.txt', 'sample.txt'])), /duplicate zip entry/);
});
