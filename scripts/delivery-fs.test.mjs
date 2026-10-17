import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {assertFilesystemLayout} from './delivery-fs.mjs';

test('physical verifier rejects wrong bytes with the correct path set and leftover files',()=>{
  const root=fileURLToPath(new URL('../artifacts/',import.meta.url));fs.mkdirSync(root,{recursive:true});
  const work=fs.mkdtempSync(path.join(root,'fs-negative-control-'));
  const initial=new Map([['target',[{path:'b',kind:'file',bytes:Buffer.from('Y')}]]]);
  const expected=[{path:'a',kind:'file',origin:{root:'target',path:'b'}}];
  fs.writeFileSync(path.join(work,'a'),'X');
  assert.throws(()=>assertFilesystemLayout(work,expected,initial),/Wrong initial content/);
  fs.writeFileSync(path.join(work,'a'),'Y');assertFilesystemLayout(work,expected,initial);
  fs.writeFileSync(path.join(work,'scratch'),'leftover');
  assert.throws(()=>assertFilesystemLayout(work,expected,initial),/file\/directory set differs/);
});
