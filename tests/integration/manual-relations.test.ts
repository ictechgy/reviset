import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,writeFile,rm,readFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {SCHEMA_VERSION,ENGINE_VERSION,SCHEMA_HASH,Report,Manifest,Decision,hash,type PageData,type RevisionData,type ReportData,type MatchData} from '../../packages/schema/index.js';
import {canonicalRelation,relationEdges,validateMappings,rewriteMappings} from '../../packages/matching/relations.js';
import {rangeLineage,pathEdges} from '../../packages/matching/lineage.js';
import {diffRevisions as legacy43Diff} from '../../packages/diff/legacy-ocr-43.js';
import {id} from '../../packages/schema/index.js';
import {matchPages} from '../../packages/matching/index.js';
import {diffRevisions} from '../../packages/diff/index.js';
import {Store} from '../../packages/storage/index.js';
import {DesktopService} from '../../packages/desktop/service.js';
import {QueryService,type QueryName} from '../../packages/query/index.js';
import {analyze} from '../../packages/engine/index.js';
import {makePptx} from '../../scripts/generate-fixtures.js';
import {exportReport} from '../../packages/export/index.js';

function page(id:string,n=1,text='내용 100억'):PageData{return {page_id:id,asset_id:'asset',page:n,width:960,height:540,coordinate_system:'normalized_top_left',source_transform:[1,0,0,1,0,0],hidden:false,text,elements:[{observation_id:'obs_'+id,kind:'text',text,normalized_text:text,bbox:[.1,.1,.5,.1],reading_order:0,availability:'available',method:'fixture_source',source_ref:id,provenance:'observed'}],notes:'',capabilities:{text:'available',notes:'available',hidden_slides:'available',animation:'unavailable',structure:'available',preview:'unavailable'},coverage_gaps:[]};}
function revision(id:string,pages:PageData[]):RevisionData{return {revision_id:'rev_'+id,revision_occurrence_id:id,label:id,assets:[{asset_id:'asset',format:'pptx',bytes:0}],status:'success',pages,coverage_gaps:[],errors:[],bundle_mapping:[]};}
function report(revisions:RevisionData[],matches:MatchData[]=[]):ReportData{return {schema_version:SCHEMA_VERSION,engine_version:ENGINE_VERSION,schema_hash:SCHEMA_HASH,report_id:'report_manual',project_id:'project_manual',timeline_revision_id:'timeline',mapping_revision_id:'mapping',observation_environment:{fixture:'manual-topology'},revisions,matches,candidates:[],mapping_decisions:[],mapping_relations:[],lineages:[{entity_id:'family',page_ids:revisions.flatMap(r=>r.pages.map(p=>p.page_id)),status:'human_confirmed'}],changes:[],coverage_gaps:[]};}
const edges=(a:string,b:string,kind:MatchData['relation_kind']='continuation',rel='rel_'+a):MatchData=>({from_page_id:a,to_page_id:b,score:1,status:'human_confirmed',reasons:['원문 확인'],relation_id:rel,relation_kind:kind});
function all(q:QueryService,name:QueryName,args:Record<string,unknown>){let cursor:string|undefined;const rows:Record<string,unknown>[]=[];for(let i=0;i<1000;i++){const result=q.query(name,{...args,...(cursor?{cursor}:{})});assert.ok(Buffer.byteLength(JSON.stringify(result))<=Number(args.max_output_tokens??4000));rows.push(...result.items);if(!result.next_cursor)return rows;cursor=result.next_cursor;}throw Error('Cursor did not terminate');}

