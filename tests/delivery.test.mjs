import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
const cli = fileURLToPath(new URL('../bin/moonportcheck.mjs', import.meta.url));
const snapshot = (paths, extra={}) => ({format:'moonportcheck-snapshot',version:1,profile:'portable-windows-v1',complete:true,scope:[],entries:paths.map(p=>typeof p==='string'?{path:p,kind:'file'}:p).sort((a,b)=>a.path<b.path?-1:a.path>b.path?1:0),scan_issues:[],...extra});
const spec = (paths,mappings,sources=[]) => ({format:'moonportcheck-delivery-spec',version:1,target:{id:'target',snapshot:snapshot(paths)},sources,mappings});
const move = (from,to) => ({mode:'move',source:'target',from,to});
const copy = (source,from,to) => ({mode:'copy',source,from,to});
function run(...args){const r=spawnSync(process.execPath,[cli,...args],{encoding:'utf8',maxBuffer:16*1024*1024});assert.equal(r.error,undefined);assert.equal(r.stderr,'');return r;}
async function files(doc){const dir=await fs.mkdtemp(path.join(os.tmpdir(),'moonport-delivery-'));const input=path.join(dir,'spec.json');const output=path.join(dir,'plan.json');await fs.writeFile(input,JSON.stringify(doc));return {dir,input,output};}
async function planAndAudit(doc){const f=await files(doc);const generated=run('plan',f.input,'--format','json');assert.equal(generated.status,0,generated.stdout);const plan=JSON.parse(generated.stdout);assert.equal(plan.status,'ready');await fs.writeFile(f.output,generated.stdout);const audited=run('audit-plan',f.input,f.output,'--format','json');assert.equal(audited.status,0,audited.stdout);const audit=JSON.parse(audited.stdout);assert.equal(audit.valid,true);return {...f,plan,audit};}
const identityAt=(audit,p)=>audit.final_entries.find(e=>e.path===p)?.origin;

