// A clean local clone, with no previous build or fixture cache. Run separately
// from acceptance to avoid recursive acceptance/reproduction invocations.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {collectSourceSnapshot} from './source-snapshot.mjs';
const root=fileURLToPath(new URL('../',import.meta.url));
function run(command,args,options={}){
  const r=spawnSync(command,args,{cwd:root,encoding:'utf8',maxBuffer:64*1024*1024,...options});
  assert.ifError(r.error);assert.equal(r.status,0,`${command} ${args.join(' ')}\n${r.stdout}\n${r.stderr}`);return r;
}
assert.equal(run('git',['status','--porcelain']).stdout.trim(),'','Commit the intended source first; reproduction never ignores dirty/untracked source.');
const head=run('git',['rev-parse','HEAD']).stdout.trim();
const artifacts=path.join(root,'artifacts');fs.mkdirSync(artifacts,{recursive:true});
const output=fs.mkdtempSync(path.join(artifacts,'reproduction-')),clone=path.join(output,'source');
run('git',['clone','--no-local','--no-hardlinks',root,clone]);
assert.equal(run('git',['rev-parse','HEAD'],{cwd:clone}).stdout.trim(),head);
for(const name of ['artifacts','dist','_build','.toolchains'])assert.ok(!fs.existsSync(path.join(clone,name)),`Clone inherited ${name}`);
const before=await collectSourceSnapshot(clone),original=await collectSourceSnapshot(root);
// Git may translate text line endings on checkout; require the same path set
// and record each platform's byte manifest instead of pretending they match.
assert.deepEqual(before.files.map(f=>f.path),original.files.map(f=>f.path));
const platform=process.platform==='win32'?'windows-x86_64':'linux-x86_64';
const environment={...process.env,MOONPORT_TOOLCHAIN_HOME:path.resolve(root,process.env.MOONPORT_TOOLCHAIN_HOME??path.join('.toolchains',platform))};
delete environment.MOONPORT_API_BASELINE;
const command=process.platform==='win32'?'pwsh':'bash';
const args=process.platform==='win32'?['-NoProfile','-File','run_acceptance.ps1']:['run_acceptance.sh'];
const result=spawnSync(command,args,{cwd:clone,env:environment,encoding:'utf8',maxBuffer:64*1024*1024});
fs.writeFileSync(path.join(output,'acceptance.log'),`${result.stdout??''}${result.stderr??''}`);
assert.ifError(result.error);assert.equal(result.status,0,`Clean acceptance failed. See ${output}/acceptance.log`);
assert.equal(run('git',['status','--porcelain'],{cwd:clone}).stdout.trim(),'','Clean acceptance changed tracked/untracked source');
assert.equal((await collectSourceSnapshot(clone)).sha256,before.sha256,'Source changed during reproduction');
run('git',['archive','--format=tar',`--output=${path.join(output,`moonportcheck-${head.slice(0,7)}-source.tar`)}`,head]);
const records=fs.readdirSync(path.join(clone,'artifacts')).filter(n=>n.startsWith('acceptance-'));
assert.equal(records.length,1);
const evidenceFile=path.join(clone,'artifacts',records[0],'evidence.json');
const acceptance=JSON.parse(fs.readFileSync(evidenceFile,'utf8'));assert.equal(acceptance.passed,true);assert.equal(acceptance.tested_sha,head);
const evidence={passed:true,source_commit:head,source_snapshot_sha256:before.sha256,source_files:before.files.length,empty_build_and_fixture_cache:true,toolchain_reused:environment.MOONPORT_TOOLCHAIN_HOME,public_fixture_download_exercised:true,acceptance:evidenceFile,output};
fs.writeFileSync(path.join(output,'source-manifest.json'),JSON.stringify(before,null,2));
fs.writeFileSync(path.join(output,'evidence.json'),JSON.stringify(evidence,null,2));
fs.writeFileSync(path.join(artifacts,'reproduction-latest.json'),JSON.stringify(evidence,null,2));console.log(JSON.stringify(evidence,null,2));
