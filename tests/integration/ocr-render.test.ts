import { test } from 'node:test';
import { execFileSync } from 'node:child_process';
import assert from 'node:assert/strict';
import { mkdtemp,readFile,writeFile,rm,readdir,realpath } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join,resolve } from 'node:path';
import PDFDocument from 'pdfkit';
import pptxgen from 'pptxgenjs';
import { createCanvas,GlobalFonts } from '@napi-rs/canvas';
import { zipSync,unzipSync,strToU8 } from 'fflate';
import { extractPdf } from '../../packages/ingest/pdf.js';
import { extractPptx } from '../../packages/ingest/pptx.js';
import {selectHybridComparison} from '../../packages/ingest/comparison-selection.js';
import {unresolvedComparisonText,comparisonRegions} from '../../packages/schema/index.js';
import {diffRevisions as legacyOcr9Diff} from '../../packages/diff/legacy-ocr-9.js';
import {matchPages as legacyOcr9Match} from '../../packages/matching/legacy-ocr-9.js';
import { recognizePdf,captureNativePages,supplementPdfOcr } from '../../packages/ingest/ocr.js';
import { convertPptx,validateRenderPackage,normalizeConvertedPdf,rendererSandbox } from '../../packages/render/index.js';
import { preparePptxPreview,missingRenderedText } from '../../packages/render/pptx-preview.js';
import { officeExecutable,visionExecutable,visionInfo,runTool } from '../../packages/runtime/tools.js';
import { byteHash,id,normalize,comparisonText,SCHEMA_VERSION,Report,ENGINE_VERSION,type PageData,type RevisionData,type ReportData } from '../../packages/schema/index.js';
import { matchPages as legacyNativeMatch } from '../../packages/matching/legacy-native-1.js';
import { diffRevisions as legacyNativeDiff } from '../../packages/diff/legacy-native-1.js';
import { matchPages } from '../../packages/matching/index.js';
import { diffRevisions } from '../../packages/diff/index.js';
import { exportReport } from '../../packages/export/index.js';
import { DesktopService } from '../../packages/desktop/service.js';
import { Store } from '../../packages/storage/index.js';
import { QueryService,type QueryResult } from '../../packages/query/index.js';
import {preparePdfjs} from '../../scripts/prepare-pdfjs.js';
import {numericSlots,numericPattern,numericShape,numericNotationSupported} from '../../packages/ingest/numeric-slots.js';

await preparePdfjs();
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';

const native={skip:process.platform!=='darwin'||!visionExecutable()};
const office={skip:!officeExecutable()};
async function pdf(draw:(d:PDFKit.PDFDocument)=>void):Promise<Buffer>{const d=new PDFDocument({size:[960,540],margin:0}),chunks:Buffer[]=[];d.on('data',b=>chunks.push(b));const done=new Promise<Buffer>(resolve=>d.on('end',()=>resolve(Buffer.concat(chunks))));draw(d);d.end();return done;}
function scan(text:string):Buffer{const c=createCanvas(1920,1080),ctx=c.getContext('2d');ctx.fillStyle='white';ctx.fillRect(0,0,c.width,c.height);ctx.fillStyle='black';ctx.font='48px AppleGothic';ctx.fillText('계약 검토 · Contract review',120,140);ctx.font='40px AppleGothic';ctx.fillText(text,120,300);return c.toBuffer('image/png');}
const scanned=(text:string)=>pdf(d=>d.image(scan(text),0,0,{width:960,height:540}));
test('native numeric slots, grayscale strikes and ruled-grid negative controls',native,async()=>{
  const folder=await mkdtemp(join(tmpdir(),'docver-native-checks-'));
  try{const executable=join(folder,'checks');execFileSync('swiftc',['-swift-version','5','-O','-parse-as-library','-D','DOCVER_TEST','apps/helpers/Vision.swift','tests/native/OcrChecks.swift','-o',executable],{cwd:resolve('.'),timeout:120000});const output=execFileSync(executable,[resolve('tests/fixtures/numeric-notation.json')],{encoding:'utf8',timeout:30000});assert.match(output,/PASS numeric position\/multiplicity\/conflict/);}finally{await rm(folder,{recursive:true,force:true});}
});
test('ruled grid supplement retains blank cells and inferred provenance when native table recognition misses',native,async()=>{
  const bytes=await pdf(d=>{d.font('Helvetica').fontSize(16);for(const y of [100,150,200,250])d.moveTo(100,y).lineTo(700,y).stroke('red');for(const x of [100,300,500,700])d.moveTo(x,100).lineTo(x,250).stroke('red');for(const [row,col,text]of [[0,0,'Name'],[0,1,'Corp'],[0,2,'Remark'],[1,0,'Foo'],[2,0,'Bar'],[2,1,'Microsoft'],[2,2,'Dummy']] as [number,number,string][])d.text(text,110+col*200,112+row*50,{lineBreak:false});});
  const nativeResult=await recognizePdf(bytes,1);assert.equal(nativeResult.grid_tables?.length,1);assert.equal(nativeResult.grid_tables?.[0].cells.length,9);
  const [p]=await extractPdf(bytes,'sha256:'+byteHash(bytes));await supplementPdfOcr(p,bytes,{nativeResult:{...nativeResult,tables:[]}});
  const cells=p.elements.filter(e=>e.method==='raster_ruled_grid_cell');assert.equal(cells.length,9);assert.equal(cells.filter(e=>!e.text.trim()).length,2);assert.ok(cells.filter(e=>!e.text.trim()).every(e=>e.availability==='unavailable'&&e.visibility==='uncertain'));assert.ok(cells.every(e=>e.provenance==='inferred'&&e.table?.assessment==='inferred'&&e.method==='raster_ruled_grid_cell'));assert.ok(cells.some(e=>e.table?.row===2&&e.table.column===1&&e.text==='Microsoft'));
  const duplicate=[...nativeResult.grid_tables![0].cells];const [same]=await extractPdf(bytes,'sha256:'+byteHash(bytes));await supplementPdfOcr(same,bytes,{nativeResult:{...nativeResult,tables:[{cells:duplicate}]}});assert.equal(same.elements.filter(e=>e.method==='raster_ruled_grid_cell').length,0,'Overlapping native table must take priority over duplicate grid');
  const [blocked]=await extractPdf(bytes,'sha256:'+byteHash(bytes));for(const e of blocked.elements)if(e.text==='Microsoft')e.visibility='struck_inferred';await supplementPdfOcr(blocked,bytes,{nativeResult:{...nativeResult,tables:[],grid_tables:nativeResult.grid_tables!.map(t=>({cells:t.cells.map(c=>c.text==='Microsoft'?{...c,text_confident:true}:c)}))}});assert.equal(blocked.elements.find(e=>e.method==='raster_ruled_grid_cell'&&e.text==='Microsoft')?.visibility,'uncertain','Raw strike evidence must also block grid cell promotion');
  const [contradicted]=await extractPdf(bytes,'sha256:'+byteHash(bytes));contradicted.elements=[];contradicted.text='';contradicted.unresolved_text='';await supplementPdfOcr(contradicted,bytes,{nativeResult:{...nativeResult,tables:[],grid_tables:[],lines:[{...nativeResult.lines[0],text:'Foo',confidence:1,numeric_consensus:false,numeric_status:'conflicted',alternatives:[{text:'Foo',confidence:1}]}]}});assert.equal(contradicted.ocr_text,'');assert.equal(contradicted.ocr_unresolved_text,'Foo','A tile digit contradiction cannot be bypassed by a letter-only primary reading');
});
const rev=(p:PageData,key:string):RevisionData=>({revision_id:key,revision_occurrence_id:key,label:key,assets:[{asset_id:p.asset_id,format:'pdf',bytes:0}],status:'success',pages:[p],coverage_gaps:p.coverage_gaps,errors:[],bundle_mapping:[]});
function changes(a:PageData,b:PageData){const m=matchPages([a],[b]);assert.equal(m.matches.length,1);return diffRevisions(rev(a,'v1'),rev(b,'v2'),m.matches,m.candidates,()=> 'entity');}

test('unique native raster anchors survive identical-text reorders without overriding manual decisions or derived renders',()=>{
  const page=(key:string,asset:string,n:number,raster:string):PageData=>({page_id:key,asset_id:asset,page:n,width:960,height:540,coordinate_system:'normalized',source_transform:[],hidden:false,text:'Quarterly Revenue 100',visible_text:'Quarterly Revenue 100',elements:[],notes:null,capabilities:{text:'available',notes:'unavailable',hidden_slides:'unavailable',animation:'unavailable',structure:'unavailable',preview:'available'},coverage_gaps:[],raster:{sha256:raster.repeat(64),width:960,height:540,renderer:'fixture',environment:'fixture'}});
  const left=[page('a1','sourceA',1,'a'),page('a2','sourceA',2,'b')],right=[page('b1','sourceB',1,'b'),page('b2','sourceB',2,'a')];
  const matched=matchPages(left,right);assert.deepEqual(matched.matches.map(m=>[m.from_page_id,m.to_page_id,m.status]),[['a1','b2','inferred'],['a2','b1','inferred']]);
  const delta=diffRevisions({...rev(left[0],'a'),pages:left},{...rev(right[0],'b'),pages:right},matched.matches,matched.candidates,p=>'entity-'+p);assert.equal(delta.filter(c=>c.kind==='visual_region_changed').length,0);assert.equal(delta.filter(c=>c.kind==='page_moved').length,2);
  const unlinked=matchPages(left,right,[{from_page_id:'a1',to_page_id:'b2',action:'unlink',reason:'manual exclusion'}]);assert.ok(!unlinked.matches.some(m=>m.from_page_id==='a1'&&m.to_page_id==='b2'));
  const linked=matchPages(left,right,[{from_page_id:'a1',to_page_id:'b1',action:'link',reason:'manual override'}]);assert.ok(linked.matches.some(m=>m.from_page_id==='a1'&&m.to_page_id==='b1'&&m.status==='human_confirmed'));
  const repeatedLeft=left.map(p=>({...p,raster:{...p.raster!,sha256:'c'.repeat(64)}})),repeatedRight=right.map(p=>({...p,raster:{...p.raster!,sha256:'c'.repeat(64)}}));assert.ok(matchPages(repeatedLeft,repeatedRight).matches.every(m=>m.status==='needs_review'));
  const derivedRight=right.map(p=>({...p,preview:{asset_id:'sha256:'+'d'.repeat(64),page:p.page,width:960,height:540,source_transform:[1,0,0,1,0,0],renderer:'fixture',environment:'fixture',assessment:'inferred' as const,warnings:[]}}));assert.ok(matchPages(left,derivedRight).matches.every(m=>m.status==='needs_review'),'Derived PPTX pixels cannot constrain original page identity');
  const sameSource=right.map((p,i)=>({...p,asset_id:'sourceA',page:i+1}));assert.deepEqual(matchPages(left,sameSource).matches.map(m=>[m.from_page_id,m.to_page_id]),[['a1','b1'],['a2','b2']],'Exact immutable source identity takes priority over raster evidence');
});