test('delivery swap keeps equal path sets but swaps origins and avoids occupied temporary names',async()=>{
  const doc=spec(['a','b','.moonportcheck-stage-0'],[move('a','b'),move('b','a')]);
  const r=await planAndAudit(doc);
  assert.deepEqual(identityAt(r.audit,'a'),{root:'target',path:'b'});
  assert.deepEqual(identityAt(r.audit,'b'),{root:'target',path:'a'});
  assert.deepEqual(identityAt(r.audit,'.moonportcheck-stage-0'),{root:'target',path:'.moonportcheck-stage-0'});
  assert.ok(r.plan.temporary_paths.length>0);
  assert.ok(r.plan.temporary_paths.every(p=>p!=='.moonportcheck-stage-0'));
  const broken={...r.plan,operations:r.plan.operations.slice(1)};
  await fs.writeFile(r.output,JSON.stringify(broken));
  assert.equal(run('audit-plan',r.input,r.output,'--format','json').status,1);
});
test('delivery reads the initial source identity across Copy and Move dependencies',async()=>{
  const r=await planAndAudit(spec(['a','b'],[move('a','b'),move('b','c'),copy('target','b','archive/y')]));
  assert.deepEqual(identityAt(r.audit,'b'),{root:'target',path:'a'});
  assert.deepEqual(identityAt(r.audit,'c'),{root:'target',path:'b'});
  assert.deepEqual(identityAt(r.audit,'archive/y'),{root:'target',path:'b'});
  const broken=structuredClone(r.plan);
  const idx=broken.operations.findIndex(o=>o.kind==='copy');
  broken.operations[idx].origin={root:'target',path:'a'};
  await fs.writeFile(r.output,JSON.stringify(broken));
  assert.equal(run('audit-plan',r.input,r.output,'--format','json').status,1);
});
test('delivery vacates a file before making a same-name directory and distinguishes source roots',async()=>{
  const sources=[{id:'one',snapshot:snapshot(['x'])},{id:'two',snapshot:snapshot(['x'])}];
  const mappings=[move('report','old/report'),copy('one','x','report/a'),copy('two','x','report/b')];
  const r=await planAndAudit(spec(['report'],mappings,sources));
  assert.deepEqual(identityAt(r.audit,'old/report'),{root:'target',path:'report'});
  assert.deepEqual(identityAt(r.audit,'report/a'),{root:'one',path:'x'});
  assert.deepEqual(identityAt(r.audit,'report/b'),{root:'two',path:'x'});
  const f=await files(spec(['report'],mappings.slice(1),sources));
  assert.equal(run('plan',f.input,'--format','json').status,1);
});
test('delivery handles mkdir cycles, case-only moves, directory copies and initial-state-only expansion',async()=>{
  await planAndAudit(spec(['a','p'],[move('a','p/x'),move('p','a')]));
  const upper=await planAndAudit(spec(['a.txt'],[move('a.txt','A.txt')]));
  assert.deepEqual(identityAt(upper.audit,'A.txt'),{root:'target',path:'a.txt'});
  assert.ok(upper.plan.temporary_paths.length>0);
  const r=await planAndAudit(spec(['src/x',{path:'empty',kind:'directory'}],[copy('target','src','src/backup'),copy('target','empty','empty-copy')]));
  assert.deepEqual(identityAt(r.audit,'src/backup/x'),{root:'target',path:'src/x'});
  assert.equal(r.audit.final_entries.filter(e=>e.kind==='file').length,2);
  assert.ok(r.audit.final_entries.some(e=>e.path==='empty-copy'&&e.kind==='directory'));
});
test('delivery snapshot refs resolve beside spec; inputs remain unchanged; formats and exit classes work',async()=>{
  const doc=spec(['a'],[copy('target','a','out/a')]);
  const f=await files(doc);const snapFile=path.join(f.dir,'initial.json');
  await fs.writeFile(snapFile,JSON.stringify(doc.target.snapshot));doc.target.snapshot='initial.json';await fs.writeFile(f.input,JSON.stringify(doc));
  const before=[await fs.readFile(f.input,'utf8'),await fs.readFile(snapFile,'utf8')];
  for(const format of ['json','text','markdown'])assert.equal(run('plan',f.input,'--format',format).status,0);
  assert.deepEqual([await fs.readFile(f.input,'utf8'),await fs.readFile(snapFile,'utf8')],before);
  const bad=await files(spec(['a'],[move('a','b'),move('a','c')]));assert.equal(run('plan',bad.input,'--format','json').status,1);
  const incomplete=spec([],[]);incomplete.target.snapshot.complete=false;
  const partial=await files(incomplete);assert.equal(run('plan',partial.input,'--format','json').status,3);
  const invalid=await files({...spec([],[]),unknown:true});assert.equal(run('plan',invalid.input,'--format','json').status,2);
  assert.equal(run('plan',f.input,'--format','sarif').status,2);
  assert.equal(run('plan',f.input,'--exclude','*').status,2);
});
test('delivery source names use exact matching and target copies cannot silently conflate identities',async()=>{
  const sources=[{id:'linux',snapshot:snapshot(['A','a','CON.txt'])}];
  const r=await planAndAudit(spec([],[copy('linux','A','one'),copy('linux','a','two'),copy('linux','CON.txt','safe')],sources));
  assert.deepEqual(identityAt(r.audit,'one'),{root:'linux',path:'A'});assert.deepEqual(identityAt(r.audit,'two'),{root:'linux',path:'a'});
  assert.deepEqual(identityAt(r.audit,'safe'),{root:'linux',path:'CON.txt'});
});

test('delivery cannot silently reinterpret an unsupported target snapshot profile',async()=>{
  const doc=spec([],[]);doc.target.snapshot.profile='other-profile';
  const f=await files(doc);const generated=run('plan',f.input,'--format','json');
  assert.equal(generated.status,1,generated.stdout);
  const plan={...JSON.parse(generated.stdout),status:'ready',diagnostics:[]};
  await fs.writeFile(f.output,JSON.stringify(plan));
  const audited=run('audit-plan',f.input,f.output,'--format','json');
  assert.equal(audited.status,1,audited.stdout);
});
