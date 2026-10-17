import test from 'node:test';
import assert from 'node:assert/strict';
import {interfaceHash,verifyInterfaceBaseline} from './interface-baseline.mjs';
test('explicit local interface baseline rejects drift and extra interfaces',()=>{
  const files=[{path:'pkg.generated.mbti',text:'pub fn stable() -> Unit\n'}];
  const baseline={schema_version:1,files:files.map(f=>({path:f.path,sha256:interfaceHash(f.text)}))};
  assert.doesNotThrow(()=>verifyInterfaceBaseline(files,baseline));
  assert.throws(()=>verifyInterfaceBaseline([{...files[0],text:'pub fn changed() -> Unit\n'}],baseline),/mismatch/);
  assert.throws(()=>verifyInterfaceBaseline([...files,{path:'new.mbti',text:''}],baseline),/file set/);
  assert.throws(()=>verifyInterfaceBaseline(files,{...baseline,files:[...baseline.files,...baseline.files]}),/file set/);
});