test('typed split/merge reserves all members and emits one structural event, preserving raw uncertainty',()=>{
  const a=revision('v1',[page('a'),page('stable1',2,'매출 100억')]),b=revision('v2',[page('b1'),page('b2',2),page('stable2',3,'매출 120억')]);
  b.pages[1].elements[0].provenance='inferred';b.pages[1].elements[0].method='vision_ocr';b.pages[1].coverage_gaps=[{feature:'ocr',reason:'unresolved_original_reading'}];
  const raw=JSON.stringify([a,b]),selection={kind:'split' as const,from_occurrence:'v1',to_occurrence:'v2',from_page_ids:['a'],to_page_ids:['b2','b1'],reason:'  원문 분할 확인  '},group=canonicalRelation([a,b],selection);
  assert.deepEqual(group.to_page_ids,['b1','b2']);assert.equal(group.reason,selection.reason);assert.equal(group.relation_id,canonicalRelation([a,b],{...selection,to_page_ids:['b1','b2']}).relation_id);
  const matched=matchPages(a.pages,b.pages,[{from_page_id:'stable1',to_page_id:'stable2',action:'link',reason:'숫자 원문'}],[group]),changes=diffRevisions(a,b,matched.matches,matched.candidates,()=> 'family');
  const structural=changes.filter(c=>c.kind==='page_split');assert.equal(structural.length,1);assert.deepEqual(structural[0].topology?.to_page_ids,['b1','b2']);assert.equal(structural[0].lineage.status,'human_confirmed');assert.equal(structural[0].text_assessment,undefined);
  assert.deepEqual(structural[0].evidence.map(e=>[e.page_id,e.method,e.provenance]),[['a','fixture_source','observed'],['b1','fixture_source','observed'],['b2','vision_ocr','inferred']]);
  assert.ok(structural[0].coverage_gaps.some(g=>g.reason==='unresolved_original_reading'));assert.ok(!changes.some(c=>['text_modified','page_added','page_deleted','page_moved','visual_region_changed'].includes(c.kind)&&c.evidence.some(e=>['a','b1','b2'].includes(e.page_id))));
  assert.ok(changes.some(c=>c.kind==='text_modified'&&c.before==='매출 100억'&&c.after==='매출 120억'));assert.equal(JSON.stringify([a,b]),raw);
  const c=revision('v3',[page('c')]),merge=canonicalRelation([b,c],{kind:'merge',from_occurrence:'v2',to_occurrence:'v3',from_page_ids:['b2','b1'],to_page_ids:['c'],reason:'병합'}),merged=diffRevisions(b,c,relationEdges(merge),[],()=> 'family');assert.equal(merged.filter(c=>c.kind==='page_merged').length,1);
});

test('adjacent stored split and merge IDs remain recoverable without claiming endpoint-net equivalence',()=>{
  for(const kind of ['split','merge'] as const){
    const a=revision('before',kind==='split'?[page('a')]:[page('a1'),page('a2',2)]),b=revision('after',kind==='split'?[page('b1'),page('b2',2)]:[page('b')]);
    const group=canonicalRelation([a,b],{kind,from_occurrence:'before',to_occurrence:'after',from_page_ids:a.pages.map(p=>p.page_id),to_page_ids:b.pages.map(p=>p.page_id),reason:'Synthetic reviewed topology'});
    const matched=matchPages(a.pages,b.pages,[],[group]),r=report([a,b],matched.matches);r.mapping_relations=[group];r.candidates=matched.candidates;
    r.changes=diffRevisions(a,b,matched.matches,matched.candidates,()=> 'family').map((change,index)=>({...change,report_id:r.report_id,change_id:'chg_synthetic_'+kind+'_'+index}));
    const raw=JSON.stringify(r),q=new QueryService({} as Store,new Set([r.project_id]),()=>r),scope={project_id:r.project_id,report_id:r.report_id,from:'before',to:'after',max_output_tokens:8000};
    const history=q.changeSet({...scope,mode:'history'}),adjacent=q.changeSet({...scope,mode:'adjacent'}),net=q.changeSet({...scope,mode:'range_net'});
    assert.deepEqual(adjacent,history);assert.equal(history.length,1);assert.equal(history[0].kind,kind==='split'?'page_split':'page_merged');assert.equal(history[0].topology?.semantics,'direct_edges');
    assert.equal(net.length,1);assert.equal(net[0].kind,'page_lineage_changed');assert.equal(net[0].topology?.semantics,'directed_reachability');assert.notEqual(net[0].change_id,history[0].change_id);
    assert.deepEqual(new Set(net[0].evidence.map(e=>e.page_id)),new Set(history[0].evidence.map(e=>e.page_id)));
    const storedSummary=q.query('get_change',{...scope,change_id:history[0].change_id,component:'summary'}).items[0];
    assert.equal(storedSummary.computed_range,false);assert.equal(storedSummary.resource_uri,`docver://projects/${r.project_id}/reports/${r.report_id}/changes/${history[0].change_id}/detail`);
    assert.equal(q.query('get_change',{...scope,change_id:net[0].change_id,component:'summary'}).items[0].computed_range,true);
    assert.throws(()=>q.query('get_change',{...scope,change_id:history[0].change_id,mode:'history'}),'get_change must reject a mode argument');
    assert.equal(all(q,'get_change',{...scope,change_id:history[0].change_id,component:'evidence',limit:1}).length,3);assert.equal(JSON.stringify(r),raw);
  }
});