test('OCR order-only differences retain layout evidence and archived engine9 replay semantics',async()=>{
  const page=(key:string,rows:[string,number][]):PageData=>({page_id:key,asset_id:key,page:1,width:960,height:540,coordinate_system:'normalized',source_transform:[],hidden:false,text:'',comparison_basis:'raster_ocr',ocr_text:rows.map(r=>r[0]).join('\n'),elements:rows.map(([text,y],i)=>({observation_id:key+i,kind:'text',text,normalized_text:text,bbox:[.1,y,.3,.06],reading_order:i,availability:'available',method:'vision_ocr',source_ref:'line'+i,provenance:'inferred',visibility:'visible'})),notes:null,capabilities:{text:'available',notes:'unavailable',hidden_slides:'unavailable',animation:'unavailable',structure:'unavailable',preview:'available'},coverage_gaps:[],raster:{sha256:key.repeat(64),width:960,height:540,renderer:'fixture',environment:'fixture'}});
  const a=page('a',[['Revenue 100',.1],['Cost 50',.3]]),b=page('b',[['Cost 50',.3],['Revenue 100',.1]]),order=changes(a,b);
  assert.equal(order.filter(c=>c.kind==='text_modified').length,0);assert.ok(order.some(c=>c.kind==='coverage_gap'&&c.coverage_gaps.some(g=>g.reason==='ocr_reading_order_changed_without_text_region_change')));assert.ok(order.some(c=>c.kind==='visual_region_changed'));
  const folder=await mkdtemp(join(tmpdir(),'docver-legacy9-')),store=new Store(folder);
  try{const left=rev(a,'v1'),right=rev(b,'v2'),matching=legacyOcr9Match([a],[b]),rangeMatches=[{...matching.matches[0],reasons:['snapshot_lineage_range_net']}],original=legacyOcr9Diff(left,right,rangeMatches,matching.candidates,()=> 'entity_legacy9');assert.equal(original.filter(c=>c.kind==='text_modified').length,1,'Archived9 must retain its exact old behavior');
    const report:ReportData={schema_version:'0.2.0',engine_version:'0.2.0-native.ocr-render.9',report_id:'rpt_legacy9',project_id:'prj_legacy9',timeline_revision_id:'timeline',mapping_revision_id:'mapping',schema_hash:'historical9',observation_environment:{fixture:'engine9'},revisions:[left,right],matches:matching.matches,candidates:matching.candidates,mapping_decisions:[],lineages:[{entity_id:'entity_legacy9',page_ids:[a.page_id,b.page_id],status:'inferred'}],changes:[],coverage_gaps:[]};store.finishRun(store.beginRun(report.project_id,'Archived9'),report);
    const before=store.db.prepare('SELECT body FROM reports WHERE id=?').get(report.report_id)?.body,q=new QueryService(store,new Set([report.project_id])),net=q.changeSet({project_id:report.project_id,report_id:report.report_id,mode:'range_net',from:'v1',to:'v2'});assert.deepEqual(net.map(c=>c.kind),original.map(c=>c.kind));assert.deepEqual(net.map(c=>c.change_id),original.map((c,i)=>id('net',[report.report_id,'v1','v2',i,c])));assert.equal(store.db.prepare('SELECT body FROM reports WHERE id=?').get(report.report_id)?.body,before);
  }finally{store.close();await rm(folder,{recursive:true,force:true});}

  assert.equal(changes(a,page('c',[['Revenue 120',.1],['Cost 50',.3]])).filter(c=>c.kind==='text_modified').length,1,'Actual numeric edits must remain');
  const extra=changes(a,page('d',[['Revenue 100',.1],['Cost 50',.3],['Cost 50',.3]]));assert.ok(!extra.some(c=>c.coverage_gaps.some(g=>g.reason==='ocr_reading_order_changed_without_text_region_change')),'Duplicate multiplicity cannot be erased by an existential match');
});

test('grid observer statuses survive schema, comparison data and explicit gaps',native,async()=>{
  const bytes=await pdf(d=>d.fontSize(20).text('Grid status fixture',50,60)),observed=await recognizePdf(bytes,1);
  for(const status of ['unsupported_format','unsupported_dimensions','budget_exceeded','ambiguous_boundaries'] as const){const [p]=await extractPdf(bytes,'sha256:'+byteHash(bytes));await supplementPdfOcr(p,bytes,{nativeResult:{...observed,grid_tables:[],grid_status:status,grid_reasons:['fixture_boundary_reason']}});assert.equal(p.ocr?.grid_status,status);assert.deepEqual(p.ocr?.grid_reasons,['fixture_boundary_reason']);assert.ok(p.coverage_gaps.some(g=>g.reason==='raster_grid_'+status));assert.ok(p.coverage_gaps.some(g=>g.reason==='raster_grid_fixture_boundary_reason'));}
});

test('hybrid selection preserves reliable raw regions, inferred recovery and blocked whole-line observations',()=>{
  type E=PageData['elements'][number];
  const element=(id:string,text:string,y:number,method='pdf_text',visibility:E['visibility']='visible',x=.1,w=.4):E=>({observation_id:id,kind:'text',text,normalized_text:text,bbox:[x,y,w,.05],reading_order:0,availability:'available',method,source_ref:id,provenance:method==='vision_ocr'?'inferred':'observed',visibility});
  const page=(key:string,elements:E[]):PageData=>({page_id:key,asset_id:key,page:1,width:960,height:540,coordinate_system:'normalized',source_transform:[],hidden:false,text:elements.filter(e=>e.provenance==='observed').map(e=>e.text).join('\n'),unresolved_text:'Unverified source retained',elements,notes:null,capabilities:{text:'available',notes:'unavailable',hidden_slides:'unavailable',animation:'unavailable',structure:'unavailable',preview:'available'},coverage_gaps:[]});
  const raw=element('raw','Check · source',.1),title=element('title','Unknown title',.3,'pdf_text','unverified'),observed=element('ocr','Check • source',.1,'vision_ocr'),recovery=element('recover','Recovered title',.3,'vision_ocr');
  const p=page('a',[raw,title,observed,recovery]),before=p.elements.map(e=>({...e}));selectHybridComparison(p);
  assert.ok(comparisonText(p).includes('Check · source'));assert.ok(!comparisonText(p).includes('Check • source'));assert.equal(raw.comparison_role,'selected');assert.equal(observed.comparison_role,'unresolved');assert.equal(observed.comparison_reason,'ocr_text_disagreement_whole_line_unresolved');assert.equal(title.comparison_role,'shadowed');assert.equal(recovery.comparison_role,'selected');assert.equal(recovery.provenance,'inferred');assert.ok(p.coverage_gaps.some(g=>g.reason==='raw_ocr_region_disagreement_source_priority'));
  assert.deepEqual(p.elements.map(({comparison_role,comparison_reason,comparison_order,...e})=>e),before,'Selection annotates observations without changing source or OCR fields');
  const a=page('b',[element('a','Revenue 100',.1),element('u','unknown',.3,'pdf_text','uncertain'),element('o','Revenue 100',.1,'vision_ocr')]),b=page('c',[element('b','Revenue 120',.1),element('v','unknown',.3,'pdf_text','uncertain'),element('q','Revenue 100',.1,'vision_ocr')]);selectHybridComparison(a);selectHybridComparison(b);const changed=changes(a,b).filter(c=>c.kind==='text_modified');assert.equal(changed.length,1);assert.equal(changed[0].text_assessment,'observed');assert.deepEqual(changed[0].evidence.map(e=>e.quote),['Revenue 100','Revenue 120']);
  const blocked=page('d',[element('cover','Revenue 1.5',.1,'pdf_text','partially_occluded'),element('seen','Revenue 15',.1,'vision_ocr')]);selectHybridComparison(blocked);assert.equal(comparisonText(blocked),'');assert.ok(unresolvedComparisonText(blocked).includes('1.5'));assert.equal(blocked.elements[1].comparison_reason,'source_appearance_blocks_ocr');
  const mixed=page('e',[element('label','Revenue',.1,'pdf_text','visible',.1,.15),element('amount','100',.1,'pdf_text','unverified',.3,.1),element('merged','Revenue 100',.1,'vision_ocr','visible',.1,.4)]);selectHybridComparison(mixed);assert.equal(mixed.elements[2].comparison_role,'unresolved');assert.equal(comparisonText(mixed),'Revenue');assert.ok(unresolvedComparisonText(mixed).includes('100'));
  const hidden=page('f',[element('prior','Revenue 999',.1,'pdf_text','hidden_render_mode'),element('fresh','Revenue 120',.1,'vision_ocr')]);selectHybridComparison(hidden);assert.equal(comparisonText(hidden),'Revenue 120');assert.equal(hidden.elements[0].comparison_role,'excluded');assert.equal(hidden.elements[1].provenance,'inferred');
  const historical={...p,comparison_basis:'raster_ocr' as const,ocr_text:'Old OCR projection',ocr_unresolved_text:'Old unresolved'};assert.equal(comparisonText(historical),'Old OCR projection');assert.equal(unresolvedComparisonText(historical),'Old unresolved');assert.ok(comparisonRegions(p).every(e=>['selected','unresolved'].includes(e.comparison_role!)));
});

test('hybrid coverage retains unread tails and glyph warnings, and keeps mixed-size rows stable',()=>{
  type E=PageData['elements'][number];
  const element=(id:string,text:string,bbox:E['bbox'],visibility:E['visibility']='visible',ocr=false):E=>({observation_id:id,kind:'text',text,normalized_text:text,bbox,reading_order:0,availability:'available',method:ocr?'vision_ocr':'pdf_text',source_ref:id,provenance:ocr?'inferred':'observed',visibility});
  const page=(key:string,elements:E[]):PageData=>({page_id:key,asset_id:key,page:1,width:960,height:540,coordinate_system:'normalized',source_transform:[],hidden:false,text:elements.filter(e=>e.provenance==='observed').map(e=>e.text).join('\n'),elements,notes:null,capabilities:{text:'available',notes:'unavailable',hidden_slides:'unavailable',animation:'unavailable',structure:'unavailable',preview:'available'},coverage_gaps:[],raster:{sha256:key.repeat(64),width:960,height:540,renderer:'fixture',environment:'fixture'}});
  const tail=(key:string,n:string)=>{const p=page(key,[element('raw','Revenue '+n+' Unreadable tail 999',[.1,.1,.5,.05],'unverified'),element('ocr','Revenue '+n,[.1,.1,.21,.05],'visible',true)]);selectHybridComparison(p);return p;};
  const a=tail('a','100'),b=tail('b','120');assert.equal(a.elements[0].comparison_role,'unresolved');assert.ok(unresolvedComparisonText(a).includes('Unreadable tail 999'));assert.equal(changes(a,b).filter(c=>c.kind==='text_modified').length,0,'A prefix cannot resolve a larger unknown run');
  const independent=(key:string,n:string)=>{const p=page(key,[element('raw','Unreadable tail 999',[.1,.4,.5,.05],'unverified'),element('ocr','Revenue '+n,[.1,.1,.21,.05],'visible',true)]);selectHybridComparison(p);return p;};
  const regional=changes(independent('c','100'),independent('d','120')).filter(c=>c.kind==='text_modified');assert.equal(regional.length,1);assert.equal(regional[0].text_scope,'region');assert.equal(regional[0].text_assessment,'inferred');
  const blocked=element('blocked','Revenue 1.5',[.1,.1,.4,.05],'uncertain');blocked.visibility_spans=[{text:'.',state:'occluded',bbox:[.35,.1,.01,.05],paint_index:1,assessment:'inferred'},{text:'R',state:'uncertain',bbox:[.1,.1,.03,.05],paint_index:0,assessment:'inferred'}];
  const covered=page('e',[blocked,element('ocr','Revenue 15',[.1,.1,.4,.05],'visible',true)]);selectHybridComparison(covered);assert.equal(covered.elements[1].comparison_reason,'source_appearance_blocks_ocr');assert.equal(comparisonText(covered),'');assert.ok(unresolvedComparisonText(covered).includes('1.5'));
  const unrelated=page('f',[structuredClone(blocked),element('ocr','Independent 100',[.6,.1,.3,.05],'visible',true)]);selectHybridComparison(unrelated);assert.equal(unrelated.elements[1].comparison_role,'selected','Disjoint appearance spans cannot block an independent region');
  const kpi=page('g',[element('label','Revenue',[.1,.10,.2,.02]),element('amount','₩12,000',[.4,.09,.15,.05],'visible',true)]);selectHybridComparison(kpi);assert.equal(comparisonText(kpi),'Revenue\n₩12,000');
  const tall=page('h',[element('tall','Tall',[.1,.1,.1,.1]),element('line1','L1',[.31,.1,.2,.02],'visible',true),element('line2','L2',[.30,.13,.2,.02],'visible',true)]);selectHybridComparison(tall);assert.equal(comparisonText(tall),'Tall\nL1\nL2');
  const sourceOnly=(key:string,y:number)=>{const p=page(key,[element('revenue','Revenue 100',[.1,y,.3,.02]),element('cost','Cost 50',[.5,.1001,.3,.02]),element('prior','Hidden 999',[.1,.8,.3,.02],'hidden_render_mode'),element('ocr1','Revenue 100',[.1,y,.3,.02],'visible',true),element('ocr2','Cost 50',[.5,.1001,.3,.02],'visible',true)]);selectHybridComparison(p);return p;};
  const left=sourceOnly('i',.1),right=sourceOnly('j',.1002);assert.equal(comparisonText(left),comparisonText(right));
  // Also protect imported snapshots whose persisted projection order differs.
  right.elements[0].comparison_order=1;right.elements[1].comparison_order=0;
  const order=changes(left,right);assert.equal(order.filter(c=>c.kind==='text_modified').length,0);assert.ok(order.some(c=>c.kind==='visual_region_changed'));assert.ok(order.some(c=>c.coverage_gaps.some(g=>g.reason==='ocr_reading_order_changed_without_text_region_change')));
});

