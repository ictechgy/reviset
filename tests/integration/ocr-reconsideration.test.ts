import {test} from 'node:test';
import {execFileSync} from 'node:child_process';
import {writeFile} from 'node:fs/promises';
import {Client} from '@modelcontextprotocol/sdk/client/index.js';
import {StdioClientTransport} from '@modelcontextprotocol/sdk/client/stdio.js';
import assert from 'node:assert/strict';
import {readFile,mkdtemp,rm,mkdir} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {OcrReconsideration,Page,Report,ENGINE_VERSION,SCHEMA_VERSION,SCHEMA_HASH,comparisonText,unresolvedComparisonText,type ElementData,type PageData,type OcrReconsiderationData,type ReportData} from '../../packages/schema/index.js';
import {admitReconsideration,hasContextualDisagreement,contextualAssessment} from '../../packages/ingest/ocr-reconsideration.js';
import {selectHybridComparison} from '../../packages/ingest/comparison-selection.js';
import {supplementPdfOcr,type NativePageResult} from '../../packages/ingest/ocr.js';
import {Store} from '../../packages/storage/index.js';
import {QueryService} from '../../packages/query/index.js';
import {exportReport} from '../../packages/export/index.js';
import PDFDocument from 'pdfkit';
const bbox=[.1,.2,.3,.05] as [number,number,number,number];
function observation(text='Pineapple'):OcrReconsiderationData{return {status:'available',band_bbox:bbox,primary_empty_characters:[{offset:9,text:'옓',bbox:[.39,.2,.01,.05],ink_pixels:0,method:'uniform_white_pixels_with_1px_margin'}],ink_pixels:2000,threshold:135,contexts:[.25,.75].flatMap(padding=>[1,2].flatMap(scale=>[['en-US'],['ko-KR','en-US']].map(languages=>({padding,scale,languages,crop_bbox:[.08,.18,.34,.09],status:'available',observations:[{text,confidence:1,bbox,token_bboxes:[bbox],alternatives:[{text,confidence:1}],ink_coverage:1}]}))))} as OcrReconsiderationData;}
function primary(text='Pineapple옓'):ElementData{return {observation_id:'primary',kind:'text',text,normalized_text:text,bbox,reading_order:0,availability:'available',method:'vision_ocr',source_ref:'page:1/raster/ocr:0',provenance:'inferred',visibility:'uncertain',ocr:{confidence:.3,confidence_scope:'line',strike_status:'not_detected',numeric_consensus:true,ambiguous:false,alternatives:[{text,confidence:.3,truncated:false}],reconsideration_observation:observation()}};}
function derived(p:ElementData):ElementData{const data=p.ocr!.reconsideration_observation!,r=admitReconsideration(p,data,()=>false)!;assert.ok(r);return {...p,observation_id:'derived',source_ref:'page:1/raster/roi:0',text:r.text,normalized_text:r.text,bbox:r.bbox,visibility:'visible',reading_order:1,ocr:{confidence:r.confidence,confidence_scope:'line',strike_status:'not_detected',numeric_consensus:true,ambiguous:false,alternatives:r.alternatives,reconsideration:{method:'vision_multicontext_roi',primary_source_ref:p.source_ref,primary_text:p.text,primary_confidence:p.ocr!.confidence,primary_bbox:p.bbox,observation:data}}};}
function page(elements:ElementData[]):PageData{return {page_id:'page_a',asset_id:'asset_a',page:1,width:960,height:540,coordinate_system:'normalized',source_transform:[],hidden:null,text:'',elements,notes:null,capabilities:{text:'available',notes:'unavailable',hidden_slides:'unavailable',animation:'unavailable',structure:'unavailable',preview:'available'},coverage_gaps:[],ocr:{status:'available',engine:'fixture',environment:'fixture',width:1920,height:1080}};}
test('supported-language contextual disagreement withholds borderline comparison while preserving primary projections and source priority',()=>{
  const p=primary('Pineapple 주스');p.visibility='visible';p.ocr!.confidence=.5;p.ocr!.reconsideration_observation=observation(p.text);
  for(const context of p.ocr!.reconsideration_observation!.contexts){context.observations[0].text=context.languages.length===1?'Pineapple FA':p.text;}
  assert.equal(hasContextualDisagreement(p,()=>false),false,'English-only crops cannot veto mixed Hangul');
  const changed=p.ocr!.reconsideration_observation!.contexts[7];changed.observations[0].text='Pineapple 무스';changed.observations[0].ink_coverage=.8;
  assert.equal(hasContextualDisagreement(p,()=>false),true,'Positive overlapping counterevidence can retain uncertainty without proving replacement text');
  const original=structuredClone(p),pg=page([p]);pg.ocr_text=p.text;selectHybridComparison(pg);Page.parse(pg);
  assert.equal(comparisonText(pg),'');assert.equal(unresolvedComparisonText(pg),p.text);assert.equal(p.comparison_reason,'contextual_ocr_disagreement_primary_retained');assert.deepEqual(p.ocr,original.ocr);assert.equal(p.text,original.text);assert.equal(p.visibility,'visible');assert.equal(pg.ocr_text,p.text);
  for(const status of ['failed','edge_cut','not_detected','budget_exceeded','contaminated','ambiguous'] as const){const q=structuredClone(p);q.ocr!.reconsideration_observation!.contexts[7].status=status;assert.equal(hasContextualDisagreement(q,()=>false),false);}
  for(const mutate of [(q:ElementData)=>{q.ocr!.confidence=1;},(q:ElementData)=>{q.ocr!.reconsideration_observation!.band_bbox=[.6,.6,.2,.1];},(q:ElementData)=>{q.ocr!.reconsideration_observation!.contexts[7].observations[0].bbox=[.7,.7,.1,.1];},(q:ElementData)=>{q.ocr!.reconsideration_observation!.contexts[7].observations[0].confidence=.3;},(q:ElementData)=>{q.ocr!.reconsideration_observation!.contexts[7].observations[0].ink_coverage=0;},(q:ElementData)=>{q.ocr!.reconsideration_observation!.contexts[7].observations[0].token_bboxes=[];},(q:ElementData)=>{q.ocr!.reconsideration_observation!.contexts[7]=q.ocr!.reconsideration_observation!.contexts[0];}]){const q=structuredClone(p);mutate(q);assert.equal(hasContextualDisagreement(q,()=>false),false);}
  assert.equal(hasContextualDisagreement(p,b=>b[0]<.1),false,'Blocked padding cannot supply comparable context');
  const source:ElementData={...structuredClone(p),observation_id:'source',method:'pdf_text',provenance:'observed',source_ref:'source',ocr:undefined};const sourcePage=page([source,structuredClone(p)]);selectHybridComparison(sourcePage);assert.equal(sourcePage.elements[0].comparison_role,'selected');assert.equal(sourcePage.elements[1].comparison_role,'shadowed');assert.equal(comparisonText(sourcePage),source.text);
});
test('missing or unusable borderline context evidence withholds selection without changing primary or numeric/source priority',()=>{
  for(const status of ['unsupported_background','unsupported_bitmap','budget_exceeded','failed','empty_ink',undefined] as const){
    const p=primary('계익 기간 변경');p.visibility='visible';p.ocr!.confidence=.5;p.ocr!.reconsideration_observation=status?{status,band_bbox:bbox,contexts:[]}:undefined;
    const original=structuredClone(p),pg=page([p]);pg.ocr_text=p.text;assert.equal(contextualAssessment(p,()=>false),'unverified');selectHybridComparison(pg);Page.parse(pg);
    assert.equal(comparisonText(pg),'');assert.equal(unresolvedComparisonText(pg),p.text);assert.equal(p.comparison_reason,'borderline_ocr_context_unverified_primary_retained');assert.deepEqual(p.ocr,original.ocr);assert.equal(p.visibility,original.visibility);assert.equal(pg.ocr_text,p.text);assert.ok(pg.coverage_gaps.some(g=>g.reason===p.comparison_reason));
    const source:ElementData={...structuredClone(p),observation_id:'source',method:'pdf_text',provenance:'observed',source_ref:'source',ocr:undefined};const sourcePage=page([source,structuredClone(p)]);selectHybridComparison(sourcePage);assert.equal(comparisonText(sourcePage),source.text);assert.equal(sourcePage.elements[1].comparison_role,'shadowed');
    const numeric=structuredClone(p);numeric.text='Amount 100';assert.equal(contextualAssessment(numeric,()=>false),'not_applicable');
    const confident=structuredClone(p);confident.ocr!.confidence=1;assert.equal(contextualAssessment(confident,()=>false),'not_applicable','High-score independent-model qualification remains a separate open task');
  }
});
test('high-score Latin counterevidence only withholds and preserves primary, source and unsupported-scope behavior',()=>{
  const p=primary('Revised dellivery date');p.visibility='visible';p.ocr!.confidence=1;p.ocr!.alternatives=[{text:p.text,confidence:1,truncated:false}];
  p.ocr!.reconsideration_observation=observation('Revised delivery date');p.ocr!.reconsideration_observation.contexts=p.ocr!.reconsideration_observation.contexts.filter(c=>c.padding===.75&&c.languages.join(',')==='en-US');
  const before=structuredClone(p),pg=page([p]);pg.ocr_text=p.text;assert.equal(contextualAssessment(p,()=>false),'disagrees');assert.equal(admitReconsideration(p,p.ocr!.reconsideration_observation!,()=>false),undefined,'Counterevidence cannot authorize correction');
  selectHybridComparison(pg);Page.parse(pg);assert.equal(comparisonText(pg),'');assert.equal(unresolvedComparisonText(pg),p.text);assert.equal(p.comparison_reason,'contextual_ocr_disagreement_primary_retained');assert.deepEqual(p.ocr,before.ocr);assert.equal(p.visibility,before.visibility);assert.equal(pg.ocr_text,p.text);
  const q=structuredClone(before);q.ocr!.reconsideration_observation!.contexts[0].status='failed';assert.equal(contextualAssessment(q,()=>false),'disagrees','A single valid counterreading retains uncertainty');
  for(const mutate of [(q:ElementData)=>{q.ocr!.reconsideration_observation=undefined;},(q:ElementData)=>{q.ocr!.reconsideration_observation!.status='budget_exceeded';},(q:ElementData)=>{q.ocr!.reconsideration_observation!.contexts.forEach(c=>c.status='edge_cut');},(q:ElementData)=>{q.ocr!.reconsideration_observation!.contexts.forEach(c=>c.languages=['ko-KR','en-US']);},(q:ElementData)=>{q.ocr!.reconsideration_observation!.contexts.forEach(c=>c.padding=.25);},(q:ElementData)=>{q.ocr!.reconsideration_observation!.band_bbox=[.6,.6,.2,.1];},(q:ElementData)=>{q.ocr!.reconsideration_observation!.contexts.push(q.ocr!.reconsideration_observation!.contexts[0]);}]){
    const q=structuredClone(before);mutate(q);assert.equal(contextualAssessment(q,()=>false),'not_applicable');const unverified=page([q]);selectHybridComparison(unverified);assert.equal(q.comparison_role,'selected','No high-score missing-context agreement or automatic blanket veto is introduced');
  }
  for(const text of ['Delivery 100','Delivery 변경','Delivery Δ']){const q=structuredClone(before);q.text=text;assert.equal(contextualAssessment(q,()=>false),'not_applicable');}
  const blocked=structuredClone(before);assert.equal(contextualAssessment(blocked,()=>true),'not_applicable');
  const source:ElementData={...structuredClone(before),observation_id:'source',method:'pdf_text',provenance:'observed',source_ref:'source',ocr:undefined};const sourcePage=page([source,structuredClone(before)]);selectHybridComparison(sourcePage);assert.equal(sourcePage.elements[0].comparison_role,'selected');assert.equal(sourcePage.elements[1].comparison_role,'shadowed');
  const same=structuredClone(before);same.ocr!.reconsideration_observation=observation(same.text);assert.equal(contextualAssessment(same,()=>false),'consistent');
});
test('ROI admission requires eight distinct complete contexts and preserves numeric, script, punctuation and ink vetoes',()=>{
  const p=primary();assert.equal(admitReconsideration(p,observation(),()=>false)?.text,'Pineapple');
  const reject=(change:(d:OcrReconsiderationData)=>void)=>{const d=observation();change(d);assert.equal(admitReconsideration(p,d,()=>false),undefined);};
  for(const status of ['edge_cut','failed','contaminated','ambiguous','not_detected','budget_exceeded'] as const)reject(d=>{d.contexts[0].status=status;});
  reject(d=>{d.contexts[0]=structuredClone(d.contexts[1]);});reject(d=>{d.contexts.pop();});reject(d=>{d.contexts[0].observations[0].ink_coverage=.999;});reject(d=>{d.contexts[0].observations[0].token_bboxes=[];});reject(d=>{d.contexts[0].observations[0].bbox=[.7,.7,.1,.1];});reject(d=>{d.contexts[0].observations[0].text='Pineapple옓';});reject(d=>{d.contexts[0].observations[0].alternatives.push({text:'Pineapple한',confidence:.9});});reject(d=>{d.status='unsupported_background';});reject(d=>{d.primary_empty_characters=[];});reject(d=>{d.primary_empty_characters![0].offset=8;});reject(d=>{d.primary_empty_characters![0].bbox=[.8,.8,.01,.01];});
  for(const [before,after]of [['Code F00','Code Foo'],['Invoice 123','Invoice 128'],['A · C','A • C'],['A • C','A · C'],['Hello','Heo'],['Pineapple','Pineapple!'],['Pineapple Juice','Pineapple'],['Pineapple 주스','Pineapple'],['Pineapple한글','Pineapple'],['modern','modem']]){const q=primary(before),d=observation(after);assert.equal(admitReconsideration(q,d,()=>false),undefined,before+' -> '+after);}
  for(const space of [' ','\t','\u00a0','\n']){
    const before='Pineapple'+space+'옓',d=observation('Pine apple');d.primary_empty_characters![0].offset=10;
    assert.equal(admitReconsideration(primary(before),d,()=>false),undefined,'A certified one-scalar token cannot disappear while another word splits');
  }
  const certified=observation('Pine applex');certified.primary_empty_characters![0].offset=10;
  assert.equal(admitReconsideration(primary('Pineapple 옓x'),certified,()=>false),undefined,'A certified partial-token deletion cannot relocate boundaries');
  assert.equal(admitReconsideration(primary('Cat dog'),observation('Ca tdoq'),()=>false),undefined,'A substitution cannot relocate boundaries either');
  const aligned=observation('Pineapple x');aligned.primary_empty_characters![0].offset=10;
  assert.equal(admitReconsideration(primary('Pineapple 옓x'),aligned,()=>false)?.text,'Pineapple x','The same certified deletion in its original aligned token remains admissible');
  for(const [before,after,character,correct,wrong]of [['ab bc','ab c','b',3,1],['a옓 옓x','a옓 x','옓',3,1]] as const){
    const d=observation(after);d.primary_empty_characters![0]={...d.primary_empty_characters![0],offset:correct,text:character};
    assert.equal(admitReconsideration(primary(before),d,()=>false)?.text,after,'A repeated scalar deletion belongs to the changed token');
    d.primary_empty_characters![0].offset=wrong;assert.equal(admitReconsideration(primary(before),d,()=>false),undefined,'A certificate in an unchanged token cannot authorize deletion');
  }
  reject(d=>{d.contexts[0].observations[0].text='Pine apple';d.contexts[0].observations[0].alternatives=[];});
  const numeric=primary();numeric.ocr!.numeric_consensus=false;assert.equal(admitReconsideration(numeric,observation(),()=>false),undefined);
  const unevaluated=primary();unevaluated.ocr!.strike_status='unsupported_bitmap';assert.equal(admitReconsideration(unevaluated,observation(),()=>false),undefined);
  const struck=primary();struck.visibility='struck_inferred';assert.equal(admitReconsideration(struck,observation(),()=>false),undefined);
  assert.equal(admitReconsideration(p,observation(),b=>b[0]<.1),undefined,'Annotation in crop padding must veto');
  const genuine=observation('Pineapple한');genuine.contexts[1].observations[0].text='Pineapple한글';assert.equal(admitReconsideration(primary('Pineapple한글'),genuine,()=>false),undefined,'A Korean-capable dissent must retain genuine trailing Hangul');
  assert.ok(!OcrReconsideration.safeParse({...observation(),contexts:Array(9).fill(observation().contexts[0])}).success);
});
test('ROI selection validates local primary relationship, geometry and duplicate claims without touching source visibility',()=>{
  const p=primary(),d=derived(p),source:ElementData={...primary('Pineapple'),observation_id:'source',method:'pdf_text',provenance:'observed',source_ref:'source',visibility:'unverified',ocr:undefined};
  const pg=page([source,p,d]),original=structuredClone(p);selectHybridComparison(pg);assert.equal(d.comparison_role,'selected');assert.equal(p.comparison_role,'shadowed');assert.equal(comparisonText(pg),'Pineapple');assert.equal(source.visibility,'unverified');assert.deepEqual(p.ocr,original.ocr);assert.equal(p.text,original.text);
  assert.ok(!pg.coverage_gaps.some(g=>g.reason==='contextual_ocr_disagreement_primary_retained'),'Admitted context must not retain a contradictory withholding diagnostic');
  const q=primary('Another reading');q.observation_id='other';q.source_ref='page:1/raster/ocr:1';const shift=(b:[number,number,number,number]):[number,number,number,number]=>[b[0],b[1]+.4,b[2],b[3]];q.bbox=shift(q.bbox);const support=q.ocr!.reconsideration_observation!;support.band_bbox=shift(support.band_bbox);for(const c of support.contexts){c.crop_bbox=shift(c.crop_bbox);for(const r of c.observations){r.bbox=shift(r.bbox);r.token_bboxes=r.token_bboxes.map(shift);}}
  const mixed=page([primary()]);mixed.elements.push(derived(mixed.elements[0]),q);selectHybridComparison(mixed);assert.equal(mixed.elements[0].comparison_role,'shadowed');assert.equal(q.comparison_role,'unresolved');assert.equal(q.comparison_reason,'contextual_ocr_disagreement_primary_retained');assert.equal(mixed.coverage_gaps.filter(g=>g.reason===q.comparison_reason).length,1,'A valid correction cannot erase a separate unresolved region');mixed.elements.pop();selectHybridComparison(mixed);assert.ok(!mixed.coverage_gaps.some(g=>g.reason==='contextual_ocr_disagreement_primary_retained'),'Reselection derives diagnostics from final participating roles');
  for(const mutation of [(q:PageData)=>{q.ocr!.width=100;},(q:PageData)=>{q.elements[1].text='Other';},(q:PageData)=>{q.elements.push({...structuredClone(q.elements[2]),observation_id:'duplicate'});},(q:PageData)=>{q.elements[1].ocr!.reconsideration_observation!.contexts[0].status='failed';}]){const q=page([structuredClone(source),primary()]);q.elements.push(derived(q.elements[1]));mutation(q);selectHybridComparison(q);assert.equal(q.elements[2].comparison_role,'excluded');assert.notEqual(q.elements[1].comparison_role,'shadowed');}
  const blocked=page([primary()]);blocked.elements.push(derived(blocked.elements[0]),{...source,observation_id:'strike',text:'struck',visibility:'struck_inferred',bbox:[.081,.181,.01,.01]});selectHybridComparison(blocked);assert.equal(blocked.elements[1].comparison_role,'excluded');assert.notEqual(blocked.elements[0].comparison_role,'shadowed');assert.deepEqual(unresolvedComparisonText(blocked).split('\n').sort(),[blocked.elements[0].text,'struck'].sort());
});
test('ROI native supplementation keeps primary projections exact and canonical evidence query/export bounded',async()=>{
  const p=primary(),data=observation(),line={text:p.text,confidence:p.ocr!.confidence,bbox,strike_candidate:false,strike_status:'not_detected',strike_bbox:[0,0,0,0] as [number,number,number,number],numeric_consensus:true,numeric_readings:[],tokens:[{text:p.text,bbox}],alternatives:[{text:p.text,confidence:.3}],reconsideration:data,reconsideration_error:undefined};
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
    for(let i=0;i<8;i++){const item=q.query('get_element',{...args,ocr_context_index:i}).items[0] as any;assert.equal(item.ocr_context.reading.text,data.contexts[i].observations[0].text);assert.deepEqual(item.ocr_context.reading.token_bboxes,data.contexts[i].observations[0].token_bboxes);assert.equal(item.ocr_context.next_index,i===7?null:i+1);}
    const empty=q.query('get_element',{...args,ocr_empty_character_index:0}).items[0] as any;assert.equal(empty.ocr_empty_character.text,'옓');assert.equal(empty.ocr_empty_character.ink_pixels,0);
    const evidence=q.query('get_evidence',args).items[0] as any;assert.equal(evidence.ocr.reconsideration.primary_text,p.text);
    await exportReport(q,r.project_id,r.report_id,join(folder,'export'));assert.deepEqual(Report.parse(JSON.parse(await readFile(join(folder,'export','report.json'),'utf8'))),JSON.parse(JSON.stringify(r)));
  }finally{store.close();await rm(folder,{recursive:true,force:true});}
});

