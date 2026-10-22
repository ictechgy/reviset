import {test} from 'node:test';
import assert from 'node:assert/strict';
import {diffRevisions} from '../../packages/diff/index.js';
import {diffRevisions as legacy53Diff} from '../../packages/diff/legacy-bundle-53.js';
import {rangeLineage} from '../../packages/matching/lineage.js';
import {matchPages} from '../../packages/matching/index.js';
import {QueryService} from '../../packages/query/index.js';
import {Store} from '../../packages/storage/index.js';
import {ENGINE_VERSION,SCHEMA_VERSION,SCHEMA_HASH,Report,id,type PageData,type ElementData,type RevisionData,type MatchData,type ReportData} from '../../packages/schema/index.js';
function page(key:string,text:string,ocr=false):PageData {
  const body:ElementData={observation_id:key+'_body',kind:'text',text,normalized_text:text,bbox:[.1,.3,.75,.05],reading_order:1,availability:'available',method:ocr?'vision_ocr':'pdf_text',source_ref:key,provenance:ocr?'inferred':'observed',visibility:'visible',comparison_role:'selected',comparison_order:1};
  return {page_id:key,asset_id:key,page:1,width:960,height:540,coordinate_system:'normalized',source_transform:[],hidden:null,text:ocr?'':text,visible_text:text,unresolved_text:'Unreadable title',comparison_basis:'hybrid_regions_v1',elements:[{...body,observation_id:key+'_header',text:'Unreadable title',normalized_text:'Unreadable title',bbox:[.1,.02,.3,.03],reading_order:0,comparison_order:0,visibility:'uncertain',comparison_role:'unresolved'},body],notes:null,capabilities:{text:'available',notes:'unavailable',hidden_slides:'unavailable',animation:'unavailable',structure:'unavailable',preview:'available'},coverage_gaps:[]};
}
const revision=(p:PageData,key:string,format:'pdf'|'pptx'='pdf'):RevisionData=>({revision_id:'rev_'+key,revision_occurrence_id:'occ_'+key,label:key,assets:[{asset_id:p.asset_id,format,bytes:0}],status:'success',pages:[p],coverage_gaps:[],errors:[],bundle_mapping:[]});
const match=(a:PageData,b:PageData,status:MatchData['status']='inferred'):MatchData=>({from_page_id:a.page_id,to_page_id:b.page_id,score:.85,status,reasons:['synthetic page association']});
const changes=(a:PageData,b:PageData,status:MatchData['status']='inferred',format:'pdf'|'pptx'='pdf')=>diffRevisions(revision(a,'a',format),revision(b,'b',format),[match(a,b,status)],[],()=> 'family');

test('overlapping unrelated PDF source statements remain evidence, not regional replacements',()=>{
  const a=page('a','Preliminary estimates cannot establish compliance with official reporting requirements'),b=page('b','Industrial emissions are attributed to generating stations and commercial activity');
  const raw=JSON.stringify([a,b]),result=changes(a,b),gap=result.find(c=>c.coverage_gaps.some(g=>g.reason==='pdf_region_correspondence_without_text_anchor'))!;
  assert.ok(gap);assert.deepEqual([gap.before,gap.after],[a.text,b.text]);assert.deepEqual(gap.evidence.map(e=>e.observation_id),['a_body','b_body']);assert.equal(gap.lineage.status,'inferred');assert.ok(!result.some(c=>c.kind==='text_modified'));assert.equal(JSON.stringify([a,b]),raw);
  assert.ok(legacy53Diff(revision(a,'a'),revision(b,'b'),[match(a,b)],[],()=> 'family').some(c=>c.kind==='text_modified'));
  assert.ok(changes(a,b,'inferred','pptx').some(c=>c.kind==='text_modified'),'OOXML source comparison is unchanged');
});