test('mixed PDF glyph paint states block OCR lines and grid values independently of aggregate uncertainty',native,async()=>{
  const make=(draw?:(d:PDFKit.PDFDocument)=>void)=>pdf(d=>{d.fontSize(24).text('Revenue 1.5',50,80,{lineBreak:false});draw?.(d);});
  const [baseline]=await extractPdf(await make(),'sha256:baseline'),spans=baseline.elements[0].visibility_spans!;
  const bytes=await make(d=>{for(const [text,alpha]of [['.',1],['R',.4]] as const){const b=spans.find(s=>s.text===text)!.bbox;d.save().fillOpacity(alpha).rect(b[0]*960-.1,b[1]*540-.1,b[2]*960+.2,b[3]*540+.2).fill('white').restore();}});
  const [p]=await extractPdf(bytes,'sha256:mixed-paint'),raw=p.elements[0];assert.equal(raw.visibility,'uncertain');assert.ok(raw.visibility_spans?.some(s=>s.text==='.'&&s.state==='occluded'));
  const result=await recognizePdf(bytes,1),line={...result.lines[0],text:'Revenue 15',confidence:1,bbox:raw.bbox,strike_candidate:false,strike_status:'not_detected',numeric_consensus:true,numeric_status:'verified',alternatives:[{text:'Revenue 15',confidence:1}]};
  await supplementPdfOcr(p,bytes,{nativeResult:{...result,lines:[line],tables:[],grid_tables:[{cells:[{row:0,column:0,row_span:1,column_span:1,text:'Revenue 15',text_confident:true,bbox:raw.bbox}]}]}});
  assert.equal(p.elements.find(e=>e.method==='vision_ocr')?.visibility,'uncertain');assert.equal(p.elements.find(e=>e.method==='vision_ocr')?.comparison_reason,'source_appearance_blocks_ocr');assert.equal(p.elements.find(e=>e.method==='raster_ruled_grid_cell')?.visibility,'uncertain');assert.equal(comparisonText(p),'');assert.ok(unresolvedComparisonText(p).includes('1.5'));
});

test('observed PDF strike source retains priority over redundant blocked OCR without clearing its visibility',native,async()=>{
  const make=(value:string)=>pdf(d=>{d.fontSize(24).text('Revenue '+value,50,80,{lineBreak:false});d.strike(49,76,160,35,{color:'red'});d.addContent('3 Tr');d.text('Prior hidden 999',50,400,{lineBreak:false});});
  const left=await make('100'),right=await make('120'),a=(await extractPdf(left,'sha256:observed-strike-a'))[0],b=(await extractPdf(right,'sha256:observed-strike-b'))[0];
  for(const [p,bytes,value]of [[a,left,'100'],[b,right,'120']] as const){
    const raw=p.elements[0];assert.equal(raw.visibility,'struck_through');assert.ok(raw.visibility_spans?.every(s=>s.state==='struck_through'&&s.assessment==='observed'));
    const result=await recognizePdf(bytes,1),line={...result.lines[0],text:'Revenue '+value,confidence:1,bbox:raw.bbox,strike_candidate:false,strike_status:'not_detected',numeric_consensus:true,numeric_status:'verified',alternatives:[{text:'Revenue '+value,confidence:1}]};
    await supplementPdfOcr(p,bytes,{nativeResult:{...result,lines:[line],tables:[],grid_tables:[{cells:[{row:0,column:0,row_span:1,column_span:1,text:'Revenue '+value,text_confident:true,bbox:raw.bbox}]}]}});
    const redundant=p.elements.find(e=>e.method==='vision_ocr')!;assert.equal(raw.comparison_role,'selected');assert.equal(redundant.comparison_role,'shadowed');assert.equal(redundant.visibility,'uncertain');assert.equal(p.elements.find(e=>e.method==='raster_ruled_grid_cell')?.visibility,'uncertain');assert.equal(unresolvedComparisonText(p),'');
  }
  const modified=changes(a,b).filter(c=>c.kind==='text_modified');assert.equal(modified.length,1);assert.equal(modified[0].text_assessment,'observed');assert.deepEqual(modified[0].evidence.map(e=>e.quote),['Revenue 100','Revenue 120']);
  const partial=structuredClone(a),source=partial.elements[0];source.visibility='uncertain';source.visibility_spans![0].state='partially_struck_through';selectHybridComparison(partial);assert.equal(partial.elements.find(e=>e.method==='vision_ocr')?.comparison_role,'unresolved');assert.ok(unresolvedComparisonText(partial).includes('100'));
  // Unrelated uncertainty must not erase an otherwise supported observed strike.
  const unclear=(p:PageData)=>{const q=structuredClone(p);q.elements.push({...q.elements[0],observation_id:'unknown',text:'Unknown',normalized_text:'Unknown',bbox:[.1,.5,.3,.05],visibility:'unverified',visibility_spans:[]});selectHybridComparison(q);return q;};
  const regional=changes(unclear(a),unclear(b)).filter(c=>c.kind==='text_modified');assert.equal(regional.length,1);assert.equal(regional[0].text_scope,'region');assert.equal(regional[0].text_assessment,'observed');assert.deepEqual(regional[0].evidence.map(e=>e.quote),['Revenue 100','Revenue 120']);
  for(const state of ['struck_inferred','partially_struck_through','occluded','uncertain'] as const){const q=unclear(a);q.elements[0].visibility=state;selectHybridComparison(q);assert.equal(changes(q,unclear(b)).filter(c=>c.kind==='text_modified').length,0,'Partial/inferred appearance cannot enter observed strike regional comparison');}
});

test('source union coverage preserves raster gaps instead of treating enclosing bounds as observed text',async()=>{
  const make=async(label:string,value:string,key:string)=>{
    const c=createCanvas(160,45),ctx=c.getContext('2d');ctx.fillStyle='white';ctx.fillRect(0,0,160,45);ctx.fillStyle='black';ctx.font='24px Helvetica';ctx.fillText(value,0,30);
    const bytes=await pdf(d=>{d.fontSize(24).text(label,50,80,{lineBreak:false});d.image(c.toBuffer('image/png'),230,76,{width:160,height:45});d.text('USD',400,80,{lineBreak:false});d.addContent('3 Tr');d.text('Prior hidden',50,400,{lineBreak:false});});
    const [p]=await extractPdf(bytes,key,{ocr:'off'}),raw=p.elements.filter(e=>e.visibility==='visible'),x=Math.min(...raw.map(e=>e.bbox[0])),y=Math.min(...raw.map(e=>e.bbox[1]));assert.equal(raw.length,2);
    p.elements.push({observation_id:'ocr',kind:'text',text:label+' '+value+' USD',normalized_text:normalize(label+' '+value+' USD'),bbox:[x,y,Math.max(...raw.map(e=>e.bbox[0]+e.bbox[2]))-x,Math.max(...raw.map(e=>e.bbox[1]+e.bbox[3]))-y],reading_order:p.elements.length,availability:'available',method:'vision_ocr',source_ref:'synthetic-whole-line-reading',provenance:'inferred',visibility:'visible'});selectHybridComparison(p);return p;
  };
  const a=await make('Revenue Q1','100','a'),b=await make('Revenue Q2','120','b');assert.equal(a.elements.at(-1)?.comparison_role,'unresolved');assert.ok(unresolvedComparisonText(a).includes('100'));assert.ok(a.coverage_gaps.some(g=>g.reason==='ocr_crosses_mixed_or_uncovered_source_regions'));
  const delta=changes(a,b).filter(c=>c.kind==='text_modified');assert.equal(delta.length,1);assert.equal(delta[0].text_scope,'region');assert.deepEqual(delta[0].evidence.map(e=>e.quote),['Revenue Q1','Revenue Q2']);
  assert.ok(changes(a,b).some(c=>c.coverage_gaps.some(g=>g.reason==='pdf_visibility_unresolved_text_comparison_withheld')),'Unresolved raster content remains a page-level comparison gap');
  const fixture=(boxes:PageData['elements'][number]['bbox'][],target:PageData['elements'][number]['bbox'])=>{const p=structuredClone(a),template=p.elements[0],text=boxes.map((_,i)=>'Piece'+i).join(' ');p.elements=boxes.map((bbox,i)=>({...template,observation_id:'raw'+i,text:'Piece'+i,normalized_text:'Piece'+i,bbox,visibility:'visible' as const,visibility_spans:[]}));p.elements.push({...template,observation_id:'ocr',text,normalized_text:text,bbox:target,method:'vision_ocr',provenance:'inferred',visibility:'visible',visibility_spans:[]});selectHybridComparison(p);return p.elements.at(-1)!;};
  assert.equal(fixture([[.1,.1,.3,.05],[.4,.1,.3,.05]],[.1,.1,.6,.05]).comparison_role,'shadowed','Adjacent source pieces really cover the line');
  assert.equal(fixture([[.1,.1,.2,.05],[.3001,.1,.3999,.05]],[.1,.1,.6,.05]).comparison_role,'unresolved','Edge tolerance must never bridge even a tiny internal raster punctuation gap');
  assert.equal(fixture([[.1,.1,.6,.02],[.1,.12,.3,.03]],[.1,.1,.6,.05]).comparison_role,'unresolved','Vertical slabs must detect L-shaped coverage holes');
  assert.equal(fixture([[.1,.1,.6,.05]],[.0997,.0997,.6006,.0506]).comparison_role,'shadowed','Outer OCR edge tolerance is retained');
  assert.equal(fixture(Array.from({length:257},()=>[.1,.1,.6,.05]),[.1,.1,.6,.05]).comparison_reason,'readable_source_coverage_union_budget_exceeded');
  const canvas=createCanvas(100,40),ctx=canvas.getContext('2d');ctx.fillStyle='white';ctx.fillRect(0,0,100,40);ctx.fillStyle='black';ctx.font='24px Helvetica';ctx.fillText('1',0,30);
  const bytes=await pdf(d=>{d.image(canvas.toBuffer('image/png'),145,80,{width:5,height:24});d.fontSize(24).text('Revenue USD',50,80,{lineBreak:false});d.addContent('3 Tr');d.text('Hidden',50,400,{lineBreak:false});}),[one]=await extractPdf(bytes,'sha256:single-run-hole'),clear=one.elements.filter(e=>e.visibility==='visible');assert.equal(clear.length,1,'PDF.js retains the literal single-space source in one run');
  one.elements.push({...clear[0],observation_id:'ocr',method:'vision_ocr',provenance:'inferred',text:'Revenue 1 USD',normalized_text:'Revenue 1 USD',visibility_spans:[]});selectHybridComparison(one);assert.equal(one.elements.at(-1)!.comparison_role,'unresolved');assert.equal(one.elements.at(-1)!.comparison_reason,'ocr_text_disagreement_whole_line_unresolved');assert.ok(unresolvedComparisonText(one).includes('Revenue 1 USD'));
});

test('hybrid source agreement uses target glyphs for neighboring lines and split OCR runs',async()=>{
  const embedded=(draw:(d:PDFKit.PDFDocument)=>void)=>pdf(d=>{d.font(resolve('node_modules/pdfjs-dist/standard_fonts/LiberationSans-Regular.ttf'));draw(d);});
  const [tight]=await extractPdf(await embedded(d=>{d.save().rect(40,70,300,32.1).clip();d.fontSize(24).text('H',50,80,{lineBreak:false});d.restore().save().rect(40,102.15,300,17.15).clip();d.text('H',50,97.2,{lineBreak:false});d.restore();}),'sha256:tight-target');
  assert.ok(tight.elements.every(e=>e.visibility==='visible'));tight.elements.push({...tight.elements[0],observation_id:'ocr-tight',method:'vision_ocr',provenance:'inferred',visibility_spans:[],visibility_evidence:[]});selectHybridComparison(tight);assert.equal(tight.elements.at(-1)!.comparison_role,'shadowed','Neighboring empty metric margins do not append another line to the agreement text');assert.ok(!tight.coverage_gaps.some(g=>g.reason==='raw_ocr_region_disagreement_source_priority'));
  const [split]=await extractPdf(await embedded(d=>d.fontSize(24).text('Revenue Q1 2026',50,80,{lineBreak:false})),'sha256:split-target');assert.equal(split.elements.length,1);const raw=split.elements[0],spans=raw.visibility_spans!;
  const envelope=(boxes:PageData['elements'][number]['bbox'][]):PageData['elements'][number]['bbox']=>{const x=Math.min(...boxes.map(b=>b[0])),y=Math.min(...boxes.map(b=>b[1]));return [x,y,Math.max(...boxes.map(b=>b[0]+b[2]))-x,Math.max(...boxes.map(b=>b[1]+b[3]))-y];};
  for(const [text,ss]of [['Revenue Q1',spans.slice(0,9)],['2026',spans.slice(9)]]as const)split.elements.push({...raw,observation_id:'ocr-'+text,text,normalized_text:text,bbox:envelope(ss.map(s=>s.bbox)),method:'vision_ocr',provenance:'inferred',visibility_spans:[],visibility_evidence:[]});
  selectHybridComparison(split);assert.ok(split.elements.filter(e=>e.method==='vision_ocr').every(e=>e.comparison_role==='shadowed'));assert.equal(comparisonText(split),'Revenue Q1 2026');assert.ok(!split.coverage_gaps.some(g=>g.reason==='raw_ocr_region_disagreement_source_priority'));
  const mismatched=structuredClone(split);mismatched.elements.at(-1)!.text='2028';selectHybridComparison(mismatched);assert.equal(mismatched.elements.at(-1)!.comparison_role,'unresolved','Exact target content still matters');
  const malformed=structuredClone(split);malformed.elements[0].visibility_spans!.pop();selectHybridComparison(malformed);assert.equal(malformed.elements.at(-1)!.comparison_reason,'readable_source_glyph_text_correlation_unverified');
  const budget=structuredClone(split);budget.elements[0].visibility_spans=Array.from({length:8193},()=>({...spans[0]}));selectHybridComparison(budget);assert.equal(budget.elements.at(-1)!.comparison_reason,'readable_source_glyph_agreement_budget_exceeded');
  const reordered=structuredClone(split);reordered.elements[0].visibility_spans!.reverse();selectHybridComparison(reordered);assert.ok(reordered.elements.filter(e=>e.method==='vision_ocr').every(e=>e.comparison_role==='unresolved'),'Incorrect source correlation is not repaired from the OCR hypothesis');
  const logical=(text:string,spans:NonNullable<PageData['elements'][number]['visibility_spans']>)=>{const p=structuredClone(split);p.elements=[{...raw,text,normalized_text:text,bbox:[.1,.1,.3,.064],visibility_spans:spans},{...raw,observation_id:'ocr-logical',text,normalized_text:text,bbox:[.1,.1,.3,.064],method:'vision_ocr',provenance:'inferred',visibility_spans:[]}];selectHybridComparison(p);return p.elements[1].comparison_role;};
  const span=(text:string,bbox:PageData['elements'][number]['bbox'])=>({text,bbox,state:'visible',paint_index:0,assessment:'inferred' as const});
  assert.equal(logical('$12',[span('$',[.1,.145,.01,.019]),span('1',[.12,.1,.02,.064]),span('2',[.14,.1,.02,.064])]),'shadowed','Mixed glyph sizes retain correlated source order');
  assert.equal(logical('אבג',[span('א',[.3,.1,.03,.05]),span('ב',[.2,.1,.03,.05]),span('ג',[.1,.1,.03,.05])]),'shadowed','RTL glyphs retain logical source order');
});