test('invalid optional ROI and table annexes preserve primary OCR, independent tables and cached diagnostics',async()=>{
  const folder=await mkdtemp(join(tmpdir(),'docver-roi-fault-'));
  try{
    const document=new PDFDocument({size:[960,540],margin:0}),chunks:Buffer[]=[];
    const complete=new Promise<Buffer>((resolve,reject)=>{document.on('data',chunk=>chunks.push(chunk));document.on('end',()=>resolve(Buffer.concat(chunks)));document.on('error',reject);});
    for(let n=0;n<3;n++){if(n)document.addPage();document.text('Mandatory OCR failure diagnostic page '+(n+1),50,50);}document.end();
    const diagnosticPdf=join(folder,'diagnostic.pdf');await writeFile(diagnosticPdf,await complete);
    const blockedCache=join(folder,'blocked-cache'),blockedRaster=join(folder,'blocked-raster');
    await mkdir(blockedCache);await writeFile(join(blockedCache,'ocr'),'Not a directory');
    await mkdir(join(blockedRaster,'ocr'),{recursive:true});await writeFile(join(blockedRaster,'ocr','raster'),'Not a directory');
    const helper=join(folder,'fake-vision.mjs'),module=new URL('../../packages/ingest/ocr.ts',import.meta.url).href;
    const line={text:'Primary stays exact',confidence:.3,bbox,strike_candidate:false,strike_status:'not_detected',strike_bbox:[0,0,0,0],numeric_consensus:true,numeric_readings:[],tokens:[],alternatives:[]};
    const valid={version:'roi-fault',revision:3,languages:['ko-KR','en-US'],language_correction:false,ocr_performed:true,renderer:'fixture',verification:'fixture',viewport_width:960,viewport_height:540,rotation:0,width:960,height:540,render_sha256:'a'.repeat(64),lines:[line]};
    const bad=observation();bad.contexts[0].observations[0].bbox=[-.01,0,.1,.1];
    const oversized=observation('e\u0301'.repeat(70));
    const cell={row:0,column:0,row_span:1,column_span:1,text:'table stays',text_confident:true,bbox:[.1,.65,.2,.1]},gridCell={...cell,text:'grid stays',bbox:[.6,.65,.2,.1]},badCell={...cell,bbox:[-.1,.65,.2,.1]};
    const structure={structure_status:'available',tables:[{cells:[cell]}],grid_status:'available',grid_tables:[{cells:[gridCell]}]};
    const variants={1:{...valid,lines:[{...line,reconsideration:bad}]},2:{...valid,width:0},3:{...valid,lines:[{...line,reconsideration:oversized}]},5:{...valid,...structure,tables:[{cells:[badCell]}]},6:{...valid,...structure,grid_tables:[{cells:[badCell]}]},7:{...valid,...structure,tables:null,grid_reasons:Array(21).fill('invalid')},9:{...valid,...structure,structure_metadata_errors:['document']},10:{...valid,...structure,structure_metadata_errors:['grid']},11:{...valid,...structure,structure_metadata_errors:['document','grid']},12:{...valid,ocr_performed:false}};
    await writeFile(helper,`#!${process.execPath}\nif(process.argv.includes('--info')){console.log(JSON.stringify({version:'fixture',os:'fixture',revision:3,languages:['ko-KR','en-US'],language_correction:false,font_inventory_sha256:'a'.repeat(64),font_families:[]}));}else{let input='';for await(const b of process.stdin)input+=b;const query=JSON.parse(input),valid=${JSON.stringify({...valid,...structure})},variants=${JSON.stringify(variants)};console.log(JSON.stringify({pages:query.pages.map(page=>page===13?{page,error:'fixture failure'}:{page,result:variants[page]??valid})}));}`,{mode:0o755});
    const child=`import assert from 'node:assert/strict';import {captureNativePages,recognizePdf} from ${JSON.stringify(module)};const pages=[1,2,3,4,5,6,7,8,9,10,11,12,13],options={cacheRoot:${JSON.stringify(join(folder,'cache'))},reuseRasterOcr:false};const result=await captureNativePages(new Uint8Array(),pages,pages,options),cached=await captureNativePages(new Uint8Array(),pages,pages,options);assert.deepEqual(JSON.parse(JSON.stringify([...cached])),JSON.parse(JSON.stringify([...result])));assert.equal(result.failures.get(2),'NATIVE_RESULT_SCHEMA_INVALID');assert.equal(cached.failures.get(2),'NATIVE_RESULT_SCHEMA_INVALID');assert.equal(result.failures.get(12),'NATIVE_OCR_MODE_MISMATCH');assert.equal(result.failures.get(13),'NATIVE_PAGE_HELPER_ERROR');assert.equal(result.failures.size,3);await assert.rejects(()=>recognizePdf(new Uint8Array(),2),e=>e.code==='NATIVE_RESULT_SCHEMA_INVALID');const {extractPdf}=await import(${JSON.stringify(new URL('../../packages/ingest/pdf.ts',import.meta.url).href)}),{readFile}=await import('node:fs/promises');const canonical=await extractPdf(await readFile(${JSON.stringify(diagnosticPdf)}),'sha256:fault-diagnostic',{ocr:'all'});assert.equal(canonical[1].ocr.reason,'NATIVE_RESULT_SCHEMA_INVALID');assert.ok(canonical[1].coverage_gaps.some(g=>g.reason==='NATIVE_RESULT_SCHEMA_INVALID'));assert.equal(canonical[0].ocr.status,'available');
    for(const cacheRoot of ${JSON.stringify([blockedCache,blockedRaster])}){
      const preserved=await captureNativePages(new Uint8Array(),[1,3,4],[1,3,4],{cacheRoot,reuseRasterOcr:false});
      assert.deepEqual([...preserved.keys()],[1,3,4]);assert.equal(preserved.failures.size,0);
      for(const value of preserved.values()){assert.equal(value.lines[0].text,'Primary stays exact');assert.equal(value.lines[0].confidence,.3);assert.equal(value.cache_write_failed,true);}
      const withWarning=await extractPdf(await readFile(${JSON.stringify(diagnosticPdf)}),'sha256:fault-diagnostic',{ocr:'all',cacheRoot,reuseRasterOcr:false});
      for(const index of [0,2]){assert.equal(withWarning[index].ocr.status,'available');assert.ok(withWarning[index].coverage_gaps.some(g=>g.reason==='optional_cache_write_failed_observations_retained'));}
    }
    const sourceCacheReplay=await captureNativePages(new Uint8Array(),[1,3,4],[1,3,4],{cacheRoot:${JSON.stringify(blockedRaster)},reuseRasterOcr:false});
    for(const value of sourceCacheReplay.values())assert.equal(value.cache_write_failed,undefined,'Operational warnings are not stale cached OCR evidence');
    console.log(JSON.stringify([...result]));`;
    const rows=JSON.parse(execFileSync(process.execPath,['--import','tsx','--input-type=module','-e',child],{encoding:'utf8',env:{...process.env,DOCVER_VISION:helper},timeout:15000}));
    assert.deepEqual(rows.map((r:any)=>r[0]),[1,3,4,5,6,7,8,9,10,11]);for(const [number,result]of rows){assert.equal(result.lines[0].text,line.text);if(number<4){assert.equal(result.lines[0].reconsideration,undefined);assert.equal(result.lines[0].reconsideration_error,'invalid_metadata');}}
    for(const [number,result]of rows.filter((r:any)=>r[0]>=5)){
      const p=page([]);await supplementPdfOcr(p,new Uint8Array(),{nativeResult:result});Page.parse(p);assert.equal(p.ocr?.status,'available');assert.equal(p.elements[0].text,line.text);assert.equal(p.elements[0].ocr!.confidence,line.confidence);
      const texts=p.elements.filter(e=>e.kind==='table_cell').map(e=>e.text).sort();
      assert.deepEqual(texts,[5,9].includes(number)?['grid stays']:[6,10].includes(number)?['table stays']:[7,11].includes(number)?[]:['grid stays','table stays']);
      const expected=[5,9].includes(number)?['document']:[6,10].includes(number)?['grid']:[7,11].includes(number)?['document','grid']:[];
      assert.deepEqual(result.structure_metadata_errors??[],expected);for(const annex of expected)assert.ok(p.coverage_gaps.some(g=>g.reason==='invalid_optional_'+annex+'_metadata_ignored_primary_retained'));
    }
    const p=page([]);await supplementPdfOcr(p,new Uint8Array(),{nativeResult:rows[0][1]});assert.equal(p.ocr?.status,'available');assert.equal(p.elements[0].text,line.text);assert.ok(p.coverage_gaps.some(g=>g.reason==='invalid_optional_roi_metadata_ignored_primary_retained'));
  }finally{await rm(folder,{recursive:true,force:true});}
});

