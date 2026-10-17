import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {performance} from 'node:perf_hooks';
import {run_request} from '../dist/bridge.js';
import {expectedLayout,replayPlan} from './delivery-reference.mjs';
const snapshot=paths=>({format:'moonportcheck-snapshot',version:1,profile:'portable-windows-v1',complete:true,scope:[],entries:paths.map(p=>({path:p,kind:'file'})).sort((a,b)=>a.path<b.path?-1:a.path>b.path?1:0),scan_issues:[]});
const spec=(paths,mappings,sources=[])=>({format:'moonportcheck-delivery-spec',version:1,target:{id:'target',snapshot:snapshot(paths)},sources,mappings});
const move=(from,to)=>({mode:'move',source:'target',from,to});
const run=(mode,doc,plan)=>{const result=JSON.parse(run_request(JSON.stringify({mode,format:'json',spec_text:JSON.stringify(doc),...(plan?{plan_text:JSON.stringify(plan)}:{})})));return {...result,document:JSON.parse(result.output)};};

// A separate finite transition system: positions[token] -> slot. It knows no
// production scheduler, graph, canonical basis, or audit implementation.
function referenceFeasible(n,goals){
  const expected=Array.from({length:n},(_,i)=>goals[i]??i);
  if(new Set(expected).size!==n)return false;
  const first=Array.from({length:n},(_,i)=>i);
  const todo=[first],seen=new Set([first.join(',')]);
  for(let head=0;head<todo.length;head++){
    const state=todo[head];
    if(state.every((slot,i)=>slot===expected[i]))return true;
    for(let token=0;token<n;token++){
      if(goals[token]===undefined)continue;
      for(const to of [goals[token],n+1]){
        if(state.includes(to))continue;
        const next=state.slice();next[token]=to;const key=next.join(',');
        if(!seen.has(key)){seen.add(key);todo.push(next);}
      }
    }
  }
  return false;
}
let enumerated=0,feasible=0,blocked=0;
for(let n=1;n<=4;n++){
  const names=Array.from({length:n+1},(_,i)=>String.fromCharCode(97+i));
  function visit(i,goals,used){
    if(i<n){
      visit(i+1,goals,used);
      for(let to=0;to<=n;to++)if(!used.has(to)){goals[i]=to;used.add(to);visit(i+1,goals,used);used.delete(to);delete goals[i];}
      return;
    }
    const mappings=Object.keys(goals).map(k=>move(names[Number(k)],names[goals[k]]));
    const doc=spec(names.slice(0,n),mappings);
    const expected=referenceFeasible(n,goals);
    const generated=run('plan',doc);
    assert.equal(generated.exit_code,expected?0:1,`reference mismatch ${JSON.stringify(doc)}: ${generated.output}`);
    if(expected){
      assert.deepEqual(replayPlan(doc,generated.document),expectedLayout(doc),'independent replay disagrees with declarative expected layout');
      const audited=run('audit-plan',doc,generated.document);
      assert.equal(audited.exit_code,0,audited.output);
      for(let token=0;token<n;token++){
        const goal=names[goals[token]??token];
        assert.deepEqual(audited.document.final_entries.find(e=>e.path===goal)?.origin,{root:'target',path:names[token]});
      }
      const permuted={...doc,mappings:doc.mappings.toReversed()};
      assert.equal(run('plan',permuted).output,generated.output,'mapping permutation changed canonical plan');
      feasible++;
    }else blocked++;
    enumerated++;
  }
  visit(0,{},new Set());
}