test('UserUnit outline proof preserves at least one actual native pixel of clearance',native,async()=>{
  for(const unit of [.5,1,2,10]){
    const make=(margin?:number)=>new Promise<Buffer>(done=>{const d=new PDFDocument({size:[100,100],margin:0}),chunks:Buffer[]=[];d.on('data',b=>chunks.push(b));d.on('end',()=>done(Buffer.concat(chunks)));(d.page as any).dictionary.data.UserUnit=unit;d.font(resolve('node_modules/pdfjs-dist/standard_fonts/LiberationSans-Regular.ttf')).fontSize(12);if(margin!==undefined)d.save().rect(5,5,80,10+905.2734375/1000*12+margin-5).clip();d.text('H',10,10,{lineBreak:false});if(margin!==undefined)d.restore();d.end();});
    const positive=await make(.6),[p]=await extractPdf(positive,'sha256:unit'+unit,{ocr:'off'}),[near]=await extractPdf(await make(.18),'sha256:unit-near'+unit,{ocr:'off'});assert.equal(p.elements[0].visibility,'visible');assert.equal(near.elements[0].visibility,'unverified','A native subpixel margin cannot qualify under a scaled PDF.js viewport');
    const native=(await captureNativePages(positive,[1],[])).get(1)!,base=(await captureNativePages(await make(),[1],[])).get(1)!;assert.equal(native.render_sha256,base.render_sha256);const ink=p.elements[0].visibility_evidence!.find(e=>e.method==='loaded_glyph_outline_inside_rect_clip')!.bbox;assert.ok(((10+905.2734375/1000*12+.6)/100-ink[1]-ink[3])*native.height>=1,'Claimed proof retains actual native-pixel clearance');
  }
});

test('disjoint proven text clips do not occlude each other through empty metric margins',native,async()=>{
  const make=(clipped:boolean)=>pdf(d=>{d.font(resolve('node_modules/pdfjs-dist/standard_fonts/LiberationSans-Regular.ttf'));if(clipped)d.save().rect(40,70,300,32.1).clip();d.fontSize(24).text('H',50,80,{lineBreak:false});if(clipped)d.restore();if(clipped)d.save().rect(40,102.15,300,17.15).clip();d.fontSize(24).text('H',50,97.2,{lineBreak:false});if(clipped)d.restore();});
  const bytes=await make(true),[p]=await extractPdf(bytes,'sha256:stacked-clips');assert.equal(p.elements.length,2);assert.ok(p.elements.every(e=>e.visibility==='visible'));assert.ok(p.elements.every(e=>e.visibility_evidence?.some(v=>v.method==='loaded_glyph_outline_inside_rect_clip')));
  const render=async(bytes:Buffer)=>(await captureNativePages(bytes,[1],[])).get(1)!.render_sha256;assert.equal(await render(bytes),await render(await make(false)),'Native pixels verify disjoint clips removed only empty margins');
});

test('loaded glyph outlines resolve clipped font margins while clipped ink stays unverified',native,async()=>{
  const make=(bottom?:number,text='Revenue 1.5')=>pdf(d=>{d.font(resolve('node_modules/pdfjs-dist/standard_fonts/LiberationSans-Regular.ttf'));if(bottom!==undefined)d.save().rect(40,70,300,bottom-70).clip();d.fontSize(24).text(text,50,80,{lineBreak:false});if(bottom!==undefined){d.restore();d.rect(40,bottom,300,.05).fill('white');}});
  const baseline=await make(),margin=await make(104),cut=await make(90),a=(await extractPdf(baseline,'sha256:clip-baseline'))[0],b=(await extractPdf(margin,'sha256:clip-margin'))[0],c=(await extractPdf(cut,'sha256:clip-ink'))[0];
  assert.equal(a.elements[0].visibility,'visible');assert.equal(b.elements[0].visibility,'visible');assert.ok(b.elements[0].visibility_evidence?.some(e=>e.method==='loaded_glyph_outline_inside_rect_clip'));assert.equal(c.elements[0].visibility,'unverified');assert.ok(c.unresolved_text?.includes('1.5'));
  assert.equal(a.text,b.text);assert.deepEqual(a.elements[0].bbox,b.elements[0].bbox,'Raw font metric boxes must not be rewritten as ink bounds');
  const render=async(bytes:Buffer)=>(await captureNativePages(bytes,[1],[])).get(1)!.render_sha256;
  assert.equal(await render(baseline),await render(margin),'Actual PDFKit pixels confirm the positive clip removes only font margin');assert.notEqual(await render(baseline),await render(cut));
  // Embedded LiberationSans H has minY=0: its outline bottom is the baseline.
  // A0.003pt ink cut must fail even below the ordinary metric tolerance.
  const near=(await extractPdf(await make(80+905.2734375/1000*24-.003,'H'),'sha256:near-ink-cut'))[0];assert.equal(near.elements[0].visibility,'unverified');assert.ok(near.unresolved_text?.includes('H'));
});

test('substituted standard font outlines cannot certify native clipped ink',native,async()=>{
  const make=(clipped:boolean)=>pdf(d=>{if(clipped)d.save().rect(40,70,300,27.5).clip();d.fontSize(24).text('H',50,80,{lineBreak:false});if(clipped)d.restore();if(clipped)d.save().rect(40,97.65,300,17.35).clip();d.fontSize(24).text('H',50,97.2,{lineBreak:false});if(clipped)d.restore();});
  const bytes=await make(true),[p]=await extractPdf(bytes,'sha256:substituted-clips');assert.ok(p.elements.every(e=>e.visibility==='unverified'));assert.ok(p.elements.every(e=>!e.visibility_evidence?.some(v=>v.method==='loaded_glyph_outline_inside_rect_clip')));
  const render=async(bytes:Buffer)=>(await captureNativePages(bytes,[1],[])).get(1)!.render_sha256;
  assert.notEqual(await render(bytes),await render(await make(false)),'Real PDFKit ink differs even when the PDF.js substitute outline fits');
});

test('fraction slot boundaries retain mixed numbers, units and ambiguity in regional comparisons',async()=>{
  assert.deepEqual(numericSlots('.5 -.5 −．５'),['.5','-.5','-.5']);assert.deepEqual(numericSlots('1\u0085/\u00852 －５００'),['1/2','-500']);assert.deepEqual(numericSlots('⅛ pound ¼ butter ½ olives １／２'),['1/8','1/4','1/2','1/2']);assert.deepEqual(numericSlots('1½ 1 1/2 -¼'),['1','1/2','1','1/2','-1/4']);assert.notEqual(numericPattern('½ cup'),numericPattern('½ kg'));assert.equal(numericPattern('2원)/'),'#원)/');assert.equal(numericPattern('2 만–/'),'# 만–/');
  const page=(key:string,text:string,uncertain=false):PageData=>({page_id:key,asset_id:key,page:1,width:960,height:540,coordinate_system:'normalized',source_transform:[],hidden:false,text:'',comparison_basis:'raster_ocr',ocr_text:text,ocr_unresolved_text:uncertain?'Unknown region':'',raster:{sha256:key.repeat(64),width:960,height:540,renderer:'fixture',environment:'fixture'},elements:[{observation_id:key,kind:'text',text,normalized_text:text,bbox:[.1,.1,.4,.05],reading_order:0,availability:'available',method:'vision_ocr',source_ref:key,provenance:'inferred',visibility:'visible'},...(uncertain?[{observation_id:key+'u',kind:'text' as const,text:'Unknown region',normalized_text:'Unknown region',bbox:[.1,.5,.4,.05] as [number,number,number,number],reading_order:1,availability:'available' as const,method:'vision_ocr',source_ref:key+'u',provenance:'inferred' as const,visibility:'uncertain' as const}]:[])],notes:null,capabilities:{text:'available',notes:'unavailable',hidden_slides:'unavailable',animation:'unavailable',structure:'unavailable',preview:'available'},coverage_gaps:[]});
  const a=page('a','½ cup olives',true),b=page('b','1/4 cup olives',true),regional=changes(a,b).filter(c=>c.kind==='text_modified');assert.equal(regional.length,1);assert.equal(regional[0].text_scope,'region');assert.equal(regional[0].text_assessment,'inferred');assert.deepEqual(regional[0].evidence.map(e=>e.quote),['½ cup olives','1/4 cup olives']);
  assert.equal(changes(a,page('c','1 4 cup olives',true)).filter(c=>c.kind==='text_modified').length,0,'Separate digits cannot verify one fractional slot');assert.equal(changes(a,page('d','¼ kg olives',true)).filter(c=>c.kind==='text_modified').length,0,'Regional numeric matching must preserve units');
  for(const [fraction,integer,key]of [['1/2 cup olives','12 cup olives','e'],['½ cup olives','14 cup olives','f']]){assert.equal(changes(page('a',fraction,true),page(key,integer,true)).filter(c=>c.kind==='text_modified').length,0,'A dropped fraction slash cannot become a regional value edit');const full=changes(page('a',fraction),page(key,integer));assert.ok(!full.some(c=>c.kind==='text_modified'));assert.ok(full.some(c=>c.coverage_gaps.some(g=>g.reason==='ocr_region_missing_or_numeric_ambiguity_withheld')));}
  const notationCases=JSON.parse(await readFile('tests/fixtures/numeric-notation.json','utf8')) as {text:string,supported:boolean}[];
  for(const {text,supported}of notationCases){assert.equal(numericNotationSupported(text),supported,text);if(!supported)assert.equal(numericShape(text),null,text);}
  for(const [before,after]of [['/½ cup olives','/¼ cup olives'],['/+2 cup olives','/+3 cup olives'],['/ .2 cup olives','/ .3 cup olives'],['／－２ cup olives','／－３ cup olives'],['Amount 1/\u3164 cup olives','Amount 3/\u3164 cup olives'],['Amount 2원)/ cup olives','Amount 3원)/ cup olives'],['Ratio .5/2 cup olives','Ratio .6/2 cup olives'],['Ratio 1/2.3 cup olives','Ratio 1/2.4 cup olives'],['Ratio 1/2,000 cup olives','Ratio 1/2,100 cup olives']])for(const uncertain of [false,true]){const delta=changes(page('a',before,uncertain),page('g',after,uncertain));assert.ok(!delta.some(c=>c.kind==='text_modified'),before);assert.ok(delta.some(c=>c.coverage_gaps.length));}
  assert.equal(numericShape('1½'),'decimal,fraction');assert.equal(numericPattern('1½'),'##/#');assert.equal(numericPattern('1 1/2'),'# #/#');
});