test('adjacent manual unlink can change event membership on a fresh endpoint computation',()=>{
  const a=revision('before',[page('a')]),b=revision('after',[page('b')]),decisions=[{from_page_id:'a',to_page_id:'b',action:'unlink' as const,reason:'Synthetic explicit unlink'}];
  const matched=matchPages(a.pages,b.pages,decisions),r=report([a,b],matched.matches);r.mapping_decisions=decisions;r.candidates=matched.candidates;
  r.changes=diffRevisions(a,b,matched.matches,matched.candidates,()=> 'family').map((change,index)=>({...change,report_id:r.report_id,change_id:'chg_synthetic_unlink_'+index}));
  const raw=JSON.stringify(r),q=new QueryService({} as Store,new Set([r.project_id]),()=>r),scope={project_id:r.project_id,report_id:r.report_id,from:'before',to:'after'};
  assert.deepEqual(q.changeSet({...scope,mode:'history'}).map(c=>c.kind).sort(),['page_added','page_deleted']);
  const net=q.changeSet({...scope,mode:'range_net'});assert.equal(net.length,2);assert.ok(net.every(c=>c.kind==='coverage_gap'&&c.coverage_gaps.some(g=>g.reason==='unresolved_mapping')));assert.equal(JSON.stringify(r),raw);
});

test('manual relation boundaries reject duplicates, secondary sources, nonadjacency, conflicts and over32 members',()=>{
  const revisions=[revision('v1',[page('a')]),revision('v2',Array.from({length:33},(_,i)=>page('b'+i,i+1))),revision('v3',[page('c')])],selection={kind:'split' as const,from_occurrence:'v1',to_occurrence:'v2',from_page_ids:['a'],to_page_ids:['b0','b1'],reason:'검토'};
  for(const invalid of [{...selection,to_page_ids:['b0','b0']},{...selection,to_occurrence:'v3',to_page_ids:['c']},{...selection,to_page_ids:['b0']},{...selection,to_page_ids:revisions[1].pages.map(p=>p.page_id)},{...selection,reason:' \n '},{...selection,from_page_ids:['unknown']}])assert.throws(()=>canonicalRelation(revisions,invalid));
  const maximum=canonicalRelation(revisions,{...selection,to_page_ids:revisions[1].pages.slice(0,32).map(p=>p.page_id)});assert.equal(maximum.to_page_ids.length,32);
  assert.throws(()=>validateMappings(revisions,[{from_page_id:'a',to_page_id:'b0',action:'link',reason:'중복'}],[selection]),{code:'MAPPING_CONFLICT'});
  assert.throws(()=>validateMappings(revisions,[{from_page_id:'a',to_page_id:'b0',action:'unlink',reason:'차단'}],[selection]),{code:'MAPPING_CONFLICT'});
  revisions[1].assets.push({asset_id:'secondary',format:'pdf',bytes:0});revisions[1].pages.push({...page('secondary'),asset_id:'secondary'});assert.throws(()=>canonicalRelation(revisions,{...selection,to_page_ids:['b0','secondary']}),{code:'MAPPING_NOT_FOUND'});
  assert.ok(Manifest.safeParse({project_id:'p',title:'p',revisions:[{label:'p',files:['p.pdf']}],mapping_decisions:[],mapping_relations:[selection]}).success);
});