// A second oracle allows duplicated provenance after Copy. Slots contain
// origins, rather than one position per origin; this independently exercises
// reading the initial origin before/after relocation and temporary staging.
function mixedFeasible(n,goals,copyFrom){
  const width=n+3,copySlot=n+1,tempSlot=n+2;
  const first=Array.from({length:width},(_,i)=>i<n?i:-1),expected=first.slice();
  for(const key of Object.keys(goals))expected[Number(key)]=-1;
  for(const key of Object.keys(goals)){
    const token=Number(key),to=goals[key];if(expected[to]!==-1)return false;expected[to]=token;
  }
  expected[copySlot]=copyFrom;
  const queue=[first],seen=new Set([first.join(',')]);
  for(let head=0;head<queue.length;head++){
    const state=queue[head];if(state.every((t,i)=>t===expected[i]))return true;
    function enqueue(next){const key=next.join(',');if(!seen.has(key)){seen.add(key);queue.push(next);}}
    if(state[copySlot]===-1&&state.includes(copyFrom)){const next=state.slice();next[copySlot]=copyFrom;enqueue(next);}
    for(const key of Object.keys(goals)){
      const token=Number(key);
      for(let from=0;from<width;from++)if(state[from]===token)for(const to of [goals[key],tempSlot])if(state[to]===-1){const next=state.slice();next[from]=-1;next[to]=token;enqueue(next);}
    }
  }
  return false;
}
let mixedEnumerated=0,mixedAccepted=0;
for(let n=1;n<=3;n++){
  const names=Array.from({length:n+1},(_,i)=>String.fromCharCode(97+i));
  function visit(i,goals,used){
    if(i<n){visit(i+1,goals,used);for(let to=0;to<=n;to++)if(!used.has(to)){goals[i]=to;used.add(to);visit(i+1,goals,used);used.delete(to);delete goals[i];}return;}
    for(let copyFrom=0;copyFrom<n;copyFrom++){
      const mappings=[...Object.keys(goals).map(k=>move(names[Number(k)],names[goals[k]])),{mode:'copy',source:'target',from:names[copyFrom],to:'copy-out'}];
      const doc=spec(names.slice(0,n),mappings),expected=mixedFeasible(n,goals,copyFrom),generated=run('plan',doc);
      assert.equal(generated.exit_code,expected?0:1,`mixed reference mismatch ${JSON.stringify(doc)}: ${generated.output}`);
      if(expected){assert.deepEqual(replayPlan(doc,generated.document),expectedLayout(doc),'mixed independent replay mismatch');const audit=run('audit-plan',doc,generated.document);assert.equal(audit.exit_code,0,audit.output);assert.deepEqual(audit.document.final_entries.find(e=>e.path==='copy-out')?.origin,{root:'target',path:names[copyFrom]});mixedAccepted++;}
      mixedEnumerated++;
    }
  }
  visit(0,{},new Set());
}