test('actual native OCR withholds incomplete fraction lines at the production call site',native,async()=>{
  const bytes=await pdf(d=>{d.font(resolve('node_modules/pdfjs-dist/standard_fonts/LiberationSans-Regular.ttf')).fontSize(32);for(const [i,text]of ['Amount /2 cup olives','Amount 1/ cup olives','Amount /+2 cup olives'].entries())d.text(text,80,150+i*120,{lineBreak:false});});
  const result=await recognizePdf(bytes,1),lines=result.lines.filter(l=>/olives/i.test(l.text));
  assert.deepEqual(lines.map(l=>l.text.toLowerCase().replace(/\s+/gu,' ').trim()),['amount /2 cup olives','amount 1/ cup olives','amount /+2 cup olives'],JSON.stringify(result.lines));
  for(const line of lines){assert.ok(line.text.includes('/'),JSON.stringify(line));assert.equal(line.numeric_status,'unsupported_notation',JSON.stringify(line));assert.equal(line.numeric_consensus,false);}
});

test('native fractional scan changes retain original readings and inferred evidence',native,async()=>{
  // Numeric agreement cannot raise a low whole-line confidence. Retain this
  // actual AppleGothic low-confidence case as a negative control.
  const lowBytes=await scanned('½ cup olives'),lowNative=await recognizePdf(lowBytes,1),lowLine=lowNative.lines.find(l=>l.text.includes('olives'))!;
  assert.equal(lowLine.numeric_status,'verified');assert.ok(lowLine.confidence<.5);const [low]=await extractPdf(lowBytes,'sha256:low-fraction',{ocr:'off'});await supplementPdfOcr(low,lowBytes,{nativeResult:lowNative});assert.equal(low.elements.find(e=>e.text===lowLine.text)!.visibility,'uncertain');
  assert.ok(GlobalFonts.registerFromPath(resolve('node_modules/pdfjs-dist/standard_fonts/LiberationSans-Regular.ttf'),'DocverFractionFixture'));
  const fractionScan=(text:string)=>{const c=createCanvas(1920,1080),ctx=c.getContext('2d');ctx.fillStyle='white';ctx.fillRect(0,0,c.width,c.height);ctx.fillStyle='black';ctx.font='48px DocverFractionFixture';ctx.fillText('Recipe ingredients',120,140);ctx.fillText(text,120,300);return pdf(d=>d.image(c.toBuffer('image/png'),0,0,{width:960,height:540}));};
  const pages:PageData[]=[];
  for(const [key,text]of [['half','1/2 cup finely chopped olives'],['quarter','1/4 cup finely chopped olives']]){const bytes=await fractionScan(text),observed=await recognizePdf(bytes,1),line=observed.lines.find(l=>l.text.includes('olives'));assert.ok(line);assert.equal(line.numeric_status,'verified',JSON.stringify(line));assert.equal(line.numeric_consensus,true);assert.equal(numericSlots(line.text).length,1);const [p]=await extractPdf(bytes,'sha256:'+key,{ocr:'off'});await supplementPdfOcr(p,bytes,{nativeResult:observed});assert.ok(p.elements.some(e=>e.text===line.text&&e.provenance==='inferred'&&e.visibility==='visible'),JSON.stringify({line,elements:p.elements}));pages.push(p);}
  const edits=changes(pages[0],pages[1]).filter(c=>c.kind==='text_modified');assert.equal(edits.length,1);assert.equal(edits[0].text_assessment,'inferred');assert.ok(edits[0].evidence.every(e=>e.method==='vision_ocr'));
});

test('native tiled Korean/English OCR retains signs and amounts and caches exact evidence',native,async()=>{
  const folder=await mkdtemp(join(tmpdir(),'docver-ocr-test-'));
  try{
    const bytes=await scanned('금액 -1,234.50 / +1.25% / 120억'),r=await recognizePdf(bytes,1,{cacheRoot:folder});
    const text=normalize(r.lines.map(l=>l.text).join(' '));
    for(const expected of ['계약','Contract','-1,234.50','+1.25%','120억'])assert.ok(text.replace(/\s/gu,'').includes(expected),text);
    assert.equal(r.language_correction,false);assert.deepEqual(r.languages,['ko-KR','en-US']);assert.ok(r.lines.filter(l=>/[0-9]/.test(l.text)).every(l=>l.numeric_consensus),JSON.stringify(r.lines.map(l=>({text:l.text,readings:l.numeric_readings,consensus:l.numeric_consensus}))));
    const cache=join(folder,'ocr'),files=(await readdir(cache)).filter(p=>p.endsWith('.json'));let file='';for(const name of files)if(JSON.parse(await readFile(join(cache,name),'utf8')).value.ocr_performed)file=name;assert.ok(file);const original=await readFile(join(cache,file));
    assert.deepEqual(await recognizePdf(bytes,1,{cacheRoot:folder}),r);assert.deepEqual(await readFile(join(cache,file)),original);
    await writeFile(join(cache,file),'corrupt');assert.deepEqual(await recognizePdf(bytes,1,{cacheRoot:folder}),r);
  }finally{await rm(folder,{recursive:true,force:true});}
});

test('scan changes are inferred, link to raster evidence, and never invent original raw text',native,async()=>{
  const a=(await extractPdf(await scanned('예상 매출 100억'),'sha256:scan-a',{ocr:'auto'}))[0],b=(await extractPdf(await scanned('예상 매출 120억'),'sha256:scan-b',{ocr:'auto'}))[0];
  assert.equal(a.text,'');assert.equal(b.text,'');assert.equal(a.ocr?.mode,'scan');assert.ok(comparisonText(a).includes('100억'));assert.ok(comparisonText(b).includes('120억'));
  const found=changes(a,b).filter(c=>c.kind==='text_modified');assert.equal(found.length,1);assert.equal(found[0].text_assessment,'inferred');assert.ok(found[0].coverage_gaps.some(g=>g.reason==='ocr_inferred_text_requires_source_review'));assert.ok(found[0].evidence.every(e=>e.method==='vision_ocr'&&e.observation_id));
});

test('mixed raster content supplements live text without duplication or certifying hidden glyphs',native,async()=>{
  const bytes=await pdf(d=>{d.fontSize(28).text('Observed header',55,25,{lineBreak:false});d.image(scan('이미지 매출 120억'),0,100,{width:960,height:440});});
  const p=(await extractPdf(bytes,'sha256:mixed',{ocr:'auto'}))[0];
  assert.ok(p.elements.some(e=>e.method==='pdf_text'&&e.text==='Observed header'));assert.ok(p.elements.some(e=>e.method==='vision_ocr'&&e.text.includes('120억')));
  assert.equal(p.elements.filter(e=>e.text==='Observed header').length,1);assert.ok(p.text.includes('Observed header'));assert.ok(!p.text.includes('120억'));assert.equal(p.ocr?.mode,'supplement');assert.ok(!p.visible_text?.includes('120억'),'Raw visible-text projection must not absorb an OCR annex');
  const hidden=await pdf(d=>{d.image(scan('예상 매출 120억'),0,0,{width:960,height:540});d.addContent('3 Tr');d.fontSize(24).text('Revenue 999',50,80,{lineBreak:false});});
  const q=(await extractPdf(hidden,'sha256:prior',{ocr:'auto'}))[0];assert.equal(q.ocr?.mode,'scan');assert.ok(q.text.includes('999'));assert.ok(q.elements.find(e=>e.method==='pdf_text')?.visibility==='hidden_render_mode');assert.ok(comparisonText(q).includes('120억'));assert.ok(!comparisonText(q).includes('999'));
});

test('OCR agreement never clears operator strike or occlusion uncertainty',native,async()=>{
  const bytes=await pdf(d=>{d.fontSize(28).text('Revenue 1.5',50,100,{lineBreak:false});d.moveTo(50,110).lineTo(210,110).lineWidth(1).stroke('red');});
  const p=(await extractPdf(bytes,'sha256:struck',{ocr:'auto'}))[0];assert.ok(p.elements[0].visibility!=='visible');assert.ok(p.unresolved_text?.includes('Revenue'));assert.ok(p.ocr);assert.ok(p.coverage_gaps.some(g=>g.feature==='ocr_verification'));
});

test('native OCR follows rotated cropped PDF coordinates rather than guessing source boxes',native,async()=>{
  for(const rotation of [0,90,180,270]){
    const positions:Record<number,[number,number]>={0:[100,100],90:[100,400],180:[800,400],270:[800,100]};
    const bytes=await pdf(d=>{(d.page.dictionary.data as any).Rotate=rotation;(d.page.dictionary.data as any).CropBox=[20,30,940,510];const [x,y]=positions[rotation];d.save().translate(x,y).rotate(-rotation).fontSize(28).text('Revenue 123.50',0,0,{lineBreak:false}).restore();});
    const page=(await extractPdf(bytes,'sha256:rotation-'+rotation,{ocr:'all'}))[0];assert.equal(page.ocr?.status,'available');
    const rendered=await recognizePdf(bytes,1);const raw=page.elements.find(e=>e.method==='pdf_text')!,line=rendered.lines.find(l=>l.text.includes('123.50'));assert.ok(line,JSON.stringify({rotation,lines:rendered.lines}));
    const a=raw.bbox,b=line.bbox,intersection=Math.max(0,Math.min(a[0]+a[2],b[0]+b[2])-Math.max(a[0],b[0]))*Math.max(0,Math.min(a[1]+a[3],b[1]+b[3])-Math.max(a[1],b[1]));
    assert.ok(intersection/(b[2]*b[3])>0.7,JSON.stringify({rotation,raw:a,ocr:b}));assert.ok(!page.coverage_gaps.some(g=>g.reason==='native_raster_viewport_geometry_disagrees'));
  }
});

test('rendered OCR supplies inferred comparison for unsupported text paint without mutating raw uncertainty',native,async()=>{
  const make=(value:string)=>pdf(d=>{d.addContent('2 Tr');d.fontSize(28).text('Revenue '+value,70,100,{lineBreak:false});});
  const a=(await extractPdf(await make('100'),'sha256:outlined-a',{ocr:'auto'}))[0],b=(await extractPdf(await make('120'),'sha256:outlined-b',{ocr:'auto'}))[0];
  assert.ok(a.unresolved_text?.includes('100'));assert.ok(b.unresolved_text?.includes('120'));assert.equal(a.comparison_basis,'hybrid_regions_v1');
  const delta=changes(a,b).filter(c=>c.kind==='text_modified');assert.equal(delta.length,1);assert.equal(delta[0].text_assessment,'inferred');
  const duplicate={...b,raster:{...b.raster!,sha256:a.raster!.sha256},ocr:{...b.ocr!,render_sha256:a.ocr!.render_sha256}};assert.equal(changes(a,duplicate).filter(c=>c.kind==='text_modified').length,0);
});

test('a missing OCR region is a visual observation gap, never a precise numeric deletion',native,async()=>{
  const a=(await extractPdf(await scanned('예상 매출 100억'),'sha256:present',{ocr:'auto'}))[0],b=(await extractPdf(await scanned(''),'sha256:missing-region',{ocr:'auto'}))[0];
  const delta=changes(a,b);assert.equal(delta.filter(c=>c.kind==='text_modified').length,0);assert.ok(delta.some(c=>c.coverage_gaps.some(g=>g.reason==='ocr_region_missing_or_numeric_ambiguity_withheld')));assert.ok(delta.some(c=>c.kind==='visual_region_changed'&&c.evidence.every(e=>e.method==='native_raster'&&e.render_sha256)));
});

test('a supported numeric region remains comparable beside unreadable content',()=>{
  const make=(key:string,value:string):PageData=>({page_id:key,asset_id:key,page:1,width:960,height:540,coordinate_system:'normalized',source_transform:[],hidden:false,text:'Revenue '+value+'\nuncertain body',visible_text:'Revenue '+value,unresolved_text:'uncertain body',elements:[{observation_id:key,kind:'text',text:'Revenue '+value,normalized_text:'Revenue '+value,bbox:[0.1,0.1,0.3,0.08],reading_order:0,availability:'available',method:'pdf_text',source_ref:'header',provenance:'observed',visibility:'visible'}],notes:null,capabilities:{text:'available',notes:'unavailable',hidden_slides:'unavailable',animation:'unavailable',structure:'unavailable',preview:'available'},coverage_gaps:[{feature:'pdf_visibility',reason:'unknown_body'}]});
  const delta=changes(make('a','100'),make('b','120')),numeric=delta.filter(c=>c.kind==='text_modified');assert.equal(numeric.length,1);assert.equal(numeric[0].text_scope,'region');assert.equal(numeric[0].text_assessment,'observed');assert.equal(numeric[0].before,'Revenue 100');assert.ok(delta.some(c=>c.kind==='coverage_gap'));
});