test('unlink normalizes residual stars3→2→1→0 and retains negative edges across rematching',()=>{
  const a=revision('v1',[page('a')]),b=revision('v2',[page('b1'),page('b2',2),page('b3',3)]),group=canonicalRelation([a,b],{kind:'split',from_occurrence:'v1',to_occurrence:'v2',from_page_ids:['a'],to_page_ids:['b1','b2','b3'],reason:'처음 확정한 이유'});
  let r=report([a,b],relationEdges(group)),groups=[group],decisions=r.mapping_decisions;
  for(const [i,target] of ['b1','b2','b3'].entries()){
    const result=rewriteMappings(r,decisions,groups,{kind:'continuation',from_occurrence:'v1',to_occurrence:'v2',from_page_ids:['a'],to_page_ids:[target],reason:'한 분기 해제'},true);groups=result.mapping_relations;decisions=result.mapping_decisions;
    assert.equal(groups.length,i===2?0:1);if(groups[0]){assert.equal(groups[0].kind,i===0?'split':'continuation');assert.equal(groups[0].reason,'처음 확정한 이유');}
    assert.equal(decisions.filter(d=>d.action==='unlink').length,i+1);r={...r,matches:groups.flatMap(relationEdges),mapping_relations:groups,mapping_decisions:decisions};
  }
  assert.equal(matchPages(a.pages,b.pages,decisions,groups).matches.length,0);
});

test('replacement preserves unselected residual branches and creates tombstones for displaced automatic edges',()=>{
  const a=revision('v1',[page('a'),page('x',2)]),b=revision('v2',[page('b1'),page('b2',2),page('y',3)]),group=canonicalRelation([a,b],{kind:'split',from_occurrence:'v1',to_occurrence:'v2',from_page_ids:['a'],to_page_ids:['b1','b2'],reason:'기존 분할'}),r=report([a,b],[...relationEdges(group),edges('x','y')]);
  const next=rewriteMappings(r,[],[group],{kind:'continuation',from_occurrence:'v1',to_occurrence:'v2',from_page_ids:['x'],to_page_ids:['b1'],reason:'대상 수정'});
  assert.deepEqual(next.mapping_relations.sort((a,b)=>a.from_page_ids[0].localeCompare(b.from_page_ids[0])).map(g=>[g.kind,g.from_page_ids,g.to_page_ids,g.reason]),[['continuation',['a'],['b2'],'기존 분할'],['continuation',['x'],['b1'],'대상 수정']]);
  assert.deepEqual(next.mapping_decisions.map(d=>[d.from_page_id,d.to_page_id,d.action]),[['a','b1','unlink'],['x','y','unlink']]);
});

test('directed range paths never invent B→F through an undirected split/merge family',()=>{
  const a=revision('v0',[page('A'),page('B',2),page('Z0',3,'매출 100억')]),b=revision('v1',[page('C'),page('D',2),page('E',3),page('Z1',4,'매출 100억')]),c=revision('v2',[page('F'),page('G',2),page('Z2',3,'매출 120억')]),r=report([a,b,c],[edges('A','C','split'),edges('A','D','split'),edges('B','E'),edges('C','F'),edges('D','G','merge','mergeG'),edges('E','G','merge','mergeG'),edges('Z0','Z1'),edges('Z1','Z2')]);
  assert.deepEqual(pathEdges(r,'B','F'),[]);assert.deepEqual(pathEdges(r,'B','G').map(e=>[e.from_page_id,e.to_page_id]),[['B','E'],['E','G']]);
  const range=rangeLineage(r,a,c);assert.deepEqual(range.matches.map(e=>[e.from_page_id,e.to_page_id]),[['Z0','Z2']]);assert.equal(range.structural.length,1);assert.equal(range.structural[0].semantics,'directed_reachability');
  const q=new QueryService({} as Store,new Set([r.project_id]),()=>r),common={project_id:r.project_id,report_id:r.report_id,max_output_tokens:8000};
  assert.deepEqual(q.query('list_page_relations',{...common,reachable_from_page_id:'B',reachable_to_page_id:'F'}).items,[]);
  const net=q.changeSet({...common,mode:'range_net',from:'v0',to:'v2'});assert.equal(net.filter(c=>c.kind==='page_lineage_changed').length,1);assert.equal(net.filter(c=>c.kind==='text_modified').length,1);assert.equal(net.filter(c=>c.kind==='page_added'||c.kind==='page_deleted').length,0);
  const structural=net.find(c=>c.kind==='page_lineage_changed')!;assert.equal(all(q,'get_evidence',{...common,change_id:structural.change_id,from:'v0',to:'v2',limit:1}).length,4);
});

