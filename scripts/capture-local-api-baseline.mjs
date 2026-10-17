import fs from 'node:fs';
import {spawnSync} from 'node:child_process';
import {interfaceHash} from './interface-baseline.mjs';
const destination=process.argv[2];if(!destination)throw new Error('Usage: capture-local-api-baseline.mjs artifacts/FILE.json');
function git(args){const r=spawnSync('git',args,{encoding:'utf8'});if(r.status!==0)throw new Error(r.stderr);return r.stdout;}
const tracked=git(['ls-files','--','*.mbti']).trim().split('\n').filter(Boolean);
const extra=git(['ls-files','--others','--exclude-standard','--','*.mbti']).trim().split('\n').filter(Boolean);
let oldDeclarations=0;
for(const file of tracked){
  const before=git(['show',`HEAD:${file}`]).replaceAll('\r\n','\n');const after=fs.readFileSync(file,'utf8').replaceAll('\r\n','\n');
  for(const block of before.split(/\n\n+/).filter(b=>/^pub /.test(b))){if(!after.includes(block))throw new Error(`Existing public declaration changed in ${file}: ${block.slice(0,100)}`);oldDeclarations++;}
}
const files=[...tracked,...extra].sort().map(p=>({path:p,sha256:interfaceHash(fs.readFileSync(p,'utf8'))}));
const baseline={schema_version:1,source_base:git(['rev-parse','HEAD']).trim(),old_public_declarations_preserved:oldDeclarations,files,note:'Explicit local baseline for authorized uncommitted additions; default Git/CI API gate is unchanged.'};
fs.writeFileSync(destination,JSON.stringify(baseline,null,2)+'\n');console.log(JSON.stringify({local_baseline:destination,files:files.length,oldDeclarations}));