test('rasterized strike is inferred from pixels while underline stays readable',native,async()=>{
  const line=(strike:boolean,underline=false)=>pdf(d=>{const c=createCanvas(1920,1080),ctx=c.getContext('2d');ctx.fillStyle='white';ctx.fillRect(0,0,1920,1080);ctx.font='48px Arial';ctx.fillStyle='black';ctx.fillText('Revenue 100',120,300);if(strike){ctx.strokeStyle='red';ctx.lineWidth=3;ctx.beginPath();ctx.moveTo(120,underline?315:282);ctx.lineTo(420,underline?315:282);ctx.stroke();}d.image(c.toBuffer('image/png'),0,0,{width:960,height:540});});
  const a=(await extractPdf(await line(false),'sha256:clean',{ocr:'auto'}))[0],b=(await extractPdf(await line(true),'sha256:raster-strike',{ocr:'auto'}))[0],u=(await extractPdf(await line(true,true),'sha256:underline',{ocr:'auto'}))[0];
  assert.ok(b.elements.some(e=>e.visibility==='struck_inferred'&&e.visibility_evidence?.some(v=>v.method==='raster_horizontal_strike_candidate')),JSON.stringify(b.elements));assert.ok(!u.elements.some(e=>e.visibility==='struck_inferred'));assert.ok(changes(a,b).some(c=>c.kind==='text_struck_through'&&c.appearance_assessment==='inferred'));
});

test('native batches distinguish OCR and render-only and changed evidence excludes stable numbers',native,async()=>{
  const bytes=await pdf(d=>{d.fontSize(24).text('Revenue 500',50,70,{lineBreak:false});d.text('Cost 100',50,150,{lineBreak:false});}),observations=await captureNativePages(bytes,[1],[]);
  assert.equal(observations.get(1)?.ocr_performed,false);assert.equal(observations.get(1)?.lines.length,0);
  const a=(await extractPdf(bytes,'sha256:cost-a',{ocr:'auto'}))[0],b=(await extractPdf(await pdf(d=>{d.fontSize(24).text('Revenue 500',50,70,{lineBreak:false});d.text('Cost 120',50,150,{lineBreak:false});}),'sha256:cost-b',{ocr:'auto'}))[0];
  const delta=changes(a,b).find(c=>c.kind==='text_modified')!;assert.ok(delta);assert.deepEqual(delta.evidence.map(e=>e.quote),['Cost 100','Cost 120']);
});

test('native page lookup reads its transactional index without parsing a full report',native,async()=>{
  const folder=await mkdtemp(join(tmpdir(),'docver-index-')),service=new DesktopService(join(folder,'library'));
  try{const file=join(folder,'source.pdf');await writeFile(file,await pdf(d=>d.fontSize(24).text('Indexed page 123',50,80)));const project=await service.create('Index',[{label:'v1',files:[file]}]);const {report}=await service.run(project.project_id);const p=report.revisions[0].pages[0];
    service.store.report=()=>{throw new Error('Full report load must not be called')};const result=service.pageData(project.project_id,report.report_id,p.page_id);assert.equal(result.page.page_id,p.page_id);assert.equal(result.page.text,p.text);assert.ok(result.page.raster);
    assert.equal(service.store.db.prepare('SELECT count(*) AS n FROM native_pages WHERE report_id=?').get(report.report_id)?.n,1);
  }finally{service.close();await rm(folder,{recursive:true,force:true});}
});

test('OCR alternative evidence is complete, bounded and keeps emoji across chunk boundaries',native,async()=>{
  const folder=await mkdtemp(join(tmpdir(),'docver-ocr-chunks-')),service=new DesktopService(join(folder,'library'));
  try{const file=join(folder,'source.pdf');await writeFile(file,await pdf(d=>d.fontSize(24).text('Contract evidence',50,80)));const project=await service.create('OCR chunks',[{label:'v1',files:[file]}]);const result=await service.run(project.project_id,undefined,undefined,false),report=result.report,e=report.revisions[0].pages[0].elements[0];
    const alternative=('한글 대안 😀 금액 ').repeat(600)+' -1,234.56 끝  ';e.method='vision_ocr';e.provenance='inferred';e.ocr={confidence:0.5,confidence_scope:'line',numeric_consensus:false,ambiguous:true,alternatives:[{text:e.text,confidence:0.5,truncated:false},{text:alternative,confidence:0.4,truncated:false}]};report.report_id=id('rpt',['constructed-contract-fixture',report]);service.commit(project.project_id,result);
    const query=service.queryService(project.project_id);let restored='',offset:number|null=0;
    while(offset!==null){const response=query.query('get_element',{project_id:project.project_id,report_id:report.report_id,observation_id:e.observation_id,text_length:1,ocr_alternative_index:1,ocr_alternative_offset:offset,ocr_alternative_length:701,max_output_tokens:8000});assert.ok(Buffer.byteLength(JSON.stringify(response))<=8000);const value=response.items[0].ocr_alternative as {text:string;next_text_offset:number|null};assert.ok(!/[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]/.test(value.text));restored+=value.text;offset=value.next_text_offset;}
    assert.equal(restored,alternative);assert.ok(service.store.report(project.project_id,report.report_id).revisions[0].pages[0].elements[0].ocr?.alternatives[1].text===alternative);
    const database=join(service.root,'docver.sqlite'),before=byteHash(await readFile(database)),client=new Client({name:'ocr-evidence-test',version:'1.0.0'}),transport=new StdioClientTransport({command:process.execPath,args:['--import','tsx',resolve('apps/mcp/main.ts'),'--store',service.root,'--project',project.project_id],stderr:'pipe'});
    try{await client.connect(transport);let mcpText='',next:number|null=0;while(next!==null){const response=await client.callTool({name:'get_element',arguments:{project_id:project.project_id,report_id:report.report_id,observation_id:e.observation_id,text_length:1,ocr_alternative_index:1,ocr_alternative_offset:next,ocr_alternative_length:200,max_output_tokens:8000}});assert.notEqual(response.isError,true);assert.ok(Buffer.byteLength(JSON.stringify(response))<=8000);const row=(response.structuredContent as QueryResult).items[0].ocr_alternative as {text:string;next_text_offset:number|null};assert.ok(row);mcpText+=row.text;next=row.next_text_offset;}assert.equal(mcpText,alternative);}finally{await client.close();}assert.equal(byteHash(await readFile(database)),before);
  }finally{service.close();await rm(folder,{recursive:true,force:true});}
});

test('OOXML entity decoding preserves literal character references and actual Unicode separately',async()=>{
  const deck=new (pptxgen as unknown as typeof pptxgen.default)();deck.addSlide().addText('literal &#x1F600; and actual 😀',{x:1,y:1,w:8,h:1});const bytes=await deck.write({outputType:'nodebuffer'}) as Buffer;
  const text=extractPptx(bytes,'sha256:entities')[0].text;assert.equal(text,'literal &#x1F600; and actual 😀');
});

test('historical range queries retain their engine instead of silently adopting new regional inference',async()=>{
  const folder=await mkdtemp(join(tmpdir(),'docver-legacy-range-')),store=new Store(folder);
  try{const make=(value:string)=>pdf(d=>{d.fontSize(24).text('Revenue '+value,50,70,{lineBreak:false});d.addContent('2 Tr');d.text('Uncertain body',50,180,{lineBreak:false});}),a=(await extractPdf(await make('100'),'sha256:legacy-a'))[0],b=(await extractPdf(await make('120'),'sha256:legacy-b'))[0];
    let snapshot:ReportData={schema_version:'0.1.0',engine_version:'0.1.0-native.1',report_id:'rpt_legacy',project_id:'prj_legacy',timeline_revision_id:'timeline_test',mapping_revision_id:'mapping_test',schema_hash:'2b8e722edca65c1809f550b3434ae565e78d1567009d92be803c68ede917c2c1',observation_environment:{fixture:'historical-contract'},revisions:[rev(a,'v1'),rev(b,'v2')],matches:[{from_page_id:a.page_id,to_page_id:b.page_id,score:1,status:'inferred',reasons:['fixture']}],candidates:[],mapping_decisions:[],lineages:[{entity_id:'entity',page_ids:[a.page_id,b.page_id],status:'inferred'}],changes:[],coverage_gaps:[]};
    assert.ok(Report.safeParse(snapshot).success);const run=store.beginRun(snapshot.project_id,'Legacy');store.finishRun(run,snapshot);const frozen=store.db.prepare('SELECT body FROM reports WHERE id=?').get(snapshot.report_id)?.body,stored=new QueryService(store,new Set([snapshot.project_id]));
    const info=stored.query('get_report',{project_id:snapshot.project_id,report_id:snapshot.report_id});assert.equal(info.schema_version,SCHEMA_VERSION);assert.equal(info.items[0].schema_version,'0.1.0');await exportReport(stored,snapshot.project_id,snapshot.report_id,join(folder,'legacy-export'));assert.equal(JSON.parse(await readFile(join(folder,'legacy-export/report.json'),'utf8')).schema_version,'0.1.0');assert.equal(JSON.parse(await readFile(join(folder,'legacy-export/manifest.json'),'utf8')).schema_version,'0.1.0');assert.equal(store.db.prepare('SELECT body FROM reports WHERE id=?').get(snapshot.report_id)?.body,frozen);
    const q=new QueryService(store,new Set(['prj_legacy']),()=>snapshot),args={project_id:'prj_legacy',report_id:'rpt_legacy',mode:'range_net',from:'v1',to:'v2'};
    assert.ok(q.changeSet(args).every(c=>c.schema_version==='0.1.0'));assert.equal(q.changeSet(args).filter(c=>c.kind==='text_modified').length,0);snapshot={...snapshot,schema_version:SCHEMA_VERSION,engine_version:ENGINE_VERSION};assert.equal(q.changeSet(args).filter(c=>c.kind==='text_modified'&&c.text_scope==='region').length,1);
    snapshot={...snapshot,engine_version:'unknown historical engine'};assert.throws(()=>q.changeSet(args),{code:'ENGINE_VERSION_UNAVAILABLE'});assert.deepEqual(q.changeSet({...args,mode:'history'}),[]);
  }finally{store.close();await rm(folder,{recursive:true,force:true});}
});

test('raster document tables retain inferred rows, columns and original-source distinction',native,async(t)=>{
  if(!(await visionInfo())?.document_structure){t.skip('Document structure requires macOS26+');return;}
  const c=createCanvas(1600,1000),ctx=c.getContext('2d');ctx.fillStyle='white';ctx.fillRect(0,0,1600,1000);ctx.strokeStyle='black';ctx.lineWidth=3;
  for(const x of [100,700,1300]){ctx.beginPath();ctx.moveTo(x,150);ctx.lineTo(x,750);ctx.stroke();}for(const y of [150,350,550,750]){ctx.beginPath();ctx.moveTo(100,y);ctx.lineTo(1300,y);ctx.stroke();}
  ctx.fillStyle='black';ctx.font='44px AppleGothic';for(const [text,x,y] of [['분기',140,260],['매출',740,260],['Q1',140,460],['100',740,460],['Q2',140,660],['120',740,660]] as [string,number,number][])ctx.fillText(text,x,y);
  const bytes=await pdf(d=>d.image(c.toBuffer('image/png'),0,0,{width:960,height:540})),p=(await extractPdf(bytes,'sha256:table-scan',{ocr:'auto'}))[0];
  assert.equal(p.ocr?.structure_status,'available');assert.ok((p.ocr?.table_count??0)>=1);const cells=p.elements.filter(e=>e.table?.origin==='vision_table_inferred');assert.ok(cells.some(e=>e.text.includes('100'))&&cells.some(e=>e.text.includes('120')));assert.ok(cells.every(e=>e.provenance==='inferred'&&e.table?.assessment==='inferred'));
});

test('render safety rejects unused external and nested workbook relationships before conversion',()=>{
  const external=strToU8('<Relationships><Relationship TargetMode="External" Target="http://127.0.0.1/private"/></Relationships>');
  assert.throws(()=>validateRenderPackage(zipSync({'unused/_rels/link.rels':external})),{code:'EXTERNAL_RELATIONSHIP'});
  assert.throws(()=>validateRenderPackage(zipSync({'unused/_rels/link.rels':strToU8('<Relationships><Relationship TargetMode="Exte&#114;nal" Target="f&#105;le:///private/picture.png"/></Relationships>')})),{code:'EXTERNAL_RELATIONSHIP'});
  assert.doesNotThrow(()=>validateRenderPackage(zipSync({'unused/_rels/link.rels':strToU8('<Relationships><Relationship Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink" TargetMode="External" Target="https://example.test/"/></Relationships>')})));
  const xlsx=zipSync({'xl/_rels/workbook.xml.rels':external});assert.throws(()=>validateRenderPackage(zipSync({'ppt/embeddings/test.xlsx':xlsx})),{code:'EXTERNAL_RELATIONSHIP'});
  assert.throws(()=>validateRenderPackage(zipSync({'ppt/embeddings/oleObject1.bin':new Uint8Array([0])})),{code:'ACTIVE_CONTENT'});
});