test('maximum multibyte group remains fully recoverable in paged queries, immutable storage and full export',async()=>{
  const folder=await mkdtemp(join(tmpdir(),'docver-relations-')),store=new Store(join(folder,'store'));
  try{
    const a=revision('v1',[page('a')]),b=revision('v2',Array.from({length:32},(_,i)=>page('b'+i,i+1))),group=canonicalRelation([a,b],{kind:'split',from_occurrence:'v1',to_occurrence:'v2',from_page_ids:['a'],to_page_ids:b.pages.map(p=>p.page_id),reason:'한😀'.repeat(400)}),r=report([a,b],relationEdges(group));r.mapping_relations=[group];r.changes=diffRevisions(a,b,r.matches,[],()=> 'family').map((c,i)=>({...c,report_id:r.report_id,change_id:'change_'+i}));Report.parse(r);store.finishRun(store.beginRun(r.project_id,'최대 분할'),r);
    const q=new QueryService(store,new Set([r.project_id])),common={project_id:r.project_id,report_id:r.report_id,max_output_tokens:2048,limit:1};
    const rows=all(q,'list_page_relations',{...common,relation_id:group.relation_id,reason_length:16});assert.equal(rows.length,32);assert.ok(rows.every(row=>row.next_reason_offset!==null));assert.equal(all(q,'get_evidence',{...common,change_id:'change_0',text_length:32}).length,33);
    await exportReport(q,r.project_id,r.report_id,join(folder,'export'));assert.equal(JSON.parse(await readFile(join(folder,'export/report.json'),'utf8')).matches.length,32);assert.equal((await readFile(join(folder,'export/page-relations.jsonl'),'utf8')).trim().split('\n').length,32);assert.ok((await readFile(join(folder,'export/history.md'),'utf8')).includes('페이지 대응은 문구 변경의 확정이 아닙니다'));
  }finally{store.close();await rm(folder,{recursive:true,force:true});}
});