test('actual MCP transport traverses retained components using their own Unicode offsets and bounded geometry',async()=>{
  const folder=await mkdtemp(join(tmpdir(),'docver-roi-mcp-')),store=new Store(folder),client=new Client({name:'roi-boundary',version:'1'});
  try{
    const data=observation('\u0001'.repeat(128)),token=[.123456789012345,.234567890123456,.009123456789012,.022345678901234] as [number,number,number,number];
    for(const context of data.contexts){context.status='contaminated';const row={...context.observations[0],token_bboxes:Array.from({length:32},()=>token),alternatives:Array.from({length:3},()=>({text:'한글 😀 '.repeat(20).slice(0,128),confidence:.8}))};context.observations=Array.from({length:8},()=>structuredClone(row));}
    // The returned context/character offset32 deliberately splits an unrelated
    // primary surrogate pair. Only the selected component may validate it.
    const p=primary('x'+'😀'.repeat(50));p.ocr!.reconsideration_observation=data;
    const emptyText='e'+'\u0301'.repeat(127);
    data.primary_empty_characters=[{offset:0,text:emptyText,bbox,ink_pixels:0,method:'uniform_white_pixels_with_1px_margin'}];
    const r:ReportData={schema_version:SCHEMA_VERSION,engine_version:ENGINE_VERSION,report_id:'report_roi_mcp',project_id:'project_roi_mcp',timeline_revision_id:'timeline',mapping_revision_id:'mapping',schema_hash:SCHEMA_HASH,observation_environment:{},revisions:[{revision_id:'revision',revision_occurrence_id:'occurrence',label:'Boundary',assets:[{asset_id:'asset_a',format:'pdf',bytes:0}],status:'success',pages:[page([p])],coverage_gaps:[],errors:[],bundle_mapping:[]}],matches:[],candidates:[],mapping_decisions:[],lineages:[],changes:[],coverage_gaps:[]};Report.parse(r);store.finishRun(store.beginRun(r.project_id,'ROI MCP'),r);
    await client.connect(new StdioClientTransport({command:process.execPath,args:['--import','tsx','apps/mcp/main.ts','--store',folder,'--project',r.project_id],stderr:'pipe'}));
    const read=async(extra:Record<string,unknown>)=>{const response=await client.callTool({name:'get_element',arguments:{project_id:r.project_id,report_id:r.report_id,observation_id:p.observation_id,ocr_context_index:0,text_length:32,ocr_alternative_length:32,max_output_tokens:8000,...extra}});assert.ok(!response.isError,JSON.stringify(response));assert.ok(Buffer.byteLength(JSON.stringify(response))<=8000);const item=(response.structuredContent as any).items[0];assert.ok(item.ocr_context?.reading,JSON.stringify(response));return item.ocr_context.reading;};
    for(let index=0;index<8;index++){
      let text='',offset:number|null=0;while(offset!==null){const reading=await read({ocr_observation_index:index,text_offset:offset});text+=reading.text;offset=reading.next_text_offset;}assert.equal(text,data.contexts[0].observations[index].text);
      for(let a=0;a<3;a++){let value='',at:number|null=0;while(at!==null){const reading=await read({ocr_observation_index:index,ocr_alternative_index:a,ocr_alternative_offset:at});value+=reading.alternative.text;at=reading.alternative.next_text_offset;}assert.equal(value,data.contexts[0].observations[index].alternatives[a].text);}
      const boxes:unknown[]=[];let next:number|null=0;while(next!==null){const reading=await read({ocr_observation_index:index,ocr_token_offset:next});boxes.push(...reading.token_bboxes);next=reading.next_token_offset;}assert.deepEqual(boxes,data.contexts[0].observations[index].token_bboxes);
    }
    let emptyValue='',offset:number|null=0;
    while(offset!==null){
      const response=await client.callTool({name:'get_element',arguments:{project_id:r.project_id,report_id:r.report_id,observation_id:p.observation_id,ocr_empty_character_index:0,text_offset:offset,text_length:32,max_output_tokens:8000}});
      assert.ok(!response.isError,JSON.stringify(response));assert.ok(Buffer.byteLength(JSON.stringify(response))<=8000);const character=(response.structuredContent as any).items[0].ocr_empty_character;
      emptyValue+=character.text;offset=character.next_text_offset;
    }
    assert.equal(emptyValue,emptyText);
    const invalidPrimary=await client.callTool({name:'get_element',arguments:{project_id:r.project_id,report_id:r.report_id,observation_id:p.observation_id,text_offset:32,max_output_tokens:8000}});
    assert.ok(invalidPrimary.isError);assert.match(JSON.stringify(invalidPrimary),/TEXT_OFFSET/,'A cursor that actually splits the selected primary must still fail');
  }finally{await client.close();store.close();await rm(folder,{recursive:true,force:true});}
});

