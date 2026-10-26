import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {QueryService} from '../../packages/query/index.js';
import {Store} from '../../packages/storage/index.js';
import {ENGINE_VERSION,SCHEMA_VERSION,SCHEMA_HASH,type ReportData} from '../../packages/schema/index.js';
import {nativeChangePage,nativeChangeDetail,NATIVE_CHANGE_PAGE_BYTES,NATIVE_CHANGE_DETAIL_CHARS} from '../../packages/desktop/document-changes.js';
function fixture(count=12000):ReportData {
  const revisions=['a','b','c'].map(k=>({revision_id:'rev_'+k,revision_occurrence_id:'occ_'+k,label:k,assets:[],status:'success' as const,pages:[],coverage_gaps:[],errors:[],bundle_mapping:[]}));
  const text='한😀"\\\n'.repeat(600)+' full SEARCH Beyond Preview';
  return {schema_version:SCHEMA_VERSION,engine_version:ENGINE_VERSION,report_id:'report_native_transport',project_id:'project_native_transport',schema_hash:SCHEMA_HASH,timeline_revision_id:'timeline',mapping_revision_id:'mapping',observation_environment:{fixture:'synthetic'},revisions,matches:[],candidates:[],mapping_decisions:[],lineages:[],coverage_gaps:[],changes:Array.from({length:count},(_,i)=>({schema_version:SCHEMA_VERSION,report_id:'report_native_transport',change_id:'change_'+i,entity_id:'entity_'+i,from_revision:'rev_a',to_revision:'rev_b',from_occurrence:'occ_a',to_occurrence:'occ_b',kind:i%2?'text_modified':'coverage_gap',before:text,after:text+' '+i,lineage:{status:'inferred',score:.9,reasons:[text]},coverage_gaps:[{feature:'synthetic',reason:text}],evidence_uri:'docver://synthetic',evidence:Array.from({length:12},(_,n)=>({revision_id:n<9?'rev_a':'rev_b',revision_occurrence_id:n<9?'occ_a':'occ_b',asset_id:'asset_'+n,page_id:'page_'+n,page:n+1,bbox:[0,0,1,1] as [number,number,number,number],quote:text,method:'synthetic'}))}))};
}
const scope={project_id:'project_native_transport',report_id:'report_native_transport',from:'occ_a',to:'occ_c',mode:'history' as const};
function service(report:ReportData){return new QueryService({} as Store,new Set([report.project_id]),(project,id)=>{assert.equal(project,report.project_id);assert.equal(id,report.report_id);return report;});}
test('native document transport traverses a >64MiB canonical change list without duplicate/omitted events or oversized initial/continuation responses',()=>{
  const report=fixture(),query=service(report);let logicalBytes=2;
  for(const change of report.changes)logicalBytes+=Buffer.byteLength(JSON.stringify(change))+1;
  assert.ok(logicalBytes>64*1024*1024,'Regression must exceed Windows helper cap');
  let cursor:string|undefined,received:string[]=[],pageCount=0;
  do {const page=nativeChangePage(query,{...scope,...(cursor?{cursor}:{})});assert.ok(Buffer.byteLength(JSON.stringify(page))<NATIVE_CHANGE_PAGE_BYTES);assert.equal(page.total_count,report.changes.length);assert.ok(page.items.length>0&&page.items.length<=100);assert.ok(page.items.every(c=>c.detail_required&&c.summary_preview));assert.ok(page.items[0].evidence.some(e=>e.revision_occurrence_id==='occ_b'),'Both event-source anchors must survive even when earlier evidence fills the preview');received.push(...page.items.map(c=>c.change_id));cursor=page.next_cursor??undefined;pageCount++;}while(cursor);
  assert.ok(pageCount>1);assert.deepEqual(received,report.changes.map(c=>c.change_id));assert.equal(new Set(received).size,received.length);
  assert.equal(report.changes[0].evidence.length,12);assert.ok(report.changes[0].before!.length>180,'Transport must not mutate canonical observations');
});
test('selected native detail recovers every UTF16 unit and all evidence; full-text filters find matches beyond preview and reject foreign/stale scopes',()=>{
  const report=fixture(5),query=service(report),change=report.changes[1];change.before='😀한"\\\n'.repeat(40000);change.after=null;change.evidence.push({...change.evidence[0],quote:'LAST EVIDENCE '+change.before});
  const page=nativeChangePage(query,scope);let offset=0,parts:string[]=[],digest='';
  do {const part=nativeChangeDetail(query,{...scope,query_id:page.query_id,change_id:change.change_id,detail_offset:offset});assert.ok(part.json_chunk.length<=NATIVE_CHANGE_DETAIL_CHARS);assert.ok(Buffer.byteLength(JSON.stringify(part))<4*1024*1024);assert.equal(part.detail_offset,offset);parts.push(part.json_chunk);digest=part.content_sha256;if(part.next_detail_offset===null)break;assert.ok(part.next_detail_offset>offset);offset=part.next_detail_offset;}while(true);
  assert.ok(parts.length>1);const serialized=parts.join('');assert.equal(createHash('sha256').update(serialized).digest('hex'),digest);assert.deepEqual(JSON.parse(serialized),change);
  const filtered=nativeChangePage(query,{...scope,text:'search beyond preview',kind:'coverage_gap',limit:1});assert.equal(filtered.total_count,3);assert.ok(filtered.next_cursor);assert.ok(!filtered.items[0].before!.toLowerCase().includes('search beyond preview'));
  assert.throws(()=>nativeChangePage(query,{...scope,text:'different',cursor:filtered.next_cursor!}),{code:'DOCUMENT_CURSOR_SCOPE'});
  assert.throws(()=>nativeChangePage(query,{...scope,to:'occ_b',cursor:filtered.next_cursor!}),{code:'DOCUMENT_CURSOR_SCOPE'});
  for(const changes of [{from:'occ_b'},{mode:'adjacent'},{text:'different'},{report_id:'other_report'},{project_id:'other_project'}])assert.throws(()=>nativeChangeDetail(query,{...scope,...changes,query_id:page.query_id,change_id:change.change_id}),{code:'DOCUMENT_CHANGE_SCOPE'});
  assert.throws(()=>nativeChangeDetail(query,{...scope,query_id:page.query_id,change_id:'foreign'}),{code:'DOCUMENT_CHANGE_SCOPE'});
  assert.throws(()=>nativeChangePage(query,{...scope,report_id:'latest'}));
  const history=query.changeSet({...scope,change_id:'change_0'});assert.deepEqual(history,[report.changes[0]],'Existing MCP/export full changeSet semantics remain intact');
  const withoutMatch=nativeChangePage(query,{...scope,text:'not present anywhere'});assert.equal(withoutMatch.total_count,0);assert.equal(withoutMatch.next_cursor,null);
  // A stored intermediate event belongs to history a->c, but never to b->c.
  const newer=nativeChangePage(query,{...scope,from:'occ_b'});assert.equal(newer.total_count,0);assert.throws(()=>nativeChangeDetail(query,{...scope,from:'occ_b',query_id:newer.query_id,change_id:change.change_id}),{code:'DOCUMENT_CHANGE_SCOPE'});
});

