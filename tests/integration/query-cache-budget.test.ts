import {test} from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {BoundedCache} from '../../packages/query/bounded-cache.js';
import {QueryService} from '../../packages/query/index.js';
import {ENGINE_VERSION,SCHEMA_VERSION,SCHEMA_HASH,type ReportData} from '../../packages/schema/index.js';
import type {Store} from '../../packages/storage/index.js';

test('cache byte boundaries match JSON UTF-8 for escaped, Unicode, sparse and nested plain data',()=>{
  const holes=Array(4);holes[1]=undefined;holes[3]='😀';
  const controls=Array.from({length:32},(_,i)=>String.fromCharCode(i)).join('');
  const utf16=Array.from({length:65536},(_,i)=>String.fromCharCode(i)).join('');
  const values:unknown[]=[null,true,false,0,-0,1e21,1e-7,NaN,Infinity,'',controls,utf16,'"\\/한😀\u2028\u2029\ud800x\udc00',holes,
    {undefined,empty:[],nested:{'한😀"':controls,number:42},array:[undefined,null,{},[]]},Object.assign(Object.create(null),{a:1,b:undefined})];
  for(const value of values){
    const bytes=Buffer.byteLength(JSON.stringify(value)),exact=new BoundedCache<unknown>(1,bytes),short=new BoundedCache<unknown>(1,bytes-1);
    exact.set('entry',value);assert.equal(exact.get('entry'),value,JSON.stringify(value));
    short.set('entry',value);assert.equal(short.get('entry'),undefined,JSON.stringify(value));
  }
});

test('cache aggregate byte eviction, LRU and replacement retain exact accounting',()=>{
  const cache=new BoundedCache<string>(3,14);
  cache.set('a','aaaa');cache.set('b','bbbb');cache.set('a','a');cache.set('c','ccc');
  assert.equal(cache.get('b'),'bbbb');assert.equal(cache.get('a'),'a');
  cache.set('d','d');assert.equal(cache.get('c'),undefined);assert.equal(cache.get('a'),'a');assert.equal(cache.get('b'),'bbbb');
  cache.set('a','x'.repeat(100));assert.equal(cache.get('a'),'a','rejected replacement preserves its prior entry');
  cache.set('b','bbbbbbbbbb');assert.equal(cache.get('b'),'bbbbbbbbbb');assert.equal(cache.get('a'),undefined);assert.equal(cache.get('d'),undefined);
});

test('oversized row sets stop before reading their remaining observations',()=>{
  let tailReads=0;const rows:unknown[]=Array.from({length:128},()=>({text:'x'.repeat(1024)}));
  Object.defineProperty(rows,127,{get(){tailReads++;throw Error('oversized tail must not be read');}});
  const cache=new BoundedCache<unknown>(2,2048);cache.set('kept',{text:'retained'});
  assert.doesNotThrow(()=>cache.set('oversized',{rows}));
  assert.equal(tailReads,0);assert.equal(cache.get('oversized'),undefined);assert.deepEqual(cache.get('kept'),{text:'retained'});
});

test('an oversized escaped primitive is rejected within a small subprocess heap',t=>{
  const module=new URL('../../packages/query/bounded-cache.ts',import.meta.url).href;
  const script=`import {BoundedCache} from ${JSON.stringify(module)};const c=new BoundedCache(1,1024);const huge='\\0'.repeat(24*1024*1024);const before=process.resourceUsage().maxRSS;c.set('huge',huge);if(c.get('huge')!==undefined)throw Error('oversized value cached');console.log(JSON.stringify({growthKiB:process.resourceUsage().maxRSS-before}));`;
  const result=spawnSync(process.execPath,['--max-old-space-size=96','--import','tsx','--input-type=module','-e',script],{encoding:'utf8',timeout:30_000,maxBuffer:8192});
  assert.equal(result.status,0,result.stderr);assert.equal(result.signal,null);
  const {growthKiB}=JSON.parse(result.stdout);assert.ok(growthKiB<32*1024,result.stdout);t.diagnostic(`Rejected 24 MiB escaped string: peak RSS growth ${growthKiB} KiB`);
});

test('row-cache accounting includes report coverage and keys, while stored size bypasses serialization',()=>{
  const rows=[{page_id:'one'}],context={report_id:'fixed',schema_version:'0.4.0',coverage_gaps:[{feature:'ocr',reason:'한'.repeat(40)}]};
  const value={context,rows},bytes=Buffer.byteLength(JSON.stringify(value)),cache=new BoundedCache<typeof value>(2,bytes-1);
  cache.set('oversized',value);assert.equal(cache.get('oversized'),undefined);
  const exact=new BoundedCache<typeof value>(2,bytes);exact.set('exact',value);assert.equal(exact.get('exact'),value);
  const sized=new BoundedCache<object>(2,20),opaque={toJSON(){throw Error('already measured');}};
  sized.set('stored',opaque,20);assert.equal(sized.get('stored'),opaque);
  for(const invalid of [-1,NaN,Infinity,1.5,21]){sized.set('invalid',opaque,invalid);assert.equal(sized.get('invalid'),undefined);}
});

