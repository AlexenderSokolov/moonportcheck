// Test fixtures only: never export an executor for user-supplied destination roots.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {expectedLayout, replayPlan} from './delivery-reference.mjs';

const root=fileURLToPath(new URL('../',import.meta.url));
function invoke(args,expected=0){
  const r=spawnSync(process.execPath,[path.join(root,'bin/moonportcheck.mjs'),...args],{encoding:'utf8',maxBuffer:32*1024*1024});
  assert.ifError(r.error);assert.equal(r.status,expected,`${args.join(' ')}\n${r.stdout}\n${r.stderr}`);return JSON.parse(r.stdout);
}
function safe(directory,relative){
  assert.ok(relative && !relative.includes('\\') && !path.isAbsolute(relative));
  assert.ok(relative.split('/').every(p=>p && p!=='.' && p!=='..'));
  const result=path.resolve(directory,...relative.split('/'));
  assert.ok(result.startsWith(path.resolve(directory)+path.sep));return result;
}
function inventory(directory,prefix=''){
  const entries=[];
  for(const child of fs.readdirSync(directory,{withFileTypes:true}).sort((a,b)=>a.name<b.name?-1:1)){
    const name=prefix?`${prefix}/${child.name}`:child.name,full=path.join(directory,child.name);
    assert.ok(!child.isSymbolicLink(),'Fixtures must contain only regular files/directories');
    if(child.isDirectory()){entries.push({path:name,kind:'directory'});entries.push(...inventory(full,name));}
    else {assert.ok(child.isFile());entries.push({path:name,kind:'file',bytes:fs.readFileSync(full)});}
  }
  return entries.sort((a,b)=>a.path<b.path?-1:a.path>b.path?1:0);
}
function populate(destination,fixture){
  if(typeof fixture==='string'){
    for(const entry of inventory(fixture)){
      const full=safe(destination,entry.path);
      if(entry.kind==='directory')fs.mkdirSync(full,{recursive:true});
      else {fs.mkdirSync(path.dirname(full),{recursive:true});fs.writeFileSync(full,entry.bytes,{flag:'wx'});}
    }
  }else{
    for(const dir of fixture?.directories??[])fs.mkdirSync(safe(destination,dir),{recursive:true});
    for(const [name,bytes] of Object.entries(fixture?.files??{})){
      const full=safe(destination,name);fs.mkdirSync(path.dirname(full),{recursive:true});fs.writeFileSync(full,bytes,{flag:'wx'});
    }
  }
}
export function assertFilesystemLayout(directory,expected,initial){
  const actual=inventory(directory);
  assert.deepEqual(actual.map(({path,kind})=>({path,kind})),expected.map(({path,kind})=>({path,kind})), 'Actual file/directory set differs');
  for(const entry of expected.filter(e=>e.kind==='file')){
    const bytes=initial.get(entry.origin.root)?.find(e=>e.path===entry.origin.path)?.bytes;
    assert.ok(bytes,`Missing initial bytes for ${JSON.stringify(entry.origin)}`);
    assert.deepEqual(fs.readFileSync(safe(directory,entry.path)),bytes,`Wrong initial content at ${entry.path}`);
  }
}