test('entirely nonASCII Latin words share producer scope while raw text and source priority remain intact',()=>{
 for(const [before,after]of [['éé','éè'],['É','È'],['Æ','Œ'],['ø','ö']])for(const score of [.5,1]){
  const p=primary(before);p.visibility='visible';p.ocr!.confidence=score;p.ocr!.reconsideration_observation=observation(after);if(score===1)p.ocr!.reconsideration_observation.contexts=p.ocr!.reconsideration_observation.contexts.filter(c=>c.padding===.75&&c.languages.join(',')==='en-US');
  const original=structuredClone(p),pg=page([p]);assert.equal(contextualAssessment(p,()=>false),'disagrees');selectHybridComparison(pg);Page.parse(pg);assert.equal(p.comparison_role,'unresolved');assert.equal(p.text,before);assert.deepEqual(p.ocr,original.ocr);
  const matching=structuredClone(original);matching.ocr!.reconsideration_observation=observation(before);assert.equal(contextualAssessment(matching,()=>false),'consistent');
  const missing=structuredClone(original);missing.ocr!.reconsideration_observation=undefined;assert.equal(contextualAssessment(missing,()=>false),score===1?'not_applicable':'unverified');
  const source:ElementData={...structuredClone(original),observation_id:'source',method:'pdf_text',provenance:'observed',source_ref:'source',ocr:undefined};const sourcePage=page([source,structuredClone(original)]);selectHybridComparison(sourcePage);assert.equal(sourcePage.elements[0].comparison_role,'selected');assert.equal(sourcePage.elements[1].comparison_role,'shadowed');
 }
});
