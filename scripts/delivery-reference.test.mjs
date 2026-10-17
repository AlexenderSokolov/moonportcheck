import test from 'node:test';
import assert from 'node:assert/strict';
import {expectedLayout,replayPlan} from './delivery-reference.mjs';

const snapshot=entries=>({format:'moonportcheck-snapshot',version:1,profile:'portable-windows-v1',complete:true,scope:[],scan_issues:[],entries:entries.map(e=>typeof e==='string'?{path:e,kind:'file'}:e)});
const spec=(entries,mappings,sources=[])=>({format:'moonportcheck-delivery-spec',version:1,target:{id:'target',snapshot:snapshot(entries)},sources,mappings});
const origin=(path,root='target')=>({root,path});
const map=(mode,from,to,source='target')=>({mode,source,from,to});
const op=(kind,from,to,original=from,source='target')=>({kind,source,from,to,origin:origin(original,source)});
const mkdir=to=>({kind:'mkdir',source:'',from:'',to,origin:origin('','')});
const plan=(doc,operations,temporary_paths=[])=>({status:'ready',basis:JSON.stringify(doc),operations,temporary_paths,diagnostics:[]});
const rejects=(doc,p,code,step=-1)=>assert.throws(()=>replayPlan(doc,p),e=>e.code===code&&e.step===step);

test('reference swaps identities, preserves unrelated file and accepts alternate staging',()=>{
  const doc=spec(['a','b','.moonportcheck-stage-0'],[map('move','a','b'),map('move','b','a')]);
  const p=plan(doc,[op('move','b','scratch'),op('move','a','b'),op('move','scratch','a','b')],['scratch']);
  assert.deepEqual(replayPlan(doc,p),expectedLayout(doc));
  assert.deepEqual(expectedLayout(doc).filter(e=>e.path==='a'||e.path==='b').map(e=>e.origin.path),['b','a']);
  rejects(doc,{...p,temporary_paths:['.moonportcheck-stage-0']},'TEMPORARY_CONFLICT');
  rejects(doc,plan(doc,[op('move','a','b')]),'DESTINATION_OCCUPIED',0);
  rejects(doc,{...p,operations:p.operations.slice(0,-1)},'TEMPORARY_LEFTOVER');
});

test('reference rejects a path-legal read after provenance changed',()=>{
  const doc=spec(['a','b'],[map('move','a','b'),map('move','b','c'),map('copy','b','archive/y')]);
  const operations=[mkdir('archive'),op('move','b','c'),op('move','a','b'),op('copy','c','archive/y','b')];
  assert.deepEqual(replayPlan(doc,plan(doc,operations)),expectedLayout(doc));
  const bad=structuredClone(operations);bad[3].from='b';
  rejects(doc,plan(doc,bad),'SOURCE_IDENTITY',3);
  bad[3].origin=origin('a');
  rejects(doc,plan(doc,bad),'UNRELATED_COPY',3);
  rejects(doc,plan(doc,operations.slice(0,-1)),'FINAL_LAYOUT');
});

test('reference handles vacating file parent and mkdir dependency cycle',()=>{
  const doc=spec(['a','p'],[map('move','a','p/x'),map('move','p','a')]);
  const operations=[op('move','a','scratch'),op('move','p','a'),mkdir('p'),op('move','scratch','p/x','a')];
  assert.deepEqual(replayPlan(doc,plan(doc,operations,['scratch'])),expectedLayout(doc));
  rejects(doc,plan(doc,[mkdir('p')]),'DESTINATION_OCCUPIED',0);
});

test('directory expansion preserves empties and is strictly initial-only',()=>{
  const doc=spec([{path:'tree/empty',kind:'directory'},'tree/a'],[map('copy','tree','tree/child')]);
  const expected=expectedLayout(doc);
  assert(expected.some(e=>e.path==='tree/child/empty'&&e.kind==='directory'));
  assert(!expected.some(e=>e.path.includes('child/child')));
  const operations=[mkdir('tree/child'),mkdir('tree/child/empty'),op('copy','tree/a','tree/child/a')];
  assert.deepEqual(replayPlan(doc,plan(doc,operations)),expected);
  rejects(doc,plan(doc,[...operations,mkdir('unrelated')]),'UNRELATED_MKDIR',3);
});

test('multi-root exact sources and repeated copies preserve independent origins',()=>{
  const doc=spec(['unrelated'],[map('copy','A','first','linux'),map('copy','a','second','linux'),map('copy','A','third','linux'),map('copy','A','fourth','other')],[{id:'linux',snapshot:snapshot(['A','a'])},{id:'other',snapshot:snapshot(['A'])}]);
  const p=plan(doc,[op('copy','A','fourth','A','other'),op('copy','A','third','A','linux'),op('copy','a','second','a','linux'),op('copy','A','first','A','linux')]);
  assert.deepEqual(replayPlan(doc,p),expectedLayout(doc));
  const changed=structuredClone(p);changed.operations[0].origin.root='linux';
  rejects(doc,changed,'SOURCE_IDENTITY',0);
});

test('case-only rename requires intermediate vacant slot',()=>{
  const doc=spec(['Readme'],[map('move','Readme','README')]);
  assert.deepEqual(replayPlan(doc,plan(doc,[op('move','Readme','scratch'),op('move','scratch','README','Readme')],['scratch'])),expectedLayout(doc));
  rejects(doc,plan(doc,[op('move','Readme','README')]),'DESTINATION_OCCUPIED',0);
});

test('unrelated identity cannot be moved away and restored despite matching final layout',()=>{
  const doc=spec(['a','unrelated'],[map('copy','a','b')]);
  const p=plan(doc,[op('copy','a','b'),op('move','unrelated','scratch'),op('move','scratch','unrelated','unrelated')],['scratch']);
  rejects(doc,p,'UNRELATED_MOVE',1);
});

test('reference rejects stale basis, duplicate Move and conflicting Copy destinations',()=>{
  const doc=spec(['a'],[map('copy','a','b')]);
  const p=plan(doc,[op('copy','a','b')]);
  p.basis=JSON.stringify({...doc,mappings:[]});
  rejects(doc,p,'BASIS');
  assert.throws(()=>expectedLayout(spec(['a'],[map('move','a','b'),map('move','a','c')])),e=>e.code==='MOVE');
  assert.throws(()=>expectedLayout(spec(['a'],[map('copy','a','b'),map('copy','a','B')])),e=>e.code==='MAPPING_COLLISION');
});