// Every mutable root is freshly minted here. Existing fixture paths are read
// and copied; all Move operations apply exclusively to these new copies.
export function runFilesystemCase({name,target={},sources={},mappings,expectedBlocked=false}){
  const artifacts=path.join(root,'artifacts');fs.mkdirSync(artifacts,{recursive:true});
  const work=fs.mkdtempSync(path.join(artifacts,`delivery-fs-${name}-`));
  const roots=new Map();
  for(const [id,fixture] of [['target',target],...Object.entries(sources)]){
    assert.match(id,/^[a-zA-Z0-9_-]+$/);assert.ok(!roots.has(id));
    const directory=path.join(work,id);fs.mkdirSync(directory);populate(directory,fixture);roots.set(id,directory);
  }
  const initial=new Map([...roots].map(([id,dir])=>[id,inventory(dir)]));
  const tree=id=>({id,snapshot:invoke(['snapshot',roots.get(id)])});
  const spec={format:'moonportcheck-delivery-spec',version:1,sources:Object.keys(sources).map(tree),target:tree('target'),mappings};
  const specFile=path.join(work,'spec.json'),planFile=path.join(work,'plan.json');fs.writeFileSync(specFile,JSON.stringify(spec,null,2));
  const plan=invoke(['plan',specFile,'--format','json'],expectedBlocked?1:0);fs.writeFileSync(planFile,JSON.stringify(plan,null,2));
  if(expectedBlocked){
    for(const [id,dir] of roots)assert.deepEqual(inventory(dir),initial.get(id));
    const result={name,work,blocked:true,inputs_unchanged:true};fs.writeFileSync(path.join(work,'evidence.json'),JSON.stringify(result,null,2));return result;
  }
  const audit=invoke(['audit-plan',specFile,planFile,'--format','json']);assert.equal(audit.valid,true);
  fs.writeFileSync(path.join(work,'audit.json'),JSON.stringify(audit,null,2));
  const expected=expectedLayout(spec);assert.deepEqual(replayPlan(spec,plan),expected);
  const targetDir=roots.get('target'),trace=[];
  for(const [step,op] of plan.operations.entries()){
    const to=safe(targetDir,op.to),parent=fs.lstatSync(path.dirname(to));assert.ok(parent.isDirectory()&&!parent.isSymbolicLink());
    assert.ok(!fs.existsSync(to),`Occupied target at step ${step}`);
    if(op.kind==='mkdir')fs.mkdirSync(to);
    else {
      assert.ok(roots.has(op.source));const from=safe(roots.get(op.source),op.from);
      const source=fs.lstatSync(from);assert.ok(source.isFile()&&!source.isSymbolicLink());
      const originBytes=initial.get(op.origin.root)?.find(e=>e.path===op.origin.path)?.bytes;
      assert.deepEqual(fs.readFileSync(from),originBytes,`Physical source identity at step ${step}`);
      if(op.kind==='copy')fs.copyFileSync(from,to,fs.constants.COPYFILE_EXCL);
      else {assert.equal(op.kind,'move');assert.equal(op.source,'target');fs.renameSync(from,to);}
    }
    trace.push({step,operation:op,state:inventory(targetDir).map(({path,kind})=>({path,kind}))});
  }
  assertFilesystemLayout(targetDir,expected,initial);
  for(const [id,dir] of roots)if(id!=='target')assert.deepEqual(inventory(dir),initial.get(id),'Readonly source changed');
  const expectedFiles=expected.filter(e=>e.kind==='file').length;
  const result={name,work,blocked:false,operations:plan.operations.length,files:expectedFiles,bytes_compared:expected.reduce((sum,e)=>sum+(e.kind==='file'?initial.get(e.origin.root).find(f=>f.path===e.origin.path).bytes.length:0),0),readonly_sources_unchanged:true,temporary_files_remaining:0};
  fs.writeFileSync(path.join(work,'expected-layout.json'),JSON.stringify(expected,null,2));
  fs.writeFileSync(path.join(work,'physical-trace.json'),JSON.stringify(trace,null,2));
  fs.writeFileSync(path.join(work,'evidence.json'),JSON.stringify(result,null,2));return result;
}

if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){
  const move=(from,to)=>({mode:'move',source:'target',from,to});
  const copy=(source,from,to)=>({mode:'copy',source,from,to});
  const cases=[
    {name:'swap',target:{files:{a:'X',b:'Y','.moonportcheck-stage-0':'Z',keep:'unrelated'}},mappings:[move('a','b'),move('b','a')]},
    {name:'read-before-move',target:{files:{a:'X',b:'Y'}},mappings:[move('a','b'),move('b','c'),copy('target','b','archive/y')]},
    {name:'vacate-directory',target:{files:{report:'R'}},sources:{one:{files:{x:'ONE'}},two:{files:{x:'TWO'}}},mappings:[move('report','old/report'),copy('one','x','report/a'),copy('two','x','report/b')]},
    {name:'vacate-blocked',target:{files:{report:'R'}},sources:{one:{files:{x:'ONE'}}},mappings:[copy('one','x','report/a')],expectedBlocked:true},
    {name:'mkdir-cycle',target:{files:{a:'A',p:'P'}},mappings:[move('a','p/x'),move('p','a')]},
    {name:'case-rename',target:{files:{a:'A'}},mappings:[move('a','A')]},
    {name:'initial-prefix',target:{files:{'tree/x':'X'},directories:['tree/empty']},mappings:[copy('target','tree','tree/nested')]},
    {name:'multiple-copy',target:{files:{a:'X'}},mappings:[copy('target','a','one'),copy('target','a','two'),move('a','three')]},
  ];
  if(process.platform==='linux')cases.push({name:'linux-exact-source',sources:{linux:{files:{A:'UPPER',a:'lower'}}},mappings:[copy('linux','A','upper'),copy('linux','a','lower')]});
  const result={cases:cases.map(runFilesystemCase),skipped:process.platform==='linux'?[]:[{name:'linux-exact-source',reason:'Requires case-sensitive Linux filesystem; abstract model runs on both platforms.'}],scope:'Only newly created fixture roots are mutated; no public executor.'};
  fs.writeFileSync(path.join(root,'artifacts/delivery-fs-latest.json'),JSON.stringify(result,null,2));console.log(JSON.stringify(result,null,2));
}