test('desktop mapping is atomic, stale-safe and leaves pending draft and old report intact across reopen',async()=>{
  const folder=await mkdtemp(join(tmpdir(),'docver-draft-relations-'));let service=new DesktopService(join(folder,'library'));
  try{
    const file=join(folder,'fixture.pdf');await writeFile(file,'synthetic bytes; no parser invoked');const p=await service.create('대응',[{label:'before',files:[file]},{label:'after',files:[file]}]),r=report([revision('v1',[page('a')]),revision('v2',[page('b1'),page('b2',2)])]);r.project_id=p.project_id;r.report_id='report_original';
    service.commit(p.project_id,{report:r,analysis_run_id:service.store.beginRun(p.project_id,'대응'),draft_hash:hash(service.manifest(p.project_id))});const original=String(service.store.db.prepare('SELECT body FROM reports WHERE id=?').get(r.report_id)?.body),selection={kind:'split' as const,from_occurrence:'v1',to_occurrence:'v2',from_page_ids:['a'],to_page_ids:['b1','b2'],reason:'원문 확인'};
    assert.throws(()=>service.mappingRelation(p.project_id,r.report_id,{...selection,to_page_ids:['missing','b2']},false,hash(service.manifest(p.project_id))));assert.equal(service.project(p.project_id).dirty,false);
    service.mappingRelation(p.project_id,r.report_id,selection,false,hash(service.manifest(p.project_id)));assert.equal(service.project(p.project_id).dirty,true);assert.throws(()=>service.mappingRelation(p.project_id,r.report_id,selection),{code:'STALE_REPORT'});
    const abort=new AbortController();abort.abort();await assert.rejects(analyze(service.manifest(p.project_id),service.root,service.store,abort.signal,undefined,{ocr:'off',pptxPreview:false}),{name:'AbortError'});assert.equal(service.project(p.project_id).mapping_relations.length,1);assert.equal(service.project(p.project_id).dirty,true);
    service.close();service=new DesktopService(join(folder,'library'));assert.equal(service.project(p.project_id).mapping_relations.length,1);assert.equal(service.project(p.project_id).last_report_id,r.report_id);const other=new DesktopService(join(folder,'library'));try{assert.throws(()=>other.mappingRelation(p.project_id,r.report_id,selection),{code:'STALE_REPORT'});}finally{other.close();}
    assert.throws(()=>service.reorder(p.project_id,[1,0],true),{code:'PENDING_MAPPING_DECISIONS'});
    const otherDraft=await service.create('stale run',[{label:'before',files:[file]},{label:'after',files:[file]}]),staleHash=hash(service.manifest(otherDraft.project_id)),run=service.store.beginRun(otherDraft.project_id,'stale');service.reorder(otherDraft.project_id,[1,0]);assert.throws(()=>service.commit(otherDraft.project_id,{report:{...r,project_id:otherDraft.project_id,report_id:'report_stale'},analysis_run_id:run,draft_hash:staleHash}),{code:'STALE_RUN'});assert.equal(service.reports(p.project_id).length,1);assert.equal(service.project(p.project_id).last_report_id,r.report_id);assert.equal(service.store.db.prepare('SELECT body FROM reports WHERE id=?').get(r.report_id)?.body,original);
    service.close();service=new DesktopService(join(folder,'library'));service.recover(run);assert.equal(service.project(p.project_id).dirty,true);assert.equal(service.snapshot(p.project_id,r.report_id).report_id,r.report_id);
  }finally{service.close();await rm(folder,{recursive:true,force:true});}
});


