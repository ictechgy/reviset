import {test} from 'node:test';
import assert from 'node:assert/strict';
import PDFDocument from 'pdfkit';
import {mkdtemp,writeFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {extractPdf} from '../../packages/ingest/pdf.js';
import {annotationBlocksRegion,PDF_ANNOTATION_CARRIER} from '../../packages/ingest/pdf-annotation-regions.js';
import {PDF_ANNOTATION_LIMIT,PDF_ANNOTATION_POINT_LIMIT,PDF_ANNOTATION_QUAD_LIMIT} from '../../packages/ingest/pdf-annotations.js';
import {selectHybridComparison} from '../../packages/ingest/comparison-selection.js';
import {diffRevisions} from '../../packages/diff/index.js';
import {DesktopService} from '../../packages/desktop/service.js';
import {Page,byteHash,type PageData,type ElementData,type RevisionData} from '../../packages/schema/index.js';
async function pdf(draw:(d:PDFKit.PDFDocument)=>void){const d=new PDFDocument({size:[600,400],margin:0}),chunks:Buffer[]=[];d.on('data',b=>chunks.push(b));const done=new Promise<Buffer>(r=>d.on('end',()=>r(Buffer.concat(chunks))));draw(d);d.end();return done;}
function text(d:PDFKit.PDFDocument,value:string,font='Times-Roman'){d.font(font).fontSize(32).text('Revenue '+value+' won',50,120,{lineBreak:false});}
async function sample(value:string,draw?:(d:PDFKit.PDFDocument)=>void,font='Times-Roman'){
  const bytes=await pdf(d=>{text(d,value,font);draw?.(d);}),[page]=await extractPdf(bytes,'sha256:'+byteHash(bytes),{ocr:'off'}),raw=page.elements.find(e=>e.method==='pdf_text')!;
  const ocr:ElementData={...structuredClone(raw),observation_id:'ocr-'+page.page_id,method:'vision_ocr',source_ref:'raster:1',provenance:'inferred',visibility:'visible',visibility_spans:[],visibility_evidence:[],ocr:{confidence:1,confidence_scope:'line',numeric_consensus:true,ambiguous:false,alternatives:[]}};page.elements.push(ocr);page.raster={sha256:(value==='100'?'a':'b').repeat(64),width:1200,height:800,renderer:'fixture',environment:'fixture'};selectHybridComparison(page);return {page,ocr,raw};
}
function changes(a:PageData,b:PageData){const revision=(p:PageData,key:string):RevisionData=>({revision_id:key,revision_occurrence_id:key,label:key,assets:[{asset_id:p.asset_id,format:'pdf',bytes:0}],status:'success',pages:[p],coverage_gaps:p.coverage_gaps,errors:[],bundle_mapping:[]});return diffRevisions(revision(a,'before'),revision(b,'after'),[{from_page_id:a.page_id,to_page_id:b.page_id,score:.9,status:'inferred',reasons:['controlled_correspondence']}],[],()=> 'entity');}

test('unlocalized numeric contradictions remain explicit and cannot become inferred OCR edits',async()=>{
  const before=await sample('100');
  for(const source of ['120','1/20']){
    const after=await sample(source);after.ocr.text=after.ocr.normalized_text=source==='120'?'Revenue 180 won':'Revenue 120 won';
    const result=changes(before.page,after.page),gap=result.find(c=>c.coverage_gaps.some(g=>g.reason==='ocr_disagrees_with_unlocalized_source_text'))!;
    assert.ok(!result.some(c=>c.kind==='text_modified'));assert.ok(gap);assert.ok(gap.evidence.some(e=>e.quote==='Revenue '+source+' won'&&e.method==='pdf_text'));assert.ok(gap.evidence.some(e=>e.quote===after.ocr.text&&e.method==='vision_ocr'));assert.equal(after.raw.text,'Revenue '+source+' won');assert.equal(after.raw.visibility,'unverified');
  }
  const split=await sample('120'),parts=['Revenue','120','won'].map((value,i)=>({...structuredClone(split.raw),observation_id:'split-'+i,text:value,normalized_text:value,reading_order:i}));split.page.elements=[...parts,split.ocr];split.ocr.text=split.ocr.normalized_text='Revenue 180 won';split.ocr.reading_order=3;selectHybridComparison(split.page);assert.ok(!changes(before.page,split.page).some(c=>c.kind==='text_modified'));
  const budget=await sample('120');budget.page.elements=[...Array.from({length:257},(_,i)=>({...structuredClone(budget.raw),observation_id:'budget-'+i,reading_order:i})),budget.ocr];selectHybridComparison(budget.page);const withheld=changes(before.page,budget.page);assert.ok(!withheld.some(c=>c.kind==='text_modified'));assert.ok(withheld.some(c=>c.coverage_gaps.some(g=>g.reason==='unlocalized_source_text_review_budget_exceeded')));
  const other=await sample('120');other.raw.text=other.raw.normalized_text='Cost 120 won';const qualified=changes(before.page,other.page);assert.equal(qualified.filter(c=>c.kind==='text_modified').length,1);assert.ok(qualified.some(c=>c.coverage_gaps.some(g=>g.reason==='ocr_disagrees_with_unlocalized_source_text')));
  const duplicate=structuredClone(before.page);duplicate.elements.push({...structuredClone(before.ocr),observation_id:'left-duplicate'});assert.ok(!changes(duplicate,(await sample('120')).page).some(c=>c.kind==='text_modified'));
});

test('page annotation intent uses actual regions without promoting carrier or estimated glyph geometry',async()=>{
  const before=await sample('100');
  for(const annotate of [(d:PDFKit.PDFDocument)=>d.strike(48,116,245,40,{color:'#fefefe'}),(d:PDFKit.PDFDocument)=>d.annotate(48,116,245,40,{Subtype:'Redact'} as any)]){
    const after=await sample('120',annotate),carrier=after.page.elements.find(e=>e.method===PDF_ANNOTATION_CARRIER)!;assert.ok(carrier);assert.equal(carrier.text,'');assert.equal(carrier.comparison_role,'excluded');assert.ok(carrier.visibility_evidence?.every(v=>v.assessment==='inferred'&&v.coverage===0));assert.equal(after.raw.visibility,'unverified');assert.equal(after.ocr.comparison_role,'unresolved');assert.equal(after.ocr.comparison_reason,'page_annotation_blocks_independent_raster');
    // A defensive diff check also rejects incorrectly preselected stored OCR.
    after.ocr.comparison_role='selected';carrier.bbox=[0,0,0,0];assert.ok(annotationBlocksRegion(after.page.elements,after.ocr.bbox));const result=changes(before.page,after.page);assert.ok(!result.some(c=>c.kind==='text_modified'));assert.ok(result.some(c=>c.coverage_gaps.some(g=>g.reason==='page_annotation_prevents_inferred_raster_edit')));Page.parse(after.page);
  }
  const hidden=await sample('120',d=>d.strike(48,116,245,40,Object.assign({color:'#fefefe'},{F:32})));assert.ok(!hidden.page.elements.some(e=>e.method===PDF_ANNOTATION_CARRIER));assert.equal(changes(before.page,hidden.page).filter(c=>c.kind==='text_modified').length,1);
  const link=await sample('120',d=>d.link(48,116,245,40,'https://example.invalid'));assert.ok(!link.page.elements.some(e=>e.method===PDF_ANNOTATION_CARRIER));assert.equal(changes(before.page,link.page).filter(c=>c.kind==='text_modified').length,1);
  const remote=await sample('120',d=>d.annotate(400,300,50,40,{Subtype:'Redact'} as any));assert.equal(changes(before.page,remote.page).filter(c=>c.kind==='text_modified').length,1);
  const observed=await sample('120',d=>d.strike(0,0,600,400),'Helvetica');assert.equal(observed.raw.visibility,'struck_through');assert.equal(observed.raw.comparison_role,'selected');assert.equal(observed.ocr.comparison_role,'shadowed','A page carrier cannot veto readable observed strike priority');
});

test('annotation carriers preserve image-only text semantics and explicit source budgets',async()=>{
  const bytes=await pdf(d=>d.annotate(48,116,245,40,{Subtype:'Redact'} as any)),[page]=await extractPdf(bytes,'sha256:'+byteHash(bytes),{ocr:'off'});assert.equal(page.text,'');assert.equal(page.visible_text,'');assert.equal(page.unresolved_text,'');assert.equal(page.capabilities.text,'unavailable');assert.equal(page.elements.length,1);assert.equal(page.elements[0].comparison_role,'excluded');Page.parse(page);
  const crowded=await pdf(d=>{text(d,'120','Helvetica');for(let i=0;i<=PDF_ANNOTATION_LIMIT;i++)d.annotate(48,116,245,40,{Subtype:'Redact'} as any);}),[limited]=await extractPdf(crowded,'sha256:'+byteHash(crowded),{ocr:'off'});assert.equal(limited.text,'Revenue 120 won');assert.equal(limited.elements.filter(e=>e.method===PDF_ANNOTATION_CARRIER).length,1);assert.ok(limited.coverage_gaps.some(g=>g.reason==='source_annotation_budget_exceeded'));assert.equal(limited.elements.find(e=>e.method==='pdf_text')!.visibility,'unverified');assert.ok(annotationBlocksRegion(limited.elements,[.1,.3,.3,.1]));Page.parse(limited);
  const points=Array.from({length:PDF_ANNOTATION_POINT_LIMIT/8+1},()=>[48,284,293,284,48,244,293,244]).flat(),pointBytes=await pdf(d=>{text(d,'120','Helvetica');d.annotate(48,116,245,40,{Subtype:'StrikeOut',QuadPoints:points} as any);}),[pointLimited]=await extractPdf(pointBytes,'sha256:'+byteHash(pointBytes),{ocr:'off'});assert.ok(pointLimited.coverage_gaps.some(g=>g.reason==='source_annotation_point_budget_exceeded'));assert.equal(pointLimited.elements.find(e=>e.method==='pdf_text')!.visibility,'unverified');Page.parse(pointLimited);
  const singlePoints=Array.from({length:PDF_ANNOTATION_QUAD_LIMIT/8+1},()=>[48,284,293,284,48,244,293,244]).flat(),singleBytes=await pdf(d=>{text(d,'120','Helvetica');d.annotate(48,116,245,40,{Subtype:'StrikeOut',QuadPoints:singlePoints} as any);}),[singleLimited]=await extractPdf(singleBytes,'sha256:'+byteHash(singleBytes),{ocr:'off'});assert.ok(singleLimited.coverage_gaps.some(g=>g.reason==='source_annotation_point_budget_exceeded'));assert.equal(singleLimited.elements.find(e=>e.method==='pdf_text')!.visibility,'unverified');Page.parse(singleLimited);
});

test('actual native pale strike and unapplied Redact metadata prevent false Times numeric edits after reopen',async()=>{
  const folder=await mkdtemp(join(tmpdir(),'docver-annotation-intent-'));let service=new DesktopService(join(folder,'library'));
  try{
    const original=join(folder,'before.pdf');await writeFile(original,await pdf(d=>{text(d,'100');d.font('Helvetica').fontSize(16).text('Stable synthetic footer',50,300,{lineBreak:false});}));
    for(const kind of ['strike','redact']){
      const file=join(folder,kind+'.pdf');await writeFile(file,await pdf(d=>{text(d,'120');d.font('Helvetica').fontSize(16).text('Stable synthetic footer',50,300,{lineBreak:false});if(kind==='strike')d.strike(48,116,245,40,{color:'#fefefe'});else d.annotate(48,116,245,40,{Subtype:'Redact'} as any);}));
      const project=await service.create('Source annotation '+kind,[{label:'before',files:[original]},{label:'after',files:[file]}]),result=await service.run(project.project_id,undefined,undefined,false);assert.ok(!result.report.changes.some(c=>c.kind==='text_modified'));assert.ok(!result.report.changes.some(c=>c.kind==='page_added'||c.kind==='page_deleted'));service.commit(project.project_id,result);service.close();service=new DesktopService(join(folder,'library'));
      const report=service.snapshot(project.project_id,result.report.report_id),page=service.pageData(project.project_id,report.report_id,report.revisions[1].pages[0].page_id).page;assert.equal(page.text,'Revenue 120 won\nStable synthetic footer');assert.ok(page.elements.some(e=>e.method===PDF_ANNOTATION_CARRIER&&e.comparison_role==='excluded'));assert.ok(page.elements.some(e=>e.method==='vision_ocr'&&e.text==='Revenue 120 won'&&e.visibility==='uncertain'&&e.comparison_role==='unresolved'));assert.ok(page.coverage_gaps.some(g=>g.feature==='pdf_annotations'));assert.deepEqual(report,result.report);
    }
  }finally{service.close();await rm(folder,{recursive:true,force:true});}
});