test('real LibreOffice preserves hidden slide indexes, renders objects and normalizes volatile metadata',office,async()=>{
  const folder=await mkdtemp(join(tmpdir(),'docver-office-test-'));
  try{
    const deck=new (pptxgen as unknown as typeof pptxgen.default)();deck.layout='LAYOUT_WIDE';
    for(let n=1;n<=5;n++){const slide=deck.addSlide();slide.hidden=n===2||n===4;slide.addText('한글 계약 '+n,{x:1,y:0.5,w:8,h:1,fontFace:'AppleGothic',fontSize:24});slide.addTable([['분기','매출'],['Q1',String(n*100)]].map(row=>row.map(text=>({text}))),{x:1,y:2,w:5,h:1,fontFace:'AppleGothic'});slide.addImage({data:'image/png;base64,'+scan('이미지').toString('base64'),x:7,y:2,w:4,h:2});}
    const bytes=await deck.write({outputType:'nodebuffer'}) as Buffer,path=join(folder,'한글 deck.pptx');await writeFile(path,bytes);
    const pages=extractPptx(bytes,'sha256:'+byteHash(bytes));assert.deepEqual(pages.filter(p=>p.hidden).map(p=>p.page),[2,4]);
    const first=await preparePptxPreview(path,bytes,pages,join(folder,'cache'));assert.ok(first);assert.equal(pages.length,5);assert.ok(pages.every(p=>p.preview?.page===p.page&&p.capabilities.preview==='available'));assert.ok(pages.every(p=>!p.preview?.warnings.some(w=>w.startsWith('rendered_text_differs'))));
    const second=await convertPptx(path);assert.equal(byteHash(first),byteHash(second));
    const rendered=await extractPdf(first,'sha256:derived');assert.equal(rendered.length,5);for(let i=0;i<5;i++)assert.ok(rendered[i].text.includes(String(i+1)),rendered[i].text);
    const missing=unzipSync(bytes);missing['ppt/slides/slide1.xml']=strToU8(new TextDecoder().decode(missing['ppt/slides/slide1.xml']).replaceAll('AppleGothic','Docver Missing Font'));
    const altered=zipSync(missing),file2=join(folder,'missing.pptx');await writeFile(file2,altered);const alteredPages=extractPptx(altered,'sha256:missing');await preparePptxPreview(file2,altered,alteredPages,join(folder,'cache'));
    assert.ok(alteredPages[0].preview?.warnings.some(w=>w==='font_substitution_possible:Docver Missing Font'));
  }finally{await rm(folder,{recursive:true,force:true});}
});

test('native subprocess timeout terminates the complete process group',async()=>{
  const folder=await mkdtemp(join(tmpdir(),'docver-tool-test-'));
  try{const file=join(folder,'pid'),script='import os,time,signal; p=os.fork(); signal.signal(signal.SIGTERM,signal.SIG_IGN) if not p else open('+JSON.stringify(file)+',"w").write(str(p)); time.sleep(30)';
    await assert.rejects(runTool('/usr/bin/python3',['-c',script],{timeout:1500}),{code:'TOOL_TIMEOUT'});
    const pid=Number(await readFile(file,'utf8'));assert.throws(()=>process.kill(pid,0),{code:'ESRCH'});
  }finally{await rm(folder,{recursive:true,force:true});}
});


test('regional inference cannot cross unchanged or unreadable overlapping numeric rows',()=>{
  const make=(key:string):PageData=>({page_id:key,asset_id:key,page:1,width:960,height:540,coordinate_system:'normalized',source_transform:[],hidden:false,text:'Revenue 100\nRevenue 120',visible_text:'Revenue 100\nRevenue 120',unresolved_text:'unknown footer',elements:[100,120].map((n,i)=>({observation_id:key+i,kind:'text',text:'Revenue '+n,normalized_text:'Revenue '+n,bbox:[.1,.1+i*.07,.3,.08],reading_order:i,availability:'available',method:'vision_ocr',provenance:'inferred',source_ref:key+i,visibility:'visible'})),notes:null,capabilities:{text:'available',notes:'unavailable',hidden_slides:'unavailable',animation:'unavailable',structure:'unavailable',preview:'available'},coverage_gaps:[],raster:{sha256:key.repeat(64),width:960,height:540,renderer:'test',environment:'test'}});
  const a=make('a'),b=make('b');assert.equal(changes(a,b).filter(c=>c.kind==='text_modified').length,0);assert.ok(changes(a,b).some(c=>c.kind==='visual_region_changed'));
  a.comparison_basis=b.comparison_basis='raster_ocr';a.ocr_text=a.text;b.ocr_text='Revenue 120';b.ocr_unresolved_text='Revenue 100';b.elements[0].visibility='uncertain';
  assert.equal(changes(a,b).filter(c=>c.kind==='text_modified').length,0);
  b.elements.shift();assert.equal(changes(a,b).filter(c=>c.kind==='text_modified').length,0);
});

test('mixed-page raster strike evidence retains inferred OCR provenance',native,async()=>{
  const make=(strike:boolean)=>pdf(d=>{const c=createCanvas(1920,1080),ctx=c.getContext('2d');ctx.fillStyle='white';ctx.fillRect(0,0,1920,1080);ctx.font='48px Arial';ctx.fillStyle='black';ctx.fillText('Revenue 100',120,300);if(strike){ctx.strokeStyle='red';ctx.lineWidth=2;ctx.beginPath();ctx.moveTo(120,282);ctx.lineTo(390,282);ctx.stroke();}d.image(c.toBuffer('image/png'),0,0,{width:960,height:540});d.fontSize(24).text('Observed header',50,25,{lineBreak:false});});
  const a=(await extractPdf(await make(false),'sha256:mixed-strike-a',{ocr:'auto'}))[0],b=(await extractPdf(await make(true),'sha256:mixed-strike-b',{ocr:'auto'}))[0];
  assert.equal(a.ocr?.mode,'supplement');const event=changes(a,b).find(c=>c.kind==='text_struck_through');assert.ok(event);assert.equal(event.appearance_assessment,'inferred');assert.ok(event.evidence.every(e=>e.method==='vision_ocr'&&e.provenance==='inferred'));assert.ok(event.coverage_gaps.some(g=>g.reason==='ocr_inferred_text_requires_source_review'));
});

test('PPTX text coverage is spatial, canonically normalized and numeric-token exact',()=>{
  const e={text:'한글 10',bbox:[.1,.1,.3,.1]} as any;
  assert.equal(missingRenderedText([e],[{text:'한글'.normalize('NFD')+' 10',bbox:[.12,.12,.2,.04]}]),false);
  assert.equal(missingRenderedText([e],[{text:'한글 100',bbox:[.12,.12,.2,.04]}]),true);
  assert.equal(missingRenderedText([e],[{text:'한글 10',bbox:[.7,.7,.2,.04]}]),true);
});

test('metadata canonicalization preserves stream bytes and nonmetadata dictionary strings',async()=>{
  const d=new PDFDocument({size:[960,540],margin:0,compress:false,info:{Title:'/CreationDate(D:20261019000000) /ID [<abcdef><abcdef>]'}}),chunks:Buffer[]=[];d.on('data',b=>chunks.push(b));const done=new Promise<Buffer>(res=>d.on('end',()=>res(Buffer.concat(chunks))));
  d.addContent('% /CreationDate(D:20261019000000) /ID [<abcdef><abcdef>] /DocChecksum /deadbeef /Type /Metadata');d.fontSize(20).text('Visible 2026-10-19T04:00:00',50,50);d.end();const bytes=await done,normalized=normalizeConvertedPdf(bytes);
  const streams=(b:Buffer)=>[...b.toString('latin1').matchAll(/stream\r?\n([\s\S]*?)endstream/g)].map(m=>m[1]);assert.deepEqual(streams(normalized),streams(bytes));
  assert.ok(normalized.toString('latin1').includes('/CreationDate(D:20261019000000) /ID [<abcdef><abcdef>] /DocChecksum /deadbeef'));
});

test('embedded SVG resource guards and renderer read isolation contain local dependencies',office,async()=>{
  const folder=await mkdtemp(join(tmpdir(),'docver-svg-test-'));try{
    const c=createCanvas(200,200);c.getContext('2d').fillRect(0,0,200,200);const Pptx=(pptxgen as any).default??pptxgen,p=new Pptx();p.addSlide().addImage({data:'image/png;base64,'+c.toBuffer('image/png').toString('base64'),x:1,y:1,w:3,h:3});
    const zip=unzipSync(await p.write({outputType:'nodebuffer'}) as Buffer),name=Object.keys(zip).find(n=>/^ppt\/media\/.*\.png$/.test(n))!,external=join(folder,'outside.txt');await writeFile(external,'private fixture');
    for(const href of ['file://'+external,'https://example.invalid/image.png','&#x66;ile://'+external]){zip[name]=strToU8(`<svg xmlns="http://www.w3.org/2000/svg"><image href="${href}"/></svg>`);assert.throws(()=>validateRenderPackage(zipSync(zip)),(e:any)=>e.code==='EXTERNAL_RELATIONSHIP');}
    zip[name]=strToU8('<svg xmlns="http://www.w3.org/2000/svg"><rect width="200" height="200" fill="red"/></svg>');assert.doesNotThrow(()=>validateRenderPackage(zipSync(zip)));
    const job=join(folder,'job');await import('node:fs/promises').then(fs=>fs.mkdir(job));const profile=rendererSandbox(await realpath(job),officeExecutable()!)+'(allow process-exec (literal "/bin/cat"))';
    await assert.rejects(runTool('/usr/bin/sandbox-exec',['-p',profile,'/bin/cat',external]),(e:any)=>e.code==='TOOL_FAILED');
    const inside=join(job,'inside.txt');await writeFile(inside,'allowed job fixture');assert.equal(await runTool('/usr/bin/sandbox-exec',['-p',profile,'/bin/cat',inside]),'allowed job fixture');
  }finally{await rm(folder,{recursive:true,force:true});}
});


test('real PPTX background changes do not invent values and off-slide source edits survive equal renders',office,async()=>{
  const folder=await mkdtemp(join(tmpdir(),'docver-source-render-')),service=new DesktopService(join(folder,'library'));
  try{const Pptx=(pptxgen as any).default??pptxgen;
    const deck=async(name:string,background:string,offslide?:string)=>{const p=new Pptx();p.layout='LAYOUT_WIDE';const slide=p.addSlide();slide.background={color:background};slide.addText('Revenue 100',{x:1,y:1,w:4,h:1,fontSize:12,margin:0});slide.addText('Revenue 120',{x:1,y:1.5,w:4,h:1,fontSize:12,margin:0});if(offslide)slide.addText('Hidden source '+offslide,{x:15,y:1,w:4,h:1,fontSize:12});const path=join(folder,name+'.pptx');await writeFile(path,await p.write({outputType:'nodebuffer'}) as Buffer);return path;};
    const a=await deck('a','FFFFFF'),b=await deck('b','E0E0E0'),project=await service.create('Background',[{label:'a',files:[a]},{label:'b',files:[b]}]),{report}=await service.run(project.project_id);
    assert.equal(report.changes.filter(c=>c.kind==='text_modified').length,0);const visual=report.changes.find(c=>c.kind==='visual_region_changed');assert.ok(visual);assert.equal(visual.appearance_assessment,'inferred');assert.ok(visual.evidence.every(e=>e.provenance==='inferred'));
    const c=await deck('c','FFFFFF','100'),d=await deck('d','FFFFFF','120'),source=await service.create('Off-slide',[{label:'c',files:[c]},{label:'d',files:[d]}]),result=(await service.run(source.project_id)).report;
    assert.equal(result.revisions[0].pages[0].raster?.sha256,result.revisions[1].pages[0].raster?.sha256);const delta=result.changes.find(c=>c.kind==='text_modified');assert.ok(delta);assert.equal(delta.text_assessment,'observed');assert.ok(delta.before?.includes('Hidden source 100'));assert.ok(delta.after?.includes('Hidden source 120'));assert.ok(result.changes.some(c=>c.coverage_gaps.some(g=>g.reason==='ooxml_source_changed_while_libreoffice_appearance_unchanged')));
  }finally{service.close();await rm(folder,{recursive:true,force:true});}
});

test('an OCR-only unmatched page is a lineage gap rather than proof of deletion',native,async()=>{
  const a=(await extractPdf(await scanned('QUARTERLY OUTLOOK 100'),'sha256:outlook',{ocr:'auto'}))[0],b=(await extractPdf(await scanned('SUPPLIER INVOICE 500'),'sha256:invoice',{ocr:'auto'}))[0],paired=matchPages([a],[b]),delta=diffRevisions(rev(a,'v1'),rev(b,'v2'),paired.matches,paired.candidates,()=> 'entity');
  assert.equal(paired.matches.length,0);assert.equal(delta.filter(c=>c.kind==='page_added'||c.kind==='page_deleted').length,0);assert.ok(delta.some(c=>c.kind==='coverage_gap'));
});