test('regional numeric differences require both resolved page association and a literal text anchor',()=>{
  for(const status of ['human_confirmed','inferred'] as const){
    const labeled=changes(page('a','Revenue 100',true),page('b','Revenue 120',true),status).filter(c=>c.kind==='text_modified');assert.equal(labeled.length,1);assert.equal(labeled[0].region_pairing_assessment,'inferred');assert.equal(labeled[0].text_assessment,'inferred');
    const bare=changes(page('a','160',true),page('b','100',true),status);assert.ok(!bare.some(c=>c.kind==='text_modified'));assert.ok(bare.some(c=>c.coverage_gaps.some(g=>g.reason==='pdf_region_correspondence_without_text_anchor')));
    assert.equal(changes(page('a','Customer accepted'),page('b','Customer declined'),status).filter(c=>c.kind==='text_modified').length,1);
  }
  for(const values of [['160','100'],['Revenue 100','Revenue 120']]){
    const result=changes(page('a',values[0],true),page('b',values[1],true),'needs_review');assert.ok(!result.some(c=>c.kind==='text_modified'));assert.ok(result.some(c=>c.coverage_gaps.some(g=>g.reason==='pdf_region_page_correspondence_requires_review')));
  }
  assert.ok(!changes(page('a','Revenue 100'),page('b','Cost 120')).some(c=>c.kind==='text_modified'),'A changed label does not anchor its amount');
});

test('reflowed multi-number claims stay unresolved instead of forcing a numerical edit',()=>{
  const a=page('a','Total 384.2 million units, a decrease of 5.4%'),b=page('b','In 2023 the total was estimated to be 385 million units');b.elements[1].bbox=[.1,.2,.75,.05];
  const result=changes(a,b);assert.ok(!result.some(c=>c.kind==='text_modified'));assert.ok(result.some(c=>c.coverage_gaps.some(g=>g.reason==='pdf_visibility_unresolved_text_comparison_withheld')));
});

test('engine53 range events retain exact archived payload, canonical endpoint IDs and evidence lookup',()=>{
  const a=page('a','160',true),b=page('b','100',true),revisions=[revision(a,'a'),revision(b,'b')];
  const r:ReportData={schema_version:SCHEMA_VERSION,engine_version:'0.4.0-native.bundle.53',schema_hash:SCHEMA_HASH,report_id:'report53',project_id:'project',timeline_revision_id:'timeline',mapping_revision_id:'mapping',observation_environment:{},revisions,matches:[match(a,b,'needs_review')],candidates:[],mapping_decisions:[],mapping_relations:[],bundle_decisions:[],lineages:[{entity_id:'family',page_ids:['a','b'],status:'needs_review'}],changes:[],coverage_gaps:[]};
  const directed=rangeLineage(r,revisions[0],revisions[1]),expected=legacy53Diff(...revisions as [RevisionData,RevisionData],directed.matches,matchPages([a],[b]).candidates,()=> 'family',directed.structural).map((c,i)=>({...c,report_id:r.report_id,change_id:id('net',[r.report_id,'occ_a','occ_b',i,c]),evidence_uri:`docver://projects/${r.project_id}/reports/${r.report_id}/manifest`}));
  r.changes=expected;Report.parse(r);const frozen=JSON.stringify(r),q=new QueryService({} as Store,new Set([r.project_id]),()=>r),base={project_id:r.project_id,report_id:r.report_id,max_output_tokens:8000};
  for(const selectors of [['rev_a','rev_b'],['occ_a','occ_b']]){
    const args={...base,from:selectors[0],to:selectors[1],mode:'range_net'},result=q.changeSet(args);assert.deepEqual(result,expected);
    const modified=expected.find(c=>c.kind==='text_modified')!;assert.ok(modified);const evidence=q.query('get_evidence',{...base,from:selectors[0],to:selectors[1],change_id:modified.change_id});assert.deepEqual(evidence.items.map(e=>e.quote),['160','100']);
    const changed={...r,engine_version:ENGINE_VERSION};const current=new QueryService({} as Store,new Set([r.project_id]),()=>changed);assert.ok(!current.changeSet(args).some(c=>c.kind==='text_modified'));assert.deepEqual(current.changeSet({...base,mode:'history'}),expected,'Stored history is not rederived');
  }
  assert.equal(JSON.stringify(r),frozen);
});