// Crossed features deliberately outside the flat BFS domain. Expected layouts
// and actual operation replay use the separate test model, not audit output.
const tree=(id,entries)=>({id,snapshot:{...snapshot([]),entries:entries.map(e=>typeof e==='string'?{path:e,kind:'file'}:e).sort((a,b)=>a.path<b.path?-1:a.path>b.path?1:0)}});
const copy=(from,to,source='target')=>({mode:'copy',source,from,to});
const targeted=[
  ['mkdir-cycle',spec(['a','p'],[move('a','p/x'),move('p','a')])],
  ['empty-directory-prefix',spec([],[copy('tree','out','src')],[tree('src',[{path:'tree/empty',kind:'directory'},'tree/a'])])],
  ['initial-only-self-prefix',{...spec([],[copy('tree','tree/child')]),target:tree('target',[{path:'tree/empty',kind:'directory'},'tree/a'])}],
  ['exact-case-multiple-roots',spec(['unrelated'],[copy('A','first','linux'),copy('a','second','linux'),copy('A','third','linux'),copy('A','fourth','other')],[tree('linux',['A','a']),tree('other',['A'])])],
  ['case-only-move',spec(['Readme'],[move('Readme','README')])],
  ['read-after-move',spec(['a','b'],[move('a','b'),move('b','c'),copy('b','archive/y')])],
  ['root-copy',spec([],[copy('','','src')],[tree('src',[{path:'empty',kind:'directory'},'nested/a'])])],
];
const targetedEvidence=[];
for(const [name,doc] of targeted){
  const generated=run('plan',doc);assert.equal(generated.exit_code,0,`${name}: ${generated.output}`);
  const entries=replayPlan(doc,generated.document);assert.deepEqual(entries,expectedLayout(doc));
  assert.equal(run('plan',{...doc,mappings:doc.mappings.toReversed()}).output,generated.output,`${name}: permutation changed plan`);
  targetedEvidence.push({name,operations:generated.document.operations.length,final_entries:entries.length});
}
const negativeEvidence=[];
function negative(name,doc,p,code,step=-1){
  assert.throws(()=>replayPlan(doc,p),e=>e.code===code&&e.step===step,`${name}: wrong independent rejection`);
  const audited=run('audit-plan',doc,p);assert.equal(audited.exit_code,1,`${name}: product accepted corrupt plan`);
  assert.equal(audited.document.diagnostics[0]?.code,code==='BASIS'?'BASIS_MISMATCH':code,`${name}: wrong product diagnostic`);
  assert.equal(audited.document.first_failed_step,step,`${name}: wrong product failure step`);
  negativeEvidence.push({name,reference_code:code,reference_step:step,product_code:audited.document.diagnostics[0]?.code,product_step:audited.document.first_failed_step});
}
const readDoc=targeted.find(([name])=>name==='read-after-move')[1];
const readPlan=run('plan',readDoc).document;
// Put the legal-path Copy last, after b has become the initial a identity.
const wrongRead=structuredClone(readPlan),copyOp=wrongRead.operations.find(op=>op.kind==='copy');
wrongRead.operations=wrongRead.operations.filter(op=>op!==copyOp);copyOp.from='b';wrongRead.operations.push(copyOp);
negative('path-legal-wrong-origin',readDoc,wrongRead,'SOURCE_IDENTITY',wrongRead.operations.length-1);
const swapDoc=spec(['a','b','.moonportcheck-stage-0'],[move('a','b'),move('b','a')]),swapPlan=run('plan',swapDoc).document;
negative('occupied-temporary',swapDoc,{...swapPlan,temporary_paths:['.moonportcheck-stage-0']},'TEMPORARY_CONFLICT');
negative('wrong-order',swapDoc,{...swapPlan,operations:[swapPlan.operations[1],swapPlan.operations[0],swapPlan.operations[2]]},'DESTINATION_OCCUPIED',0);
negative('leftover-temporary',swapDoc,{...swapPlan,operations:swapPlan.operations.slice(0,-1)},'TEMPORARY_LEFTOVER');
const omitted=structuredClone(readPlan);omitted.operations=omitted.operations.filter(op=>op.kind!=='copy');
negative('omitted-copy',readDoc,omitted,'FINAL_LAYOUT');
const stale={...readPlan,basis:JSON.stringify({...readDoc,mappings:[]})};negative('stale-basis',readDoc,stale,'BASIS');
const stray={kind:'mkdir',source:'',from:'',to:'unrelated',origin:{root:'',path:''}};
negative('unrelated-mkdir',readDoc,{...readPlan,operations:[...readPlan.operations,stray]},'UNRELATED_MKDIR',readPlan.operations.length);
const preservedDoc=spec(['a','unrelated'],[copy('a','b')]),preservedPlan=run('plan',preservedDoc).document;
const unrelatedMove={kind:'move',source:'target',from:'unrelated',to:'scratch',origin:{root:'target',path:'unrelated'}};
negative('unrelated-identity-move',preservedDoc,{...preservedPlan,temporary_paths:['scratch'],operations:[...preservedPlan.operations,unrelatedMove]},'UNRELATED_MOVE',preservedPlan.operations.length);
// A positive control prevents a reference model that only accepts the exact
// production schedule or its reserved temporary naming scheme.
const alternate=structuredClone(swapPlan),oldTemporary=alternate.temporary_paths[0];
alternate.temporary_paths=['scratch'];
for(const op of alternate.operations){if(op.from===oldTemporary)op.from='scratch';if(op.to===oldTemporary)op.to='scratch';}
assert.deepEqual(replayPlan(swapDoc,alternate),expectedLayout(swapDoc));
assert.equal(run('audit-plan',swapDoc,alternate).exit_code,0,'valid alternative staging was rejected');
const independentCopies=targeted.find(([name])=>name==='exact-case-multiple-roots')[1],differentOrder=run('plan',independentCopies).document;
differentOrder.operations.reverse();
assert.deepEqual(replayPlan(independentCopies,differentOrder),expectedLayout(independentCopies));
assert.equal(run('audit-plan',independentCopies,differentOrder).exit_code,0,'valid alternate copy ordering was rejected');
const blockers=[
  ['duplicate-move',spec(['a'],[move('a','b'),move('a','c')]),'MOVE'],
  ['folded-copy-destinations',spec(['a'],[copy('a','out'),copy('a','OUT')]),'MAPPING_COLLISION'],
  ['parent-file-without-vacating-move',spec(['report'],[copy('x','report/x','src')],[tree('src',['x'])]),'TARGET_COLLISION'],
];
const blockedEvidence=[];
for(const [name,doc,referenceCode] of blockers){
  assert.throws(()=>expectedLayout(doc),e=>e.code===referenceCode,`${name}: unexpected reference projection`);
  const generated=run('plan',doc);assert.equal(generated.exit_code,1,`${name}: product accepted blocked spec`);
  blockedEvidence.push({name,reference_code:referenceCode,product_code:generated.document.diagnostics[0]?.code});
}