test('actual engine accepts manual split then merge in a new immutable report and retains independent numeric edits',async()=>{
  const folder=await mkdtemp(join(tmpdir(),'docver-engine-relations-')),store=new Store(join(folder,'store'));
  try{
    const slide=(key:string,body:string)=>({key,title:key,body}),versions=[[slide('통합','설계 구현 검토'),slide('매출 전망','예상 매출 100억')],[slide('설계','설계 검토'),slide('구현','구현 검토'),slide('매출 전망','예상 매출 100억')],[slide('재통합','설계 구현 검토'),slide('매출 전망','예상 매출 120억')]];
    for(const [i,slides] of versions.entries())await writeFile(join(folder,`v${i}.pptx`),await makePptx(slides));
    const input=Manifest.parse({project_id:'actual_relations',title:'분할 병합',revisions:versions.map((_,i)=>({label:`v${i}`,files:[`v${i}.pptx`]}))}),options={ocr:'off' as const,pptxPreview:false},original=(await analyze(input,folder,store,undefined,undefined,options)).report,[a,b,c]=original.revisions;
    const split={kind:'split' as const,from_occurrence:a.revision_occurrence_id,to_occurrence:b.revision_occurrence_id,from_page_ids:[a.pages[0].page_id],to_page_ids:[b.pages[0].page_id,b.pages[1].page_id],reason:'한 장을 두 장으로 나눔'},merge={kind:'merge' as const,from_occurrence:b.revision_occurrence_id,to_occurrence:c.revision_occurrence_id,from_page_ids:[b.pages[0].page_id,b.pages[1].page_id],to_page_ids:[c.pages[0].page_id],reason:'다시 합침'},links=[{from_page_id:a.pages[1].page_id,to_page_id:b.pages[2].page_id,action:'link' as const,reason:'매출 행'},{from_page_id:b.pages[2].page_id,to_page_id:c.pages[1].page_id,action:'link' as const,reason:'매출 행'}];
    const result=(await analyze({...input,mapping_decisions:links,mapping_relations:[split,merge]},folder,store,undefined,undefined,options)).report;assert.notEqual(result.report_id,original.report_id);assert.equal(result.mapping_relations?.length,2);assert.equal(result.matches.filter(m=>m.relation_kind==='split').length,2);assert.equal(result.matches.filter(m=>m.relation_kind==='merge').length,2);
    assert.deepEqual(result.changes.map(c=>c.kind).sort(),['page_split','page_merged','text_modified'].sort());assert.ok(result.changes.find(c=>c.kind==='text_modified')?.after?.includes('120억'));assert.deepEqual(store.report(input.project_id,original.report_id),original);
    const q=new QueryService(store,new Set([input.project_id])),net=q.changeSet({project_id:input.project_id,report_id:result.report_id,mode:'range_net',from:a.revision_occurrence_id,to:c.revision_occurrence_id});assert.equal(net.filter(c=>c.kind==='page_lineage_changed').length,1);assert.equal(net.filter(c=>c.kind==='text_modified').length,1);
    await assert.rejects(analyze({...input,revisions:[...input.revisions].reverse(),mapping_relations:[split]},folder,store,undefined,undefined,options),{code:'MAPPING_INTERVAL'});
  }finally{store.close();await rm(folder,{recursive:true,force:true});}
});


test('range bitsets retain high bits and independent branches across64 endpoints',()=>{
  const a=revision('v0',[page('A'),page('B',2)]),b=revision('v1',Array.from({length:64},(_,i)=>page('M'+i,i+1))),c=revision('v2',Array.from({length:64},(_,i)=>page('E'+i,i+1))),r=report([a,b,c],b.pages.flatMap((p,i)=>[edges(i<32?'A':'B',p.page_id,'split',i<32?'splitA':'splitB'),edges(p.page_id,c.pages[i].page_id)])),net=rangeLineage(r,a,c);
  assert.equal(net.matches.length,0);assert.equal(net.structural.length,2);assert.deepEqual(net.structural[0].to_page_ids,c.pages.slice(0,32).map(p=>p.page_id));assert.deepEqual(net.structural[1].to_page_ids,c.pages.slice(32).map(p=>p.page_id));assert.equal(pathEdges(r,'B','E31').length,0);assert.equal(pathEdges(r,'B','E63').length,2);
});

test('archived42/43 range kernels preserve historical event IDs and0.2 schema',()=>{
  for(const version of ['0.2.0-native.ocr-render.42','0.2.0-native.ocr-render.43']){
    const a=revision('v0',[page('A',1,'예상 매출 100억')]),b=revision('v1',[page('B',1,'예상 매출 120억')]),r=report([a,b],[{from_page_id:'A',to_page_id:'B',score:1,status:'inferred',reasons:['original']}]);r.schema_version='0.2.0';r.engine_version=version;delete r.mapping_relations;
    const expected=legacy43Diff(a,b,[{from_page_id:'A',to_page_id:'B',score:1,status:'human_confirmed',reasons:['snapshot_lineage_range_net']}],[],()=> 'family').map((c,i)=>{const event={...c,schema_version:'0.2.0' as const};return {...event,report_id:r.report_id,change_id:id('net',[r.report_id,'v0','v1',i,event]),evidence_uri:`docver://projects/${r.project_id}/reports/${r.report_id}/manifest`};}),q=new QueryService({} as Store,new Set([r.project_id]),()=>r);
    assert.deepEqual(q.changeSet({project_id:r.project_id,report_id:r.report_id,mode:'range_net',from:'v0',to:'v1'}),expected);assert.equal(r.mapping_relations,undefined);
  }
});


