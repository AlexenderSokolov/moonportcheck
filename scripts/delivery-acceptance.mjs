import {spawnSync} from 'node:child_process';
import assert from 'node:assert/strict';
for(const script of ['delivery-parity.mjs','delivery-verification.mjs','delivery-fs.mjs','delivery-cases.mjs']){
  const r=spawnSync(process.execPath,[`scripts/${script}`],{encoding:'utf8',maxBuffer:32*1024*1024});
  process.stdout.write(r.stdout||'');process.stderr.write(r.stderr||'');
  assert.equal(r.error,undefined);assert.equal(r.status,0,script);
}
