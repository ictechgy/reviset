import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,readFile,lstat,rm,symlink,writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import fs from 'node:fs';
import {syncBuiltinESMExports} from 'node:module';
import {canonical,hash,id,byteHash,Report,ENGINE_VERSION,SCHEMA_VERSION,SCHEMA_HASH} from '../../packages/schema/index.js';
import {canonicalJson,canonicalJsonDigest,writeCanonicalJson} from '../../packages/runtime/canonical-json.js';

test('bounded canonical report serialization preserves historical JSON bytes and identities',()=>{
  const values:unknown[]=[null,true,false,0,-0,1e-7,1e21,NaN,Infinity,'한글 😀 " \\ \n \u0000 \ud800',[],[undefined,,null],{z:undefined,a:null},
    {'10':'ten','2':'two','01':'leading','4294967295':'not-index','4294967294':'index',A:1,a:2,'ä':3},JSON.parse('{"__proto__":4}'),
    Object.fromEntries([['é',1],['e\u0301',2]]),Object.fromEntries([['e\u0301',2],['é',1]]),
    Object.assign(Object.create(null),{constructor:'data',toString:'quoted'}),{text:'😀'.repeat(70000),nested:[{same:1},{same:1}]}];
  const shared={text:'shared'};values.push({a:shared,b:shared});
  let seed=1947;const random=()=>((seed=(Math.imul(seed,1664525)+1013904223)>>>0)/2**32);
  for(let i=0;i<100;i++){const item:Record<string,unknown>={};for(let j=0;j<25;j++)item[['10','2','é','e','한글','Z','a'][j%7]+Math.floor(random()*10)]=j%4===0?undefined:[random(),-random(),'😀'+j];values.push(item);}
  for(const value of values){assert.equal(canonicalJson(value),canonical(value));assert.equal(canonicalJsonDigest(value),hash(value));assert.equal('rpt_'+canonicalJsonDigest(value),id('rpt',value));}
  const report=Report.parse({schema_version:SCHEMA_VERSION,engine_version:ENGINE_VERSION,schema_hash:SCHEMA_HASH,report_id:'rpt_test',project_id:'prj_test',timeline_revision_id:'timeline',mapping_revision_id:'mapping',observation_environment:{'2':'numeric','10':'index'},revisions:[],matches:[],candidates:[],mapping_decisions:[],lineages:[],changes:[],coverage_gaps:[]});
  assert.equal(canonicalJson(report),canonical(report));assert.equal(canonicalJsonDigest(report),hash(report));
});

test('canonical report serialization refuses execution-bearing or cyclic objects',()=>{
  let invoked=false;const getter=Object.defineProperty({},'text',{enumerable:true,get(){invoked=true;return 'bad';}});
  const cycle:any={};cycle.self=cycle;
  for(const value of [getter,cycle,new Date(),1n,{toJSON(){invoked=true;return 'bad';}}])assert.throws(()=>canonicalJson(value),TypeError);
  assert.equal(invoked,false);
});

test('report staging writes exclusive private canonical bytes with their exact digest',async()=>{
  const folder=await mkdtemp(join(tmpdir(),'reviset-stage-json-'));
  try{
    const value={rows:Array.from({length:3000},(_,i)=>({id:i,text:'한글😀'.repeat(80),optional:i%2?undefined:null}))},path=join(folder,'report.json');
    const digest=writeCanonicalJson(path,value),bytes=await readFile(path);
    assert.equal(bytes.toString('utf8'),canonical(value));assert.equal(digest,byteHash(bytes));assert.equal((await lstat(path)).mode&0o777,0o600);
    assert.throws(()=>writeCanonicalJson(path,{overwrite:true}),{code:'EEXIST'});assert.deepEqual(await readFile(path),bytes);
    const target=join(folder,'outside'),link=join(folder,'link');await writeFile(target,'preserve');await symlink(target,link);
    assert.throws(()=>writeCanonicalJson(link,value),{code:'EEXIST'});assert.equal(await readFile(target,'utf8'),'preserve');
    const controller=new AbortController();controller.abort();const cancelled=join(folder,'cancelled');
    assert.throws(()=>writeCanonicalJson(cancelled,value,controller.signal),{name:'AbortError'});await assert.rejects(lstat(cancelled),{code:'ENOENT'});
  }finally{await rm(folder,{recursive:true,force:true});}
});

test('partial staging failures remove only their exclusive file and preserve the original cause',async(t)=>{
  const folder=await mkdtemp(join(tmpdir(),'reviset-stage-failure-')),value=Array.from({length:4000},(_,i)=>({i,text:'x'.repeat(80)}));
  try{
    // The first batch reaches disk; an actual writer failure then leaves no
    // orphan. Existing destinations remain protected by the exclusive open.
    const original=fs.writeSync,ioError=Object.assign(new Error('injected EIO after first batch'),{code:'EIO'});let writes=0;
    t.mock.method(fs,'writeSync',(...args:any[])=>{if(++writes===2)throw ioError;return (original as any)(...args);});syncBuiltinESMExports();
    const failed=join(folder,'io.json');assert.throws(()=>writeCanonicalJson(failed,value),error=>error===ioError);assert.ok(writes>=2);await assert.rejects(lstat(failed),{code:'ENOENT'});
    t.mock.restoreAll();syncBuiltinESMExports();
    const cycle:any={};cycle.self=cycle;const malformed=join(folder,'malformed.json');assert.throws(()=>writeCanonicalJson(malformed,[...value,cycle]),TypeError);await assert.rejects(lstat(malformed),{code:'ENOENT'});
    const controller=new AbortController(),cancelled=join(folder,'abort.json');
    t.mock.method(fs,'writeSync',(...args:any[])=>{const n=(original as any)(...args);controller.abort();return n;});syncBuiltinESMExports();
    assert.throws(()=>writeCanonicalJson(cancelled,value,controller.signal),{name:'AbortError'});await assert.rejects(lstat(cancelled),{code:'ENOENT'});
    t.mock.restoreAll();syncBuiltinESMExports();
    const repaired=join(folder,'retry.json');assert.equal(writeCanonicalJson(repaired,value),byteHash(await readFile(repaired)));
  }finally{t.mock.restoreAll();syncBuiltinESMExports();await rm(folder,{recursive:true,force:true});}
});