test('native batch failure preserves completed pages and unverified environments never run OCR',async()=>{
  const folder=await mkdtemp(join(tmpdir(),'docver-native-fault-'));try{
    const helper=join(folder,'fake-vision.mjs'),module=new URL('../../packages/ingest/ocr.ts',import.meta.url).href;
    const result={version:'fault-fixture',revision:3,languages:['ko-KR','en-US'],language_correction:false,ocr_performed:false,renderer:'fixture',verification:'fixture',viewport_width:960,viewport_height:540,rotation:0,width:960,height:540,render_sha256:'a'.repeat(64),lines:[]};
    await writeFile(helper,`#!${process.execPath}\nif(process.argv.includes('--info')){console.log(JSON.stringify({version:'fixture',os:'fixture',revision:3,languages:['ko-KR','en-US'],language_correction:false,font_inventory_sha256:'a'.repeat(64),font_families:[]}));}else{let s='';for await(const d of process.stdin)s+=d;const q=JSON.parse(s);if(q.pages[0]>16)console.log('broken batch');else console.log(JSON.stringify({pages:q.pages.map(page=>({page,result:${JSON.stringify(result)}}))}));}`,{mode:0o755});
    const child=`import {captureNativePages} from ${JSON.stringify(module)};const r=await captureNativePages(new Uint8Array(),Array.from({length:20},(_,i)=>i+1),[]);console.log(JSON.stringify([...r.keys()]));`;
    const output=execFileSync(process.execPath,['--import','tsx','--input-type=module','-e',child],{encoding:'utf8',env:{...process.env,DOCVER_VISION:helper},timeout:15000});assert.deepEqual(JSON.parse(output),Array.from({length:16},(_,i)=>i+1));
    await writeFile(helper,`#!${process.execPath}\nprocess.exit(7);`,{mode:0o755});
    const unavailable=`import {recognizePdf} from ${JSON.stringify(module)};try{await recognizePdf(new Uint8Array(),1);throw Error('OCR executed');}catch(e){if(e.code!=='OCR_UNAVAILABLE')throw e;console.log(e.code);}`;
    assert.equal(execFileSync(process.execPath,['--import','tsx','--input-type=module','-e',unavailable],{encoding:'utf8',env:{...process.env,DOCVER_VISION:helper},timeout:15000}).trim(),'OCR_UNAVAILABLE');
  }finally{await rm(folder,{recursive:true,force:true});}
});


test('merged OCR boxes cannot reuse one observation to certify multiple numeric regions',()=>{
  const make=(key:string,rows:[string,number,number][]):PageData=>({page_id:key,asset_id:key,page:1,width:960,height:540,coordinate_system:'normalized',source_transform:[],hidden:false,text:'',comparison_basis:'raster_ocr',ocr_text:rows.map(r=>r[0]).join('\n'),elements:rows.map(([text,y,h],i)=>({observation_id:key+i,kind:'text',text,normalized_text:text,bbox:[.1,y,.3,h],reading_order:i,availability:'available',method:'vision_ocr',source_ref:key+i,provenance:'inferred',visibility:'visible'})),notes:null,capabilities:{text:'available',notes:'unavailable',hidden_slides:'unavailable',animation:'unavailable',structure:'unavailable',preview:'available'},coverage_gaps:[]});
  const a=make('a',[['Revenue 100',.1,.08],['Revenue 120',.16,.08]]),b=make('b',[['Revenue 120',.1,.14]]);
  for(const [left,right]of [[a,b],[b,a]]){const delta=changes(left,right);assert.equal(delta.filter(c=>c.kind==='text_modified').length,0);assert.ok(delta.some(c=>c.coverage_gaps.some(g=>g.reason==='ocr_region_missing_or_numeric_ambiguity_withheld')));}
});


test('scanned numeric position swaps stay inferred with affected-region evidence',native,async()=>{
  const make=(swapped:boolean)=>pdf(d=>{const c=createCanvas(1920,1080),ctx=c.getContext('2d');ctx.fillStyle='white';ctx.fillRect(0,0,1920,1080);ctx.font='48px Arial';ctx.fillStyle='black';ctx.fillText('Contract review',120,140);ctx.fillText('Revenue '+(swapped?'120':'100'),120,300);ctx.fillText('Revenue '+(swapped?'100':'120'),120,500);d.image(c.toBuffer('image/png'),0,0,{width:960,height:540});});
  const a=(await extractPdf(await make(false),'sha256:swap-a',{ocr:'auto'}))[0],b=(await extractPdf(await make(true),'sha256:swap-b',{ocr:'auto'}))[0],delta=changes(a,b).find(c=>c.kind==='text_modified');
  assert.ok(delta);assert.equal(delta.text_assessment,'inferred');assert.ok(delta.coverage_gaps.some(g=>g.reason==='ocr_inferred_text_requires_source_review'));assert.ok(delta.evidence.every(e=>e.provenance==='inferred'&&e.method==='vision_ocr'));assert.deepEqual(delta.evidence.map(e=>e.quote),['Revenue 100','Revenue 120','Revenue 120','Revenue 100']);
});

test('immutable textless PPTX page identity survives re-import and unknown nontext correspondence is a gap',office,async()=>{
  const folder=await mkdtemp(join(tmpdir(),'docver-nontext-')),service=new DesktopService(join(folder,'library'));try{
    const Pptx=(pptxgen as any).default??pptxgen,p=new Pptx();p.layout='LAYOUT_WIDE';p.addSlide().addShape('rect',{x:1,y:1,w:2,h:2,fill:{color:'FF0000'},line:{color:'FF0000'}});const file=join(folder,'same.pptx');await writeFile(file,await p.write({outputType:'nodebuffer'}) as Buffer);
    const project=await service.create('Same shape twice',[{label:'a',files:[file]},{label:'b',files:[file]}]),report=(await service.run(project.project_id)).report;
    assert.equal(report.matches.length,1);assert.ok(report.matches[0].reasons.includes('exact_source_page'));assert.equal(report.changes.filter(c=>c.kind==='page_added'||c.kind==='page_deleted').length,0);
    const a=report.revisions[0].pages[0],b={...report.revisions[1].pages[0],asset_id:'different-source',raster:undefined};const paired=matchPages([a],[b]);assert.equal(paired.matches.length,0);const delta=diffRevisions(rev(a,'v1'),rev(b,'v2'),[],[],()=> 'entity');assert.equal(delta.filter(c=>c.kind==='page_added'||c.kind==='page_deleted').length,0);assert.ok(delta.every(c=>c.coverage_gaps.some(g=>g.reason==='nontext_page_lineage_unresolved')));
  }finally{service.close();await rm(folder,{recursive:true,force:true});}
});

test('uncertain image OCR cannot become a deletion while readable source text remains comparable',()=>{
  const page=(key:string,title:string,uncertain=false):PageData=>({page_id:key,asset_id:key,page:1,width:960,height:540,coordinate_system:'normalized',source_transform:[],hidden:false,text:title,visible_text:title+(uncertain?'':'\nTotal 100'),ocr_text:uncertain?'':'Total 100',ocr_unresolved_text:uncertain?'Total 100':'',elements:[{observation_id:key+'raw',kind:'text',text:title,normalized_text:title,bbox:[.1,.1,.6,.08],reading_order:0,availability:'available',method:'pdf_text',source_ref:'header',provenance:'observed',visibility:'visible'},{observation_id:key+'ocr',kind:'text',text:'Total 100',normalized_text:'Total 100',bbox:[.1,.4,.3,.08],reading_order:1,availability:'available',method:'vision_ocr',source_ref:'image',provenance:'inferred',visibility:uncertain?'uncertain':'visible'}],notes:null,capabilities:{text:'available',notes:'unavailable',hidden_slides:'unavailable',animation:'unavailable',structure:'unavailable',preview:'available'},coverage_gaps:[]});
  const delta=changes(page('a','Contract review header Alpha'),page('b','Contract review header Beta',true)),text=delta.filter(c=>c.kind==='text_modified');assert.equal(text.length,1);assert.equal(text[0].text_scope,'region');assert.equal(text[0].text_assessment,'observed');assert.equal(text[0].before,'Contract review header Alpha');assert.equal(text[0].after,'Contract review header Beta');assert.ok(delta.some(c=>c.coverage_gaps.some(g=>g.reason==='ocr_region_missing_or_numeric_ambiguity_withheld')));
});


test('cross-format producer differences retain raster evidence without one visual-change event per page',office,async()=>{
  const folder=await mkdtemp(join(tmpdir(),'docver-cross-render-')),service=new DesktopService(join(folder,'library'));try{
    const Pptx=(pptxgen as any).default??pptxgen,p=new Pptx();p.layout='LAYOUT_WIDE';for(const name of ['Alpha','Bravo','Delta'])p.addSlide().addText(name+' Revenue 100',{x:1,y:1,w:4,h:1,fontSize:24,fontFace:'Arial'});const source=join(folder,'source.pptx'),reference=join(folder,'reference.pdf');await writeFile(source,await p.write({outputType:'nodebuffer'}) as Buffer);await writeFile(reference,await pdf(d=>{for(const [i,name]of ['Alpha','Bravo','Delta'].entries()){if(i)d.addPage({size:[960,540],margin:0});d.fontSize(24).text(name+' Revenue 100',80,140,{lineBreak:false});}}));
    const project=await service.create('Cross format',[{label:'pptx',files:[source]},{label:'pdf',files:[reference]}]),report=(await service.run(project.project_id)).report;
    assert.equal(report.matches.length,3);assert.ok(report.matches.every(m=>!m.reasons.includes('gap_applies_to_entire_revision_interval')));assert.ok(report.changes.filter(c=>!c.coverage_gaps.some(g=>g.reason==='revision_interval_render_appearance_not_comparable')).every(c=>!c.lineage.reasons.includes('gap_applies_to_entire_revision_interval')));assert.equal(report.changes.filter(c=>c.coverage_gaps.some(g=>g.reason==='revision_interval_render_appearance_not_comparable')).length,1);assert.notEqual(report.revisions[0].pages[0].raster?.sha256,report.revisions[1].pages[0].raster?.sha256);assert.equal(report.changes.filter(c=>c.kind==='visual_region_changed').length,0);assert.ok(report.revisions[0].pages[0].coverage_gaps.some(g=>g.feature==='render_fidelity'));assert.equal(report.changes.filter(c=>c.kind==='text_modified').length,0);
  }finally{service.close();await rm(folder,{recursive:true,force:true});}
});


test('released native1 range replay freezes candidate semantics and pre-schema-bump net IDs',async()=>{
  const folder=await mkdtemp(join(tmpdir(),'docver-legacy-candidates-')),store=new Store(folder);try{
    const Pptx=(pptxgen as any).default??pptxgen,p=new Pptx();p.addSlide().addShape('rect',{x:1,y:1,w:2,h:2,fill:{color:'FF0000'}});const bytes=await p.write({outputType:'nodebuffer'}) as Buffer,source=extractPptx(bytes,'sha256:'+byteHash(bytes))[0],a={...source,page_id:'pg_legacy_a'},b={...source,page_id:'pg_legacy_b'};
    const left=rev(a,'v1'),right=rev(b,'v2');left.assets[0].format=right.assets[0].format='pptx';const old=legacyNativeMatch([a],[b]);assert.equal(old.candidates.length,0);assert.equal(matchPages([a],[b]).matches.length,1);
    const entity=(page:string)=>page===a.page_id?'entity_a':'entity_b',original=legacyNativeDiff(left,right,[],old.candidates,entity);assert.deepEqual(original.map(c=>c.kind),['page_deleted','page_added']);assert.ok(original.every(c=>c.schema_version==='0.1.0'));
    const report:ReportData={schema_version:'0.1.0',engine_version:'0.1.0-native.1',report_id:'rpt_legacy_candidates',project_id:'prj_legacy_candidates',timeline_revision_id:'timeline',mapping_revision_id:'mapping',schema_hash:'historical',observation_environment:{fixture:'fixed-native1'},revisions:[left,right],matches:[],candidates:[],mapping_decisions:[],lineages:[{entity_id:'entity_a',page_ids:[a.page_id],status:'inferred'},{entity_id:'entity_b',page_ids:[b.page_id],status:'inferred'}],changes:[],coverage_gaps:[]};
    const q=new QueryService(store,new Set([report.project_id]),()=>report),net=q.changeSet({project_id:report.project_id,report_id:report.report_id,mode:'range_net',from:'v1',to:'v2'});
    assert.deepEqual(net.map(c=>c.kind),original.map(c=>c.kind));assert.deepEqual(net.map(c=>c.change_id),original.map((c,i)=>id('net',[report.report_id,'v1','v2',i,c])));assert.ok(net.every(c=>c.schema_version==='0.1.0'));
  }finally{store.close();await rm(folder,{recursive:true,force:true});}
});