test('native detail continuation never publishes an offset inside a boundary surrogate pair',()=>{
  const report=fixture(1),change=report.changes[0];
  change.before='';change.after=null;change.evidence=[];change.coverage_gaps=[];change.lineage.reasons=[];
  const empty=JSON.stringify(change),marker='"before":"',start=empty.indexOf(marker)+marker.length;
  assert.ok(start>=marker.length);
  change.before='a'.repeat(NATIVE_CHANGE_DETAIL_CHARS-start-1)+'😀 tail';
  const query=service(report),page=nativeChangePage(query,scope),args={...scope,query_id:page.query_id,change_id:change.change_id};
  const first=nativeChangeDetail(query,args);
  assert.equal(first.next_detail_offset,NATIVE_CHANGE_DETAIL_CHARS-1);
  assert.throws(()=>nativeChangeDetail(query,{...args,detail_offset:NATIVE_CHANGE_DETAIL_CHARS}),{code:'DOCUMENT_CHANGE_SCOPE'});
  const second=nativeChangeDetail(query,{...args,detail_offset:first.next_detail_offset!});
  assert.ok(second.json_chunk.startsWith('😀'));assert.equal(second.next_detail_offset,null);
  assert.deepEqual(JSON.parse(first.json_chunk+second.json_chunk),change);
});
