import {test} from 'node:test';
import assert from 'node:assert/strict';
import {canonical,hash,Report,ENGINE_VERSION,SCHEMA_VERSION,SCHEMA_HASH} from '../../packages/schema/index.js';
import {canonicalJson,canonicalJsonDigest} from '../../packages/runtime/canonical-json.js';

test('bounded canonical report serialization preserves historical JSON bytes and identities',()=>{
  const values:unknown[]=[null,true,false,0,-0,1e-7,1e21,NaN,Infinity,'한글 😀 " \\ \n \u0000 \ud800',[],[undefined,,null],{z:undefined,a:null},
    {'10':'ten','2':'two','01':'leading','4294967295':'not-index','4294967294':'index',A:1,a:2,'ä':3},JSON.parse('{"__proto__":4}'),
    Object.fromEntries([['é',1],['e\u0301',2]]),Object.fromEntries([['e\u0301',2],['é',1]]),
    Object.assign(Object.create(null),{constructor:'data',toString:'quoted'}),{text:'😀'.repeat(70000),nested:[{same:1},{same:1}]}];
  const shared={text:'shared'};values.push({a:shared,b:shared});
  let seed=1947;const random=()=>((seed=(Math.imul(seed,1664525)+1013904223)>>>0)/2**32);
  for(let i=0;i<100;i++){const item:Record<string,unknown>={};for(let j=0;j<25;j++)item[['10','2','é','e','한글','Z','a'][j%7]+Math.floor(random()*10)]=j%4===0?undefined:[random(),-random(),'😀'+j];values.push(item);}
  for(const value of values){assert.equal(canonicalJson(value),canonical(value));assert.equal(canonicalJsonDigest(value),hash(value));}
  const report=Report.parse({schema_version:SCHEMA_VERSION,engine_version:ENGINE_VERSION,schema_hash:SCHEMA_HASH,report_id:'rpt_test',project_id:'prj_test',timeline_revision_id:'timeline',mapping_revision_id:'mapping',observation_environment:{'2':'numeric','10':'index'},revisions:[],matches:[],candidates:[],mapping_decisions:[],lineages:[],changes:[],coverage_gaps:[]});
  assert.equal(canonicalJson(report),canonical(report));assert.equal(canonicalJsonDigest(report),hash(report));
});

test('canonical report serialization refuses execution-bearing or cyclic objects',()=>{
  let invoked=false;const getter=Object.defineProperty({},'text',{enumerable:true,get(){invoked=true;return 'bad';}});
  const cycle:any={};cycle.self=cycle;
  for(const value of [getter,cycle,new Date(),1n,{toJSON(){invoked=true;return 'bad';}}])assert.throws(()=>canonicalJson(value),TypeError);
  assert.equal(invoked,false);
});