const scale=[];
for(const [name,doc] of [
  ['copy-10000',spec([],Array.from({length:10000},(_,i)=>({mode:'copy',source:'source',from:`f${i}`,to:`out/f${i}`})),[{id:'source',snapshot:snapshot(Array.from({length:10000},(_,i)=>`f${i}`))}])],
  ['chain-10000',spec(Array.from({length:10000},(_,i)=>`f${i}`),Array.from({length:10000},(_,i)=>move(`f${i}`,`f${i+1}`)))],
  ['rings-10000',spec(Array.from({length:10000},(_,i)=>`f${i}`),Array.from({length:10000},(_,i)=>move(`f${i}`,`f${Math.floor(i/4)*4+(i+1)%4}`)))],
]){
  const start=performance.now();const planned=run('plan',doc);const planMs=performance.now()-start;
  assert.equal(planned.exit_code,0,planned.output.slice(0,500));
  const second=performance.now();const audited=run('audit-plan',doc,planned.document);const auditMs=performance.now()-second;
  assert.equal(audited.exit_code,0,audited.output.slice(0,500));
  scale.push({name,mappings:10000,operations:planned.document.operations.length,temporary_paths:planned.document.temporary_paths.length,plan_with_audit_ms:planMs,audit_ms:auditMs,rss_bytes:process.memoryUsage().rss,process_peak_rss_bytes:process.resourceUsage().maxRSS*1024,plan_bytes:Buffer.byteLength(planned.output)});
}
const evidence={reference:{enumerated,feasible,blocked,max_files:4,method:'independent breadth-first token-position feasibility plus independent actual-operation replay and declarative final projection',mixed_enumerated:mixedEnumerated,mixed_feasible:mixedAccepted,mixed_method:'separate slot-to-origin BFS permits provenance copies during moves; every accepted actual operation sequence is independently replayed',actual_plans_replayed:feasible+mixedAccepted,targeted:targetedEvidence,negative_controls:negativeEvidence,blocked_controls:blockedEvidence,alternative_temporary_plan_accepted:true,alternative_operation_order_accepted:true,boundary:'BFS is exhaustive only for the documented flat domain. Tree/multiple-root/casing interactions are targeted, not exhaustive. Basis is compared semantically; product codec tests cover canonical JSON.'},scale,note:'Planning/replay measurements exclude disk scanning. Planning CLI includes an independent audit gate; timings are observations, not limits.'};
fs.mkdirSync('artifacts',{recursive:true});fs.writeFileSync('artifacts/delivery-verification.json',JSON.stringify(evidence,null,2)+'\n');
console.log(JSON.stringify(evidence,null,2));
