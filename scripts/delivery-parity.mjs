import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
const output=target=>{const r=spawnSync('moon',['run','cmd/delivery-demo','--target',target,'--release','--deny-warn'],{maxBuffer:32*1024*1024});assert.equal(r.status,0,r.stderr?.toString());return r.stdout;};
const js=output('js'),wasm=output('wasm-gc');assert.deepEqual(js,wasm,'Delivery public API output differs across targets');
const docs=js.toString().trim().split(/\r?\n/).map(JSON.parse);assert.equal(docs.length,6);
assert.ok(docs.filter(d=>d.format==='moonportcheck-delivery-plan').every(d=>d.status==='ready'));
assert.ok(docs.filter(d=>d.format==='moonportcheck-delivery-audit').every(d=>d.valid));
console.log(JSON.stringify({delivery_parity:'pass',targets:['js','wasm-gc'],documents:docs.length,bytes:js.length}));
