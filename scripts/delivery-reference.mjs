// Test-only transition model. This module does not import the product, its
// planner/auditor, or a product-generated expected layout. Paths are abstract
// slots; disk access belongs to the isolated conformance adapter.
import {isDeepStrictEqual} from 'node:util';

const emptyOrigin=()=>({root:'',path:''});
const fold=value=>value.replace(/[A-Z]/g,c=>c.toLowerCase());
const identity=value=>JSON.stringify([value.root,value.path]);
const parents=value=>value.split('/').slice(0,-1).map((_,i)=>value.split('/').slice(0,i+1).join('/'));
const ordered=items=>[...items].sort((a,b)=>a.path<b.path?-1:a.path>b.path?1:0);
const directory=path=>({path,kind:'directory',origin:emptyOrigin()});

export class DeliveryReferenceError extends Error {
  constructor(code,message,step=-1){super(`${code}${step<0?'':` at step ${step}`}: ${message}`);this.name='DeliveryReferenceError';this.code=code;this.step=step;}
}
const fail=(code,message,step)=>{throw new DeliveryReferenceError(code,message,step);};
function relative(value,allowRoot=false){
  if(typeof value!=='string'||(!value&&!allowRoot)||value.includes('\\')||value.includes('\0')||/^[A-Za-z]:/.test(value)||value.startsWith('/')||(value&&value.split('/').some(p=>!p||p==='.'||p==='..')))fail('PATH',`Invalid relative path ${JSON.stringify(value)}`);
}
function targetPath(value){
  relative(value);
  for(const part of value.split('/'))if(/[<>:"|?*\x00-\x1f]/.test(part)||/[. ]$/.test(part)||/^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)/i.test(part))fail('PATH',`Nonportable target ${value}`);
}
function initialRoots(spec){
  const roots=new Map();
  if(spec.target.snapshot.profile!=='portable-windows-v1')fail('TARGET_PROFILE','Target requires portable-windows-v1');
  for(const tree of [...spec.sources,spec.target]){
    if(!tree.id||roots.has(tree.id))fail('ROOT','Root IDs must be unique and nonempty');
    const snapshot=tree.snapshot;
    if(!snapshot.complete||snapshot.scope.length||snapshot.scan_issues.length)fail('INCOMPLETE','Snapshots must be complete and unscoped');
    const entries=new Map(),explicit=new Set();
    for(const entry of snapshot.entries){
      relative(entry.path);
      if(!['file','directory'].includes(entry.kind)||explicit.has(entry.path))fail('STRUCTURE','Invalid or duplicate snapshot entry');
      explicit.add(entry.path);
      if(entries.has(entry.path)&&entries.get(entry.path).kind!==entry.kind)fail('STRUCTURE','File/directory conflict');
      entries.set(entry.path,{path:entry.path,kind:entry.kind,origin:entry.kind==='file'?{root:tree.id,path:entry.path}:emptyOrigin()});
      for(const p of parents(entry.path)){
        if(entries.get(p)?.kind==='file')fail('STRUCTURE',`File ancestor ${p}`);
        entries.set(p,directory(p));
      }
    }
    roots.set(tree.id,entries);
  }
  const slots=new Map();
  for(const entry of roots.get(spec.target.id).values()){
    targetPath(entry.path);
    if(slots.has(fold(entry.path)))fail('TARGET_COLLISION','Initial target has folded aliases');
    slots.set(fold(entry.path),entry);
  }
  return {roots,initial:slots};
}

// This projection is declarative: remove initial Move owners, then materialize
// the declared outputs and their directory closure. It never simulates a plan.
function derive(spec){
  const {roots,initial}=initialRoots(spec),intents=[],requiredDirectories=new Map(),moves=new Map();
  function requireDirectory(p){
    targetPath(p);
    const key=fold(p),old=requiredDirectories.get(key);
    if(old&&old.path!==p)fail('TARGET_COLLISION',`Inconsistent directory spelling ${p}`);
    requiredDirectories.set(key,directory(p));
  }
  for(const mapping of spec.mappings){
    if(!['copy','move'].includes(mapping.mode))fail('MAPPING','Unknown mapping mode');
    relative(mapping.from,true);relative(mapping.to,true);
    const root=roots.get(mapping.source);
    if(!root)fail('SOURCE','Unknown source root');
    const source=mapping.from===''?directory(''):root.get(mapping.from);
    if(!source)fail('SOURCE',`Missing initial source ${mapping.source}:${mapping.from}`);
    if(mapping.mode==='move'&&(mapping.source!==spec.target.id||source.kind!=='file'))fail('MOVE','Only initial target files may move');
    const expanded=[];
    if(source.kind==='file')expanded.push([source,mapping.to]);
    else {
      if(mapping.to)requireDirectory(mapping.to);
      const prefix=mapping.from?mapping.from+'/':'';
      for(const entry of root.values())if(entry.path.startsWith(prefix)&&entry.path!==mapping.from){
        const suffix=entry.path.slice(prefix.length);
        expanded.push([entry,mapping.to?mapping.to+'/'+suffix:suffix]);
      }
    }
    for(const [entry,destination] of expanded){
      targetPath(destination);
      if(entry.kind==='directory')requireDirectory(destination);
      else {
        const intent={mode:mapping.mode,to:destination,origin:{...entry.origin}};
        intents.push(intent);
        if(mapping.mode==='move'){
          const key=identity(entry.origin);
          if(moves.has(key))fail('MOVE','Initial identity has multiple Move intents');
          moves.set(key,intent);
        }
        for(const p of parents(destination))requireDirectory(p);
      }
    }
  }
  for(const entry of [...requiredDirectories.values()])for(const p of parents(entry.path))requireDirectory(p);
  const final=new Map(initial);
  for(const intent of moves.values())final.delete(fold(intent.origin.path));
  const outputs=new Map();
  for(const intent of intents){
    const slot=fold(intent.to);
    if(outputs.has(slot))fail('MAPPING_COLLISION',`Multiple outputs at ${intent.to}`);
    if(final.has(slot))fail('OCCUPIED',`Unvacated initial entry at ${intent.to}`);
    outputs.set(slot,intent);
    final.set(slot,{path:intent.to,kind:'file',origin:intent.origin});
  }
  for(const [slot,entry] of requiredDirectories){
    const old=final.get(slot);
    if(old&&(old.kind!=='directory'||old.path!==entry.path))fail('TARGET_COLLISION',`Directory collision at ${entry.path}`);
    final.set(slot,entry);
  }
  for(const entry of final.values())for(const p of parents(entry.path)){
    const parent=final.get(fold(p));
    if(!parent||parent.kind!=='directory'||parent.path!==p)fail('TARGET_COLLISION',`Invalid final parent ${p}`);
  }
  return {roots,initial,final,outputs,moves};
}

export function expectedLayout(spec){return ordered(derive(spec).final.values());}

// Compare basis semantically, independently of product canonical JSON spelling.
// Wire-format canonicalization is deliberately left to product codec tests.
function semanticSpec(spec){
  const snapshot=s=>({format:s.format,version:s.version,profile:s.profile,complete:s.complete,scope:[...s.scope].sort(),scan_issues:s.scan_issues,entries:ordered(s.entries).map(e=>({path:e.path,kind:e.kind}))});
  const tree=t=>({id:t.id,snapshot:snapshot(t.snapshot)});
  return {format:spec.format,version:spec.version,target:tree(spec.target),sources:spec.sources.map(tree).sort((a,b)=>a.id<b.id?-1:a.id>b.id?1:0),mappings:spec.mappings.map(m=>({mode:m.mode,source:m.source,from:m.from,to:m.to})).sort((a,b)=>JSON.stringify(a)<JSON.stringify(b)?-1:JSON.stringify(a)>JSON.stringify(b)?1:0)};
}

export function replayPlan(spec,plan){
  const {roots,initial,final,outputs,moves}=derive(spec),state=new Map(initial),temporary=new Set();
  if(plan.status!=='ready'||plan.diagnostics?.length)fail('PLAN_STATUS','Expected ready plan');
  let basis;
  try{basis=JSON.parse(plan.basis);}catch{fail('BASIS','Plan basis is not a spec JSON document');}
  if(!isDeepStrictEqual(semanticSpec(basis),semanticSpec(spec)))fail('BASIS','Plan basis describes a different spec');
  for(const name of plan.temporary_paths){
    targetPath(name);const key=fold(name);
    if(name.includes('/')||temporary.has(key)||initial.has(key)||final.has(key))fail('TEMPORARY_CONFLICT',`Occupied or invalid temporary ${name}`);
    temporary.add(key);
  }
  for(const [step,op] of plan.operations.entries()){
    targetPath(op.to);const slot=fold(op.to);
    if(state.has(slot))fail('DESTINATION_OCCUPIED',op.to,step);
    for(const p of parents(op.to))if(state.get(fold(p))?.kind!=='directory'||state.get(fold(p))?.path!==p)fail('PARENT_MISSING',p,step);
    if(op.kind==='mkdir'){
      if(op.source!==''||op.from!==''||!isDeepStrictEqual(op.origin,emptyOrigin()))fail('MKDIR_FIELDS',op.to,step);
      const goal=final.get(slot);
      if(goal?.kind!=='directory'||goal.path!==op.to)fail('UNRELATED_MKDIR',op.to,step);
      state.set(slot,directory(op.to));
      continue;
    }
    if(!['copy','move'].includes(op.kind))fail('OP_KIND',op.kind,step);
    const source=op.source===spec.target.id?state.get(fold(op.from)):roots.get(op.source)?.get(op.from);
    if(source?.kind!=='file'||source.path!==op.from||!isDeepStrictEqual(source.origin,op.origin))fail('SOURCE_IDENTITY',`${op.source}:${op.from}`,step);
    if(op.kind==='copy'){
      const goal=outputs.get(slot);
      if(goal?.mode!=='copy'||goal.to!==op.to||!isDeepStrictEqual(goal.origin,op.origin))fail('UNRELATED_COPY',op.to,step);
    }else {
      if(op.source!==spec.target.id)fail('READONLY_SOURCE',op.source,step);
      const goal=moves.get(identity(op.origin));
      if(!goal||(!temporary.has(slot)&&goal.to!==op.to))fail('UNRELATED_MOVE',op.to,step);
      state.delete(fold(op.from));
    }
    state.set(slot,{path:op.to,kind:'file',origin:{...op.origin}});
  }
  for(const name of temporary)if(state.has(name))fail('TEMPORARY_LEFTOVER',name);
  const result=ordered(state.values());
  if(!isDeepStrictEqual(result,ordered(final.values())))fail('FINAL_LAYOUT','Final path, directory, or origin differs from declarative layout');
  return result;
}