test('bounded traversal handles deep JSON and shared children without treating sharing as a cycle',()=>{
  const child={text:'shared'},shared={a:child,b:child},bytes=Buffer.byteLength(JSON.stringify(shared)),cache=new BoundedCache<object>(1,bytes);
  cache.set('shared',shared);assert.equal(cache.get('shared'),shared);
  let deep:unknown=0;for(let i=0;i<20_000;i++)deep=[deep];const bounded=new BoundedCache<unknown>(1,16);
  assert.doesNotThrow(()=>bounded.set('deep',deep));assert.equal(bounded.get('deep'),undefined);
});

test('a small query result with oversized report coverage is not retained as a row-cache entry',()=>{
  const gap={feature:'ocr',reason:'x'.repeat(512)},coverage=Array(40_000).fill(gap);
  assert.ok(coverage.length*Buffer.byteLength(JSON.stringify(gap))>16*1024*1024);
  const report:ReportData={schema_version:SCHEMA_VERSION,engine_version:ENGINE_VERSION,schema_hash:SCHEMA_HASH,report_id:'report_coverage',project_id:'project_coverage',timeline_revision_id:'timeline',mapping_revision_id:'mapping',observation_environment:{fixture:'bounded-cache'},revisions:[],matches:[],candidates:[],mapping_decisions:[],lineages:[],changes:[],coverage_gaps:coverage};
  let reads=0;const store={reportWithSize(){reads++;return {report,serializedBytes:65*1024*1024};}} as unknown as Store;
  const q=new QueryService(store,new Set([report.project_id])),args={project_id:report.project_id,report_id:report.report_id};
  assert.deepEqual(q.query('get_report',args),q.query('get_report',args));
  assert.equal(reads,2,'coverage is charged even when the projected rows are small');
});


test('latest is resolved once so advancing publication cannot cache B under A',()=>{
  const make=(report_id:string):ReportData=>({schema_version:SCHEMA_VERSION,engine_version:ENGINE_VERSION,schema_hash:SCHEMA_HASH,report_id,project_id:'project_latest',timeline_revision_id:'timeline',mapping_revision_id:'mapping',observation_environment:{fixture:'latest-race'},revisions:[],matches:[],candidates:[],mapping_decisions:[],lineages:[],changes:[],coverage_gaps:[]});
  const reports={report_A:make('report_A'),report_B:make('report_B')};let current:keyof typeof reports='report_A',resolutions=0;const reads:string[]=[];
  const store={resolveReportId(project:string,selector:string){assert.equal(project,'project_latest');assert.equal(selector,'latest');resolutions++;const resolved=current;current='report_B';return resolved;},reportWithSize(project:string,reportId:keyof typeof reports){assert.equal(project,'project_latest');reads.push(reportId);return {report:reports[reportId],serializedBytes:65*1024*1024};}} as unknown as Store;
  const q=new QueryService(store,new Set(['project_latest'])),request=(report_id:string)=>q.query('get_report',{project_id:'project_latest',report_id});
  const first=request('latest');assert.equal(first.report_id,'report_A');assert.equal(first.items[0]!.report_id,'report_A');assert.equal(resolutions,1);assert.deepEqual(reads,['report_A']);
  const explicitA=request('report_A');assert.deepEqual(explicitA,first);assert.deepEqual(reads,['report_A'],'fixed A uses only its own derivative');
  const next=request('latest');assert.equal(next.report_id,'report_B');assert.equal(next.items[0]!.report_id,'report_B');assert.equal(resolutions,2);assert.deepEqual(reads,['report_A','report_B']);
  assert.deepEqual(request('report_A'),first);assert.deepEqual(request('report_B'),next);assert.deepEqual(reads,['report_A','report_B']);
  const other=new QueryService(store,new Set());assert.throws(()=>other.query('get_report',{project_id:'project_latest',report_id:'latest'}),/scope/);assert.equal(resolutions,2,'scope check precedes resolution');
});

test('unsupported cache admission skips retention without executing accessors or custom serializers',()=>{
  let calls=0;const accessor={get value(){calls++;throw Error('getter must not run');}},custom={toJSON(){calls++;throw Error('serializer must not run');}};
  const cycle:Record<string,unknown>={};cycle.self=cycle;
  const cache=new BoundedCache<unknown>(2,1024);cache.set('entry',{retained:true});
  for(const value of [new Date(0),1n,cycle,accessor,custom,Object.assign(Object.create({}),{value:1})]){assert.doesNotThrow(()=>cache.set('entry',value));assert.deepEqual(cache.get('entry'),{retained:true});}
  assert.equal(calls,0);
});
