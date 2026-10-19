import {test} from 'node:test';
import assert from 'node:assert/strict';
import PDFDocument from 'pdfkit';
import {createCanvas} from '@napi-rs/canvas';
import {mkdtemp,writeFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {extractPdf} from '../../packages/ingest/pdf.js';
import {annotationBlocksRegion,PDF_ANNOTATION_CARRIER} from '../../packages/ingest/pdf-annotation-regions.js';
import {PDF_ANNOTATION_LIMIT,PDF_ANNOTATION_POINT_LIMIT,PDF_ANNOTATION_QUAD_LIMIT} from '../../packages/ingest/pdf-annotations.js';
import {selectHybridComparison} from '../../packages/ingest/comparison-selection.js';
import {diffRevisions,evidence} from '../../packages/diff/index.js';
import {recognizePdf,supplementPdfOcr} from '../../packages/ingest/ocr.js';
import {annotationCarriers} from '../../packages/ingest/pdf-annotations.js';
import {DesktopService} from '../../packages/desktop/service.js';
import {Page,byteHash,unresolvedComparisonText,type PageData,type ElementData,type RevisionData} from '../../packages/schema/index.js';
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

test('unknown source locations still withhold numeric contradictions without assigning geometry',async()=>{
  const before=await sample('100');
  for(const side of ['before','after']){
    const left=structuredClone(before),right=await sample('120'),target=side==='before'?left:right;
    target.raw.bbox=[0,0,0,0];target.ocr.text=target.ocr.normalized_text='Revenue 180 won';selectHybridComparison(target.page);
    const result=changes(left.page,right.page);assert.ok(!result.some(c=>c.kind==='text_modified'));assert.ok(result.some(c=>c.coverage_gaps.some(g=>g.reason==='ocr_disagrees_with_unlocalized_source_text')));assert.deepEqual(target.raw.bbox,[0,0,0,0]);
  }
  const positive=await sample('120');positive.raw.bbox=[0,0,0,0];selectHybridComparison(positive.page);assert.equal(changes(before.page,positive.page).filter(c=>c.kind==='text_modified').length,1);
});

test('supplement OCR under annotations remains an unresolved observation instead of disappearing',async()=>{
  const canvas=createCanvas(1200,200),ctx=canvas.getContext('2d');ctx.fillStyle='white';ctx.fillRect(0,0,1200,200);ctx.fillStyle='black';ctx.font='64px Arial';ctx.fillText('Revenue 120 won',30,130);
  const bytes=await pdf(d=>{d.font('Helvetica').fontSize(24).text('Header',50,30,{lineBreak:false});d.image(canvas.toBuffer('image/png'),50,180,{width:480,height:80});d.highlight(45,175,490,90);});
  const observed=await recognizePdf(bytes,1),line=observed.lines.find(l=>l.text.includes('Revenue'));assert.ok(line,'Actual native raster observation must read the image');
  for(const unknown of [false,true]){
    const [page]=await extractPdf(bytes,'sha256:'+byteHash(bytes),{ocr:'off'});assert.equal(page.unresolved_text,'');
    if(unknown)page.elements=page.elements.filter(e=>e.method!==PDF_ANNOTATION_CARRIER).concat(annotationCarriers([{subtype:'Square',annotationFlags:0}],{width:600,height:400,transform:[1,0,0,-1,0,400]},page.asset_id,1,page.elements.length).elements);
    await supplementPdfOcr(page,bytes,{nativeResult:{...observed,lines:[line],tables:[],grid_tables:[]}});
    const retained:ElementData|undefined=page.elements.find(e=>e.method==='vision_ocr'&&e.text===line.text);assert.ok(retained);assert.equal(retained.visibility,'uncertain');assert.equal(retained.comparison_role,'unresolved');assert.equal(page.ocr_unresolved_text,line.text);assert.equal(page.ocr_text,'');assert.equal(page.ocr?.mode,'supplement');assert.ok(page.coverage_gaps.some(g=>g.reason==='low_confidence_or_ambiguous_ocr_observation_retained'));Page.parse(page);
  }
  const [plain]=await extractPdf(bytes,'sha256:'+byteHash(bytes),{ocr:'off'});plain.elements=plain.elements.filter(e=>e.method!==PDF_ANNOTATION_CARRIER);await supplementPdfOcr(plain,bytes,{nativeResult:{...observed,lines:[line],tables:[],grid_tables:[]}});assert.ok(plain.elements.some(e=>e.method==='vision_ocr'&&e.text===line.text&&e.visibility==='visible'));
});

test('page-level OCR evidence never attributes its quote to annotation metadata',async()=>{
  const {page,ocr}=await sample('120',d=>d.annotate(48,116,245,40,{Subtype:'Redact'} as any));const carrier=page.elements.find(e=>e.method===PDF_ANNOTATION_CARRIER)!;page.elements=[carrier,ocr];page.text='';page.ocr_text=ocr.text;page.comparison_basis='raster_ocr';
  const revision={revision_id:'r',revision_occurrence_id:'o'} as RevisionData,entry=evidence(revision,page);assert.equal(entry.quote,ocr.text);assert.equal(entry.method,'vision_ocr');assert.equal(entry.provenance,'inferred');
  page.ocr_text='';page.ocr_unresolved_text=ocr.text;assert.equal(evidence(revision,page).method,'page_observation');assert.equal(evidence(revision,page).quote,'');page.elements=[carrier];assert.equal(evidence(revision,page).method,'page_observation');
});

test('explicit nonpainting source text stays separate from actual native image edits despite unknown metrics',async()=>{
  const image=(value:string)=>{const c=createCanvas(1200,200),ctx=c.getContext('2d');ctx.fillStyle='white';ctx.fillRect(0,0,1200,200);ctx.fillStyle='black';ctx.font='64px Arial';ctx.fillText('Revenue '+value+' won',30,130);return c.toBuffer('image/png');};
  const pages:PageData[]=[];
  for(const [rawValue,rasterValue]of [['100','100'],['120','180']]){
    const bytes=await pdf(d=>{d.image(image(rasterValue),50,180,{width:480,height:80});d.addContent('3 Tr');text(d,rawValue);}),[page]=await extractPdf(bytes,'sha256:'+byteHash(bytes),{ocr:'auto'}),raw=page.elements.find(e=>e.method==='pdf_text')!;
    assert.equal(raw.visibility,'hidden_render_mode');assert.equal(raw.text,'Revenue '+rawValue+' won');assert.ok(raw.visibility_evidence?.some(v=>v.method==='pdf_text_geometry_estimated_or_unavailable'));assert.ok(raw.visibility_evidence?.some(v=>v.method==='explicit_nonpainting_text_mode'&&v.assessment==='observed'&&v.coverage===0));assert.ok(page.elements.some(e=>e.method==='vision_ocr'&&e.text==='Revenue '+rasterValue+' won'&&e.visibility==='visible'));Page.parse(page);pages.push(page);
  }
  const edits=changes(pages[0],pages[1]).filter(c=>c.kind==='text_modified');assert.equal(edits.length,1);assert.equal(edits[0].before,'Revenue 100 won');assert.equal(edits[0].after,'Revenue 180 won');assert.equal(edits[0].text_assessment,'inferred');assert.ok(edits[0].evidence.every(e=>e.method==='vision_ocr'));
  const clipped=await pdf(d=>{d.addContent('7 Tr');text(d,'120');}),[clip]=await extractPdf(clipped,'sha256:'+byteHash(clipped),{ocr:'off'});assert.equal(clip.elements[0].visibility,'hidden_render_mode');
  const mixed=await pdf(d=>{d.font('Times-Roman').fontSize(32).addContent('3 Tr');d.text('Revenue ',50,120,{continued:true});d.addContent('0 Tr');d.text('120 won',{lineBreak:false});}),[partly]=await extractPdf(mixed,'sha256:'+byteHash(mixed),{ocr:'off'});assert.ok(partly.elements.some(e=>e.text.includes('120')&&e.visibility==='unverified'));assert.ok(!partly.elements.filter(e=>e.text.includes('120')).some(e=>e.visibility==='hidden_render_mode'));
});

test('ambiguous repeated text and Type3 character programs cannot establish a nonpainting source run',async()=>{
  const repeated=await pdf(d=>{d.addContent('3 Tr');text(d,'120');d.addContent('0 Tr');d.font('Times-Roman').fontSize(32).text('Revenue 120 won',50,230,{lineBreak:false});}),[duplicate]=await extractPdf(repeated,'sha256:'+byteHash(repeated),{ocr:'off'});assert.equal(duplicate.elements.filter(e=>e.text==='Revenue 120 won').length,2);assert.ok(duplicate.elements.every(e=>e.visibility==='unverified'));
  const bytes=await pdf(d=>{const char=d.ref({});char.end('600 0 0 0 600 700 d1\n0 0 600 700 re f');const font=d.ref({Type:'Font',Subtype:'Type3',FontBBox:[0,0,600,700],FontMatrix:[.001,0,0,.001,0,0],CharProcs:{A:char},Encoding:{Type:'Encoding',Differences:[65,'A']},FirstChar:65,LastChar:65,Widths:[600],Resources:{}});font.end('');d.page.fonts.T3=font;d.addContent('BT /T3 40 Tf 3 Tr 50 200 Td (A) Tj ET');}),[type3]=await extractPdf(bytes,'sha256:'+byteHash(bytes),{ocr:'off'});assert.equal(type3.elements[0].text,'A');assert.notEqual(type3.elements[0].visibility,'hidden_render_mode');assert.ok(!type3.elements[0].visibility_evidence?.some(v=>v.method==='explicit_nonpainting_text_mode'));Page.parse(type3);
});

test('disjoint raster edits survive repeated source text and partial OCR lines remain observations',async()=>{
  const make=async(value:string)=>{const c=createCanvas(1200,200),ctx=c.getContext('2d');ctx.fillStyle='white';ctx.fillRect(0,0,1200,200);ctx.fillStyle='black';ctx.font='64px Arial';ctx.fillText('Revenue '+value+' won',30,130);return pdf(d=>{d.font('Helvetica').fontSize(24).text('Revenue 120 won',50,30,{lineBreak:false});d.image(c.toBuffer('image/png'),50,180,{width:480,height:80});});};
  const pages:PageData[]=[];
  for(const value of ['100','120']){const bytes=await make(value),[page]=await extractPdf(bytes,'sha256:'+byteHash(bytes),{ocr:'auto'});assert.ok(page.elements.some(e=>e.method==='vision_ocr'&&e.bbox[1]>.4&&e.text==='Revenue '+value+' won'&&e.comparison_role==='selected'));assert.ok(page.elements.some(e=>e.method==='pdf_text'&&e.text==='Revenue 120 won'&&e.comparison_role==='selected'));pages.push(page);}
  const edits=changes(pages[0],pages[1]).filter(c=>c.kind==='text_modified');assert.equal(edits.length,1);assert.ok(edits[0].before?.includes('Revenue 100 won'));assert.ok(edits[0].after?.includes('Revenue 120 won'));assert.deepEqual(edits[0].evidence.map(e=>e.quote),['Revenue 100 won','Revenue 120 won']);assert.ok(edits[0].evidence.every(e=>e.method==='vision_ocr'&&e.bbox[1]>.4));assert.equal(edits[0].text_assessment,'inferred');
  const bytes=await make('100'),native=await recognizePdf(bytes,1),line=native.lines.find(l=>l.text.includes('Revenue')&&l.bbox[1]>.4)!;assert.ok(line);
  for(const partial of [false,true]){const [page]=await extractPdf(bytes,'sha256:'+byteHash(bytes),{ocr:'off'}),raw=page.elements.find(e=>e.method==='pdf_text')!,bbox=partial?[raw.bbox[0],raw.bbox[1],raw.bbox[2]+.3,raw.bbox[3]]as [number,number,number,number]:raw.bbox;
    await supplementPdfOcr(page,bytes,{nativeResult:{...native,lines:[{...line,text:partial?'Revenue 120 won image 100':raw.text,bbox}],tables:[],grid_tables:[]}});const observed:ElementData|undefined=page.elements.find(e=>e.method==='vision_ocr');assert.ok(observed);assert.equal(observed.comparison_role,partial?'unresolved':'shadowed');assert.equal(observed.text,partial?'Revenue 120 won image 100':raw.text);if(!partial)assert.equal(page.ocr?.mode,'verification');Page.parse(page);
  }
});

test('known-metric explicit nonpainting modes stay hidden independently of color and clip geometry',async()=>{
  for(const mode of ['7 Tr','0 g 3 Tr']){
    const bytes=await pdf(d=>{d.addContent(mode);text(d,'120','Helvetica');}),[page]=await extractPdf(bytes,'sha256:'+byteHash(bytes),{ocr:'off'});assert.equal(page.elements[0].visibility,'hidden_render_mode');assert.ok(page.elements[0].visibility_evidence?.some(v=>v.method==='explicit_nonpainting_text_mode'&&v.assessment==='observed'));Page.parse(page);
  }
});

test('fully shadowed source verification keeps page absence complete while participating uncertainty still withholds',async()=>{
  const c=createCanvas(8,8);c.getContext('2d').fillRect(0,0,8,8);const anchor=await sample('100',d=>d.image(c.toBuffer('image/png'),500,300,{width:20,height:20}),'Helvetica'),extra=(await sample('200',undefined,'Helvetica')).page;
  assert.equal(anchor.ocr.comparison_role,'shadowed');assert.equal(unresolvedComparisonText(anchor.page),'');
  const revision=(pages:PageData[],key:string):RevisionData=>({revision_id:key,revision_occurrence_id:key,label:key,assets:pages.map(p=>({asset_id:p.asset_id,format:'pdf',bytes:0})),status:'success',pages,coverage_gaps:[],errors:[],bundle_mapping:[]});
  const run=(page:PageData,added:boolean)=>diffRevisions(revision(added?[page]:[page,extra],'before'),revision(added?[page,extra]:[page],'after'),[{from_page_id:page.page_id,to_page_id:page.page_id,score:1,status:'inferred',reasons:['controlled_anchor']}],[],()=> 'entity');
  for(const added of [false,true]){assert.equal(run(anchor.page,added).filter(c=>c.kind===(added?'page_added':'page_deleted')).length,1);
    for(const state of ['inferred','unresolved','source_unresolved']){const page=structuredClone(anchor.page),e:ElementData={...structuredClone(anchor.ocr),observation_id:'extra-'+state,text:'Raster 300 won',normalized_text:'Raster 300 won',bbox:[.1,.7,.3,.05],visibility:state==='inferred'?'visible':'uncertain',...(state==='source_unresolved'?{method:'pdf_text',provenance:'observed'}:{})};page.elements.push(e);selectHybridComparison(page);const result=run(page,added);assert.ok(!result.some(c=>c.kind==='page_added'||c.kind==='page_deleted'));assert.ok(result.some(c=>c.coverage_gaps.some(g=>g.reason==='comparison_observation_incomplete')));}
  }
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
