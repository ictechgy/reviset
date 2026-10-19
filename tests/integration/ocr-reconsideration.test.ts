import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile,mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {OcrReconsideration,Page,Report,ENGINE_VERSION,SCHEMA_VERSION,SCHEMA_HASH,comparisonText,type ElementData,type PageData,type OcrReconsiderationData,type ReportData} from '../../packages/schema/index.js';
import {admitReconsideration} from '../../packages/ingest/ocr-reconsideration.js';
import {selectHybridComparison} from '../../packages/ingest/comparison-selection.js';
import {supplementPdfOcr,type NativePageResult} from '../../packages/ingest/ocr.js';
import {Store} from '../../packages/storage/index.js';
import {QueryService} from '../../packages/query/index.js';
import {exportReport} from '../../packages/export/index.js';
const bbox=[.1,.2,.3,.05] as [number,number,number,number];
function observation(text='Pineapple'):OcrReconsiderationData{return {status:'available',band_bbox:bbox,ink_pixels:2000,threshold:135,contexts:[.25,.75].flatMap(padding=>[1,2].flatMap(scale=>[['en-US'],['ko-KR','en-US']].map(languages=>({padding,scale,languages,crop_bbox:[.08,.18,.34,.09],status:'available',observations:[{text,confidence:1,bbox,token_bboxes:[bbox],alternatives:[{text,confidence:1}],ink_coverage:1}]}))))} as OcrReconsiderationData;}
function primary(text='Pineapple옓'):ElementData{return {observation_id:'primary',kind:'text',text,normalized_text:text,bbox,reading_order:0,availability:'available',method:'vision_ocr',source_ref:'page:1/raster/ocr:0',provenance:'inferred',visibility:'uncertain',ocr:{confidence:.3,confidence_scope:'line',numeric_consensus:true,ambiguous:false,alternatives:[{text,confidence:.3,truncated:false}],reconsideration_observation:observation()}};}
function derived(p:ElementData):ElementData{const data=p.ocr!.reconsideration_observation!,r=admitReconsideration(p,data,()=>false)!;assert.ok(r);return {...p,observation_id:'derived',source_ref:'page:1/raster/roi:0',text:r.text,normalized_text:r.text,bbox:r.bbox,visibility:'visible',reading_order:1,ocr:{confidence:r.confidence,confidence_scope:'line',numeric_consensus:true,ambiguous:false,alternatives:r.alternatives,reconsideration:{method:'vision_multicontext_roi',primary_source_ref:p.source_ref,primary_text:p.text,primary_confidence:p.ocr!.confidence,primary_bbox:p.bbox,observation:data}}};}
function page(elements:ElementData[]):PageData{return {page_id:'page_a',asset_id:'asset_a',page:1,width:960,height:540,coordinate_system:'normalized',source_transform:[],hidden:null,text:'',elements,notes:null,capabilities:{text:'available',notes:'unavailable',hidden_slides:'unavailable',animation:'unavailable',structure:'unavailable',preview:'available'},coverage_gaps:[],ocr:{status:'available',engine:'fixture',environment:'fixture',width:1920,height:1080}};}
test('ROI admission requires eight distinct complete contexts and preserves numeric, script, punctuation and ink vetoes',()=>{
  const p=primary();assert.equal(admitReconsideration(p,observation(),()=>false)?.text,'Pineapple');
  const reject=(change:(d:OcrReconsiderationData)=>void)=>{const d=observation();change(d);assert.equal(admitReconsideration(p,d,()=>false),undefined);};
  for(const status of ['edge_cut','failed','contaminated','ambiguous','not_detected','budget_exceeded'] as const)reject(d=>{d.contexts[0].status=status;});
  reject(d=>{d.contexts[0]=structuredClone(d.contexts[1]);});reject(d=>{d.contexts.pop();});reject(d=>{d.contexts[0].observations[0].ink_coverage=.999;});reject(d=>{d.contexts[0].observations[0].token_bboxes=[];});reject(d=>{d.contexts[0].observations[0].bbox=[.7,.7,.1,.1];});reject(d=>{d.contexts[0].observations[0].text='Pineapple옓';});reject(d=>{d.contexts[0].observations[0].alternatives.push({text:'Pineapple한',confidence:.9});});reject(d=>{d.status='unsupported_background';});
  for(const [before,after]of [['Code F00','Code Foo'],['Invoice 123','Invoice 128'],['A · C','A • C'],['A • C','A · C'],['Hello','Heo'],['Pineapple','Pineapple!']]){const q=primary(before),d=observation(after);assert.equal(admitReconsideration(q,d,()=>false),undefined,before+' -> '+after);}
  const numeric=primary();numeric.ocr!.numeric_consensus=false;assert.equal(admitReconsideration(numeric,observation(),()=>false),undefined);
  const struck=primary();struck.visibility='struck_inferred';assert.equal(admitReconsideration(struck,observation(),()=>false),undefined);
  assert.equal(admitReconsideration(p,observation(),b=>b[0]<.1),undefined,'Annotation in crop padding must veto');
  const genuine=observation('Pineapple한');genuine.contexts[1].observations[0].text='Pineapple한글';assert.equal(admitReconsideration(primary('Pineapple한글'),genuine,()=>false),undefined,'A Korean-capable dissent must retain genuine trailing Hangul');
  assert.ok(!OcrReconsideration.safeParse({...observation(),contexts:Array(9).fill(observation().contexts[0])}).success);
});
test('ROI selection validates local primary relationship, geometry and duplicate claims without touching source visibility',()=>{
  const p=primary(),d=derived(p),source:ElementData={...primary('Pineapple'),observation_id:'source',method:'pdf_text',provenance:'observed',source_ref:'source',visibility:'unverified',ocr:undefined};
  const pg=page([source,p,d]),original=structuredClone(p);selectHybridComparison(pg);assert.equal(d.comparison_role,'selected');assert.equal(p.comparison_role,'shadowed');assert.equal(comparisonText(pg),'Pineapple');assert.equal(source.visibility,'unverified');assert.deepEqual(p.ocr,original.ocr);assert.equal(p.text,original.text);
  for(const mutation of [(q:PageData)=>{q.ocr!.width=100;},(q:PageData)=>{q.elements[1].text='Other';},(q:PageData)=>{q.elements.push({...structuredClone(q.elements[2]),observation_id:'duplicate'});},(q:PageData)=>{q.elements[1].ocr!.reconsideration_observation!.contexts[0].status='failed';}]){const q=page([structuredClone(source),primary()]);q.elements.push(derived(q.elements[1]));mutation(q);selectHybridComparison(q);assert.equal(q.elements[2].comparison_role,'unresolved');assert.notEqual(q.elements[1].comparison_role,'shadowed');}
  const blocked=page([primary()]);blocked.elements.push(derived(blocked.elements[0]),{...source,observation_id:'strike',text:'struck',visibility:'struck_inferred',bbox:[.081,.181,.01,.01]});selectHybridComparison(blocked);assert.equal(blocked.elements[1].comparison_role,'unresolved');assert.notEqual(blocked.elements[0].comparison_role,'shadowed');
});
test('ROI native supplementation keeps primary projections exact and canonical evidence query/export bounded',async()=>{
  const p=primary(),data=observation(),line={text:p.text,confidence:p.ocr!.confidence,bbox,strike_candidate:false,strike_status:'not_detected',strike_bbox:[0,0,0,0] as [number,number,number,number],numeric_consensus:true,numeric_readings:[],tokens:[{text:p.text,bbox}],alternatives:[{text:p.text,confidence:.3}],reconsideration:data};
  const result={version:'fixture',revision:3,languages:['ko-KR','en-US'],language_correction:false,ocr_performed:true,renderer:'fixture',verification:'fixture',viewport_width:960,viewport_height:540,rotation:0,width:1920,height:1080,render_sha256:'a'.repeat(64),lines:[line]} as NativePageResult;
  const pg=page([]);await supplementPdfOcr(pg,new Uint8Array(),{nativeResult:result});Page.parse(pg);assert.equal(pg.ocr_text,'');assert.equal(pg.ocr_unresolved_text,p.text);assert.equal(comparisonText(pg),'Pineapple');assert.equal(pg.elements.length,2);assert.equal(pg.elements[0].text,p.text);assert.equal(pg.elements[0].ocr!.confidence,.3);
  const r:ReportData={schema_version:SCHEMA_VERSION,engine_version:ENGINE_VERSION,report_id:'report_roi',project_id:'project_roi',timeline_revision_id:'timeline_roi',mapping_revision_id:'mapping_roi',schema_hash:SCHEMA_HASH,observation_environment:{},revisions:[{revision_id:'revision_roi',revision_occurrence_id:'occurrence_roi',label:'ROI',assets:[{asset_id:pg.asset_id,format:'pdf',bytes:0}],status:'success',pages:[pg],coverage_gaps:[],errors:[],bundle_mapping:[]}],matches:[],candidates:[],mapping_decisions:[],lineages:[],changes:[],coverage_gaps:[]};Report.parse(r);
  const folder=await mkdtemp(join(tmpdir(),'docver-roi-contract-'));let store=new Store(folder);
  try{
    const run=store.beginRun(r.project_id,'ROI contract');store.finishRun(run,r);store.close();store=new Store(folder);
    assert.deepEqual(store.report(r.project_id,r.report_id),JSON.parse(JSON.stringify(r)));assert.deepEqual(store.nativePage(r.project_id,r.report_id,pg.page_id).page,JSON.parse(JSON.stringify(pg)));
    const q=new QueryService(store,new Set([r.project_id]));
    const args={project_id:r.project_id,report_id:r.report_id,observation_id:pg.elements[1].observation_id,max_output_tokens:8000};
    const summary=q.query('get_element',args).items[0] as any;assert.equal(summary.ocr.reconsideration.context_count,8);assert.equal(summary.ocr.reconsideration.observation,undefined);assert.equal(summary.ocr_context,undefined);
    for(let i=0;i<8;i++){const item=q.query('get_element',{...args,ocr_context_index:i}).items[0] as any;assert.deepEqual(item.ocr_context.observations,data.contexts[i].observations);assert.equal(item.ocr_context.next_index,i===7?null:i+1);}
    const evidence=q.query('get_evidence',args).items[0] as any;assert.equal(evidence.ocr.reconsideration.primary_text,p.text);
    await exportReport(q,r.project_id,r.report_id,join(folder,'export'));assert.deepEqual(Report.parse(JSON.parse(await readFile(join(folder,'export','report.json'),'utf8'))),JSON.parse(JSON.stringify(r)));
  }finally{store.close();await rm(folder,{recursive:true,force:true});}
});
