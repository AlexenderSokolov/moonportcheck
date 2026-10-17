import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {parseZipEntries} from './zip-util.mjs';
import {createHash} from 'node:crypto';
import {runFilesystemCase} from './delivery-fs.mjs';
const root=fileURLToPath(new URL('../',import.meta.url));
const cli=path.join(root,'bin/moonportcheck.mjs');
const out=fs.mkdtempSync(path.join(root,'artifacts','delivery-cases-'));
function invoke(args,expected=0){const r=spawnSync(process.execPath,[cli,...args],{cwd:root,encoding:'utf8',maxBuffer:32*1024*1024});assert.equal(r.error,undefined);assert.equal(r.status,expected,`${args.join(' ')}\n${r.stdout}\n${r.stderr}`);return r.stdout;}
const snap=paths=>({format:'moonportcheck-snapshot',version:1,profile:'portable-windows-v1',complete:true,scope:[],entries:paths.map(p=>({path:p,kind:'file'})).sort((a,b)=>a.path<b.path?-1:a.path>b.path?1:0),scan_issues:[]});
const move=(from,to)=>({mode:'move',source:'target',from,to});const copy=(source,from,to)=>({mode:'copy',source,from,to});
const make=(paths,mappings,sources=[])=>({format:'moonportcheck-delivery-spec',version:1,target:{id:'target',snapshot:snap(paths)},sources,mappings});
const cases=[
 ['swap',make(['a','b','.moonportcheck-stage-0'],[move('a','b'),move('b','a')])],
 ['read-before-move',make(['a','b'],[move('a','b'),move('b','c'),copy('target','b','archive/y')])],
 ['vacate-before-directory',make(['report'],[move('report','old/report'),copy('one','x','report/a'),copy('two','x','report/b')],[{id:'one',snapshot:snap(['x'])},{id:'two',snapshot:snap(['x'])}])],
];
const records=[];
for(const [name,doc] of cases){
  const folder=path.join(out,name);fs.mkdirSync(folder);const specFile=path.join(folder,'spec.json');const planFile=path.join(folder,'plan.json');
  fs.writeFileSync(specFile,JSON.stringify(doc,null,2)+'\n');const planned=invoke(['plan',specFile,'--format','json']);fs.writeFileSync(planFile,planned);
  const audit=invoke(['audit-plan',specFile,planFile,'--format','json']);fs.writeFileSync(path.join(folder,'audit.json'),audit);
  fs.writeFileSync(path.join(folder,'report.md'),invoke(['audit-plan',specFile,planFile,'--format','markdown']));
  const broken=JSON.parse(planned);broken.operations=broken.operations.slice(1);const bad=path.join(folder,'broken-plan.json');fs.writeFileSync(bad,JSON.stringify(broken,null,2));
  fs.writeFileSync(path.join(folder,'broken-audit.json'),invoke(['audit-plan',specFile,bad,'--format','json'],1));
  records.push({name,kind:'synthetic semantic counterexample',plan_exit:0,audit_exit:0,broken_exit:1,operations:JSON.parse(planned).operations.length});
}

// Real inputs are exactly the already-published source tag and CLI ZIP, never
// the evolving working tree. These fixtures are extracted only into artifacts.
const source=path.join(out,'public-source'),runtime=path.join(out,'public-cli');fs.mkdirSync(source);fs.mkdirSync(runtime);
const tar=path.join(out,'v020-source.tar');
let child=spawnSync('git',['archive','--format=tar',`--output=${tar}`,'b7cda70b8da20dab525cba7317d54881e53e4262'],{cwd:root,encoding:'utf8'});assert.equal(child.status,0,child.stderr);
child=spawnSync('tar',['-xf',tar,'-C',source],{encoding:'utf8'});assert.equal(child.status,0,child.stderr);
const archive=path.join(root,'artifacts/release/windows/moonportcheck-0.2.0-win32-b7cda70.zip');
if(!fs.existsSync(archive)){
  const response=await fetch('https://github.com/AlexenderSokolov/moonportcheck/releases/download/v0.2.0/moonportcheck-0.2.0-win32-b7cda70.zip',{signal:AbortSignal.timeout(30000)});
  if(!response.ok)throw new Error(`Cannot retrieve pinned public CLI fixture: HTTP ${response.status}`);
  fs.mkdirSync(path.dirname(archive),{recursive:true});fs.writeFileSync(archive,Buffer.from(await response.arrayBuffer()));
}
const archiveSha=createHash('sha256').update(fs.readFileSync(archive)).digest('hex');
assert.equal(archiveSha,'a48feee19bf481d72de1ed691c5ab83294f98c07c7feb5a08a35f96d5af361d7','Published fixture digest differs; never substitute a new local build.');
for(const [name,{data}] of parseZipEntries(fs.readFileSync(archive))){assert.ok(!name.startsWith('/')&&!name.split('/').includes('..')&&!name.includes('\\'));const dest=path.join(runtime,...name.split('/'));fs.mkdirSync(path.dirname(dest),{recursive:true});fs.writeFileSync(dest,data);}
const sourceSnap=JSON.parse(invoke(['snapshot',source]));const runtimeSnap=JSON.parse(invoke(['snapshot',runtime]));
const real=make([],[copy('source','',''),copy('cli','','')],[{id:'source',snapshot:sourceSnap},{id:'cli',snapshot:runtimeSnap}]);
const folder=path.join(out,'real-source-and-cli');fs.mkdirSync(folder);const input=path.join(folder,'spec.json');const output=path.join(folder,'plan.json');
fs.writeFileSync(input,JSON.stringify(real,null,2));fs.writeFileSync(path.join(folder,'flat-blocked.json'),invoke(['plan',input,'--format','json'],1));
real.mappings=[copy('source','','source'),copy('cli','','cli')];fs.writeFileSync(input,JSON.stringify(real,null,2));fs.writeFileSync(output,invoke(['plan',input,'--format','json']));
fs.writeFileSync(path.join(folder,'audit.json'),invoke(['audit-plan',input,output,'--format','json']));
fs.writeFileSync(path.join(folder,'report.md'),invoke(['audit-plan',input,output,'--format','markdown']));
records.push({name:'real-source-and-cli',kind:'actual published inputs',source_tag:'v0.2.0',source_sha:'b7cda70b8da20dab525cba7317d54881e53e4262',cli_asset:path.basename(archive),cli_sha256:archiveSha,source_entries:sourceSnap.entries.length,cli_entries:runtimeSnap.entries.length,flat_exit:1,prefixed_plan_exit:0,audit_exit:0});
const physical=runFilesystemCase({name:'published-source-and-cli',sources:{source,cli:runtime},target:{files:{'unrelated.txt':'Preserve this existing target'}},mappings:real.mappings});
const evidence={output:out,cases:records,physical,inputs_modified:false,scope:'Published fixtures remain readonly. Mkdir/Copy/Move are exercised only in freshly created test roots under artifacts; no public executor.'};
fs.writeFileSync(path.join(out,'evidence.json'),JSON.stringify(evidence,null,2)+'\n');fs.writeFileSync(path.join(root,'artifacts/delivery-cases-latest.json'),JSON.stringify(evidence,null,2)+'\n');console.log(JSON.stringify(evidence,null,2));