test('stored0.2 decisions and legacy manifests retain long and whitespace reasons under the new UI limit',async()=>{
  const r=report([revision('v0',[page('a')]),revision('v1',[page('b')])]);r.schema_version='0.2.0';r.engine_version='0.2.0-native.ocr-render.42';delete r.mapping_relations;
  for(const reason of ['한😀'.repeat(1000),'   ']){
    r.mapping_decisions=[{from_page_id:'a',to_page_id:'b',action:'link',reason}];assert.deepEqual(Report.parse(r).mapping_decisions,r.mapping_decisions);assert.ok(Manifest.safeParse({project_id:'p',title:'p',revisions:[{label:'v0',files:['a.pptx']}],mapping_decisions:r.mapping_decisions}).success);assert.equal(Decision.safeParse(r.mapping_decisions[0]).success,false);
  }
  const folder=await mkdtemp(join(tmpdir(),'docver-legacy-draft-')),service=new DesktopService(join(folder,'library'));
  try{const file=join(folder,'a.pdf');await writeFile(file,'synthetic bytes');const p=await service.create('기존 이유',[{label:'v0',files:[file]}]),legacy={...p,mapping_decisions:[{from_page_id:'a',to_page_id:'b',action:'link',reason:'한😀'.repeat(1000)}]};delete (legacy as Partial<typeof p>).mapping_relations;service.store.db.prepare('UPDATE desktop_projects_v4 SET body=? WHERE id=?').run(JSON.stringify(legacy),p.project_id);assert.equal(service.project(p.project_id).mapping_decisions[0].reason,legacy.mapping_decisions[0].reason);assert.deepEqual(service.project(p.project_id).mapping_relations,[]);}finally{service.close();await rm(folder,{recursive:true,force:true});}
});


test('revision aliases produce canonical current net IDs and their occurrence fields recover evidence; archived44 IDs stay fixed',()=>{
  const a=revision('v0',[page('A')]),b=revision('v1',[page('B1'),page('B2',2)]),c=revision('v2',[page('C')]),r=report([a,b,c],[edges('A','B1','split'),edges('A','B2','split'),edges('B1','C','merge','mergeC'),edges('B2','C','merge','mergeC')]),q=new QueryService({} as Store,new Set([r.project_id]),()=>r),common={project_id:r.project_id,report_id:r.report_id};
  const aliased=q.changeSet({...common,mode:'range_net',from:a.revision_id,to:c.revision_id}),canonical=q.changeSet({...common,mode:'range_net',from:a.revision_occurrence_id,to:c.revision_occurrence_id});assert.deepEqual(aliased,canonical);
  const event=aliased[0];assert.equal(all(q,'get_evidence',{...common,change_id:event.change_id,from:event.from_occurrence,to:event.to_occurrence,max_output_tokens:2048,limit:1}).length,2);
  r.engine_version='0.3.0-native.lineage.44';const historical=q.changeSet({...common,mode:'range_net',from:a.revision_id,to:c.revision_id})[0],oldPreimage={...historical,report_id:'',change_id:'',evidence_uri:''};assert.equal(historical.change_id,id('net',[r.report_id,a.revision_id,c.revision_id,0,oldPreimage]));
  assert.notEqual(historical.change_id,q.changeSet({...common,mode:'range_net',from:a.revision_occurrence_id,to:c.revision_occurrence_id})[0].change_id);assert.equal(all(q,'get_evidence',{...common,change_id:historical.change_id,from:historical.from_occurrence,to:historical.to_occurrence,max_output_tokens:2048,limit:1}).length,2);
  const repeated={...r,engine_version:ENGINE_VERSION,revisions:[a,{...b,revision_id:a.revision_id},c]},qr=new QueryService({} as Store,new Set([r.project_id]),()=>repeated);const distinct=qr.changeSet({...common,mode:'range_net',from:b.revision_occurrence_id,to:c.revision_occurrence_id});assert.equal(distinct[0].from_occurrence,b.revision_occurrence_id,'Repeated immutable assets still resolve explicit occurrences');
});
