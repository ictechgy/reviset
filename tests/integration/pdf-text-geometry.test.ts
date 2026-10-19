import {test} from 'node:test';
import assert from 'node:assert/strict';
import PDFDocument from 'pdfkit';
import {getDocument} from 'pdfjs-dist/legacy/build/pdf.mjs';
import {extractPdf,pdfOptions} from '../../packages/ingest/pdf.js';
import {Page,Report,byteHash,type ElementData,type PageData,type RevisionData} from '../../packages/schema/index.js';
import {PDF_GEOMETRY_UNVERIFIED} from '../../packages/ingest/pdf-text-geometry.js';
import {selectHybridComparison} from '../../packages/ingest/comparison-selection.js';
import {diffRevisions} from '../../packages/diff/index.js';
import {DesktopService} from '../../packages/desktop/service.js';
import {validateCorpusPages} from '../../scripts/public-corpus-validation.js';
import {mkdtemp,writeFile,rm} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
async function pdf(draw:(d:PDFKit.PDFDocument)=>void){
  const d=new PDFDocument({size:[300,200],margin:0,compress:false}),chunks:Buffer[]=[];d.on('data',b=>chunks.push(b));const done=new Promise<Buffer>(r=>d.on('end',()=>r(Buffer.concat(chunks))));draw(d);d.end();return done;
}
const write=(d:PDFKit.PDFDocument,font:string,text:string,x=40,y=80)=>d.font(font).fontSize(20).fillColor('black').text(text,x,y,{lineBreak:false});

test('real standard-font missing metrics retain observed text with finite explicitly unverified geometry',async()=>{
  for(const font of ['Times-Roman','Times-Bold','Times-Italic','Courier','Symbol','ZapfDingbats']){
    const bytes=await pdf(d=>write(d,font,'A')),task=getDocument({...pdfOptions,disableFontFace:true,data:new Uint8Array(bytes)});
    try{const page=await(await task.promise).getPage(1),content=await page.getTextContent({disableNormalization:true}),item=content.items.find(i=>'str'in i&&i.str.trim());assert.ok(item&&'fontName'in item);assert.equal(Number.isFinite(content.styles[item.fontName].ascent),false,'Real upstream boundary, no mocked metrics');}finally{await task.destroy();}
    const [page]=await extractPdf(bytes,'sha256:'+byteHash(bytes),{ocr:'off'}),element=page.elements[0];
    Page.parse(JSON.parse(JSON.stringify(Page.parse(page))));assert.ok(element.text.trim());assert.equal(element.provenance,'observed');assert.equal(element.availability,'available');assert.equal(element.visibility,'unverified');assert.deepEqual(element.visibility_spans,[]);assert.ok(element.visibility_evidence?.some(v=>v.method===PDF_GEOMETRY_UNVERIFIED&&v.coverage===0));assert.ok(page.unresolved_text?.includes(element.text));assert.ok(!page.visible_text);assert.ok(page.coverage_gaps.some(g=>g.reason===PDF_GEOMETRY_UNVERIFIED));
  }
});

test('estimated geometry never establishes source shadow, grid cells, observed strike or opaque-cover claims',async()=>{
  const draw=(font:string)=>(d:PDFKit.PDFDocument)=>{for(const x of [20,140,280])d.moveTo(x,20).lineTo(x,160).stroke();for(const y of [20,90,160])d.moveTo(20,y).lineTo(280,y).stroke();for(const [value,x,y]of [['Q1',40,35],['100',160,35],['Q2',40,105],['120',160,105]] as const)write(d,font,value,x,y);d.strike(38,32,50,25);d.rect(150,100,100,35).fill('white');};
  const controlBytes=await pdf(draw('Helvetica')),[control]=await extractPdf(controlBytes,'sha256:'+byteHash(controlBytes),{ocr:'off'});assert.equal(control.elements.filter(e=>e.table?.origin==='pdf_grid_inferred').length,4);assert.equal(control.elements.find(e=>e.text==='Q1')!.visibility,'struck_through');assert.ok(control.elements.find(e=>e.text==='Q1')!.visibility_evidence?.some(v=>v.method==='strikeout_annotation_quad'));assert.equal(control.elements.find(e=>e.text==='120')!.visibility,'occluded');
  const bytes=await pdf(draw('Times-Roman'));
  const [page]=await extractPdf(bytes,'sha256:'+byteHash(bytes),{ocr:'off'});assert.equal(page.elements.length,4);assert.ok(page.elements.every(e=>!e.table&&e.visibility==='unverified'&&!e.visibility_spans?.length));
  const raw=page.elements[0],ocr:ElementData={...structuredClone(raw),observation_id:'independent-raster',method:'vision_ocr',source_ref:'raster:1',provenance:'inferred',visibility:'visible',visibility_evidence:[],bbox:[Math.max(0,raw.bbox[0]-.02),Math.max(0,raw.bbox[1]-.02),raw.bbox[2]+.04,raw.bbox[3]+.04]};page.elements.push(ocr);selectHybridComparison(page);
  assert.equal(raw.comparison_role,'unresolved');assert.equal(ocr.comparison_role,'selected');assert.equal(ocr.comparison_order,0);assert.ok(page.elements.filter(e=>e.method==='pdf_text').every(e=>(e.comparison_order??0)>0));assert.ok(page.coverage_gaps.some(g=>g.reason==='estimated_source_geometry_remains_unresolved'));Page.parse(page);
});

test('unknown painted font extent withholds earlier visibility while later reliable source stays visible',async()=>{
  const bytes=await pdf(d=>{write(d,'Helvetica','Earlier');write(d,'Times-Roman','Unknown');write(d,'Helvetica','Between',40,110);write(d,'Courier','Last unknown',160,110);write(d,'Helvetica','Later',40,150);}),[page]=await extractPdf(bytes,'sha256:'+byteHash(bytes),{ocr:'off'});
  const earlier=page.elements.find(e=>e.text==='Earlier')!,unknown=page.elements.find(e=>e.text==='Unknown')!,later=page.elements.find(e=>e.text==='Later')!;
  assert.equal(earlier.visibility,'uncertain');assert.ok(earlier.visibility_evidence?.some(v=>v.method==='later_text_geometry_unverified'));assert.equal(unknown.visibility,'unverified');assert.equal(page.elements.find(e=>e.text==='Between')!.visibility,'uncertain');assert.equal(later.visibility,'visible');assert.ok(later.visibility_spans?.length);Page.parse(page);
  const hidden=await pdf(d=>{write(d,'Helvetica','Clear');d.addContent('3 Tr');write(d,'Times-Roman','Not painted');}),[control]=await extractPdf(hidden,'sha256:'+byteHash(hidden),{ocr:'off'});assert.equal(control.elements.find(e=>e.text==='Clear')!.visibility,'visible');
});

test('standard-font page commits and reloads through actual desktop report and native-page storage',async()=>{
  const folder=await mkdtemp(join(tmpdir(),'docver-standard-font-')),library=join(folder,'library');let service=new DesktopService(library);
  try{const file=join(folder,'times.pdf');await writeFile(file,await pdf(d=>{write(d,'Times-Roman','Original raw text');write(d,'Helvetica','Reliable control',40,140);}));const project=await service.create('Standard font import',[{label:'original',files:[file]}]),result=await service.run(project.project_id,undefined,undefined,false);Report.parse(result.report);assert.equal(result.report.revisions[0].status,'success');assert.equal(result.report.revisions[0].pages.length,1);assert.equal(service.reports(project.project_id).length,0);service.commit(project.project_id,result);service.close();service=new DesktopService(library);const report=service.snapshot(project.project_id,result.report.report_id),page=report.revisions[0].pages[0];assert.deepEqual(report,result.report);assert.deepEqual(service.pageData(project.project_id,report.report_id,page.page_id).page,page);const raw=page.elements.find(e=>e.text==='Original raw text')!;assert.equal(raw.visibility,'unverified');assert.equal(raw.comparison_role,'unresolved');assert.ok(raw.visibility_evidence?.some(v=>v.method===PDF_GEOMETRY_UNVERIFIED));assert.equal(page.ocr?.status,'available');assert.ok(page.elements.some(e=>e.method==='vision_ocr'));}finally{service.close();await rm(folder,{recursive:true,force:true});}
});

test('public-corpus gate rejects nonfinite geometry before JSON can serialize it as null',async()=>{
  const [page]=await extractPdf(await pdf(d=>write(d,'Helvetica','Finite')),'sha256:finite',{ocr:'off'});assert.equal(validateCorpusPages([page],'control').length,1);const invalid=structuredClone(page);invalid.elements[0].bbox[0]=NaN;assert.throws(()=>validateCorpusPages([invalid],'invalid-standard-font'),/invalid-standard-font page 1 failed canonical Page validation/);assert.ok(JSON.stringify(invalid).includes('null'));
});

test('fractional-coordinate full-page annotations keep finite coverage and their existing assessment',async()=>{
  for(const [size,text,x,y]of [[20.3,'Pineapple',31.42,80.15],[12.7,'Revenue 1.5',19.17,28.93],[20.1,'ABCDEFG',40.1,80.1]] as const){
    for(const kind of ['strike','highlight'] as const){
      const bytes=await pdf(d=>{d.font('Helvetica').fontSize(size).text(text,x,y,{lineBreak:false});if(kind==='strike')d.strike(0,0,300,200);else d.highlight(0,0,300,200);}),[page]=await extractPdf(bytes,'sha256:'+byteHash(bytes),{ocr:'off'}),element=page.elements.find(e=>e.text===text)!;
      Page.parse(JSON.parse(JSON.stringify(page)));assert.ok(element.visibility_evidence?.length);assert.ok(element.visibility_evidence.every(v=>Number.isFinite(v.coverage)&&v.coverage>=0&&v.coverage<=1));assert.equal(element.visibility,kind==='strike'?'struck_through':'uncertain');assert.ok(element.visibility_evidence.some(v=>v.method===(kind==='strike'?'strikeout_annotation_quad':'annotation_overlay_unverified')));
    }
  }
});

test('independent raster numeric pairing ignores only estimated source geometry and retains localized ambiguity vetoes',async()=>{
  const pages:PageData[]=[];
  for(const [i,value]of ['100','120'].entries()){
    const bytes=await pdf(d=>write(d,'Times-Roman','Revenue '+value+' won')),[page]=await extractPdf(bytes,'sha256:'+byteHash(bytes),{ocr:'off'}),raw=page.elements[0];
    page.elements.push({...structuredClone(raw),observation_id:'raster-'+i,method:'vision_ocr',source_ref:'raster:1',provenance:'inferred',visibility:'visible',visibility_evidence:[],ocr:{confidence:1,confidence_scope:'line',numeric_consensus:true,ambiguous:false,alternatives:[]}});selectHybridComparison(page);page.raster={sha256:String(i+1).repeat(64),width:1200,height:800,renderer:'fixture',environment:'fixture'};pages.push(page);
  }
  const changes=(a=pages[0],b=pages[1])=>{const rev=(p:PageData,key:string):RevisionData=>({revision_id:key,revision_occurrence_id:key,label:key,assets:[{asset_id:p.asset_id,format:'pdf',bytes:0}],status:'success',pages:[p],coverage_gaps:p.coverage_gaps,errors:[],bundle_mapping:[]});return diffRevisions(rev(a,'before'),rev(b,'after'),[{from_page_id:a.page_id,to_page_id:b.page_id,score:.9,status:'inferred',reasons:['controlled_correspondence']}],[],()=> 'entity');};
  const positive=changes(),edit=positive.find(c=>c.kind==='text_modified')!;assert.ok(edit);assert.equal(edit.text_scope,'region');assert.equal(edit.text_assessment,'inferred');assert.deepEqual(edit.evidence.map(e=>e.method),['vision_ocr','vision_ocr']);assert.deepEqual(edit.evidence.map(e=>e.quote),['Revenue 100 won','Revenue 120 won']);assert.ok(edit.coverage_gaps.some(g=>g.reason==='estimated_source_geometry_not_used_for_raster_pairing'));assert.ok(positive.some(c=>c.kind==='coverage_gap'));assert.ok(pages.every(p=>p.elements[0].comparison_role==='unresolved'&&p.elements[0].visibility==='unverified'));
  const noEdit=(a:PageData,b:PageData)=>assert.ok(!changes(a,b).some(c=>c.kind==='text_modified'));
  for(const blocker of ['localized-source','uncertain-ocr','duplicate-ocr','partial-source','marked-ocr'] as const){
    const b=structuredClone(pages[1]),e=structuredClone(b.elements[1]);e.observation_id='blocker';
    if(blocker==='duplicate-ocr'){e.comparison_role='selected';}
    else{e.comparison_role='unresolved';e.visibility='uncertain';if(blocker==='marked-ocr')e.visibility_evidence=[{method:PDF_GEOMETRY_UNVERIFIED,bbox:e.bbox,assessment:'inferred',coverage:0}];if(blocker!=='uncertain-ocr'&&blocker!=='marked-ocr'){e.method='pdf_text';e.provenance='observed';e.text='Localized unread source';e.visibility_evidence=[];if(blocker==='partial-source')e.visibility='partially_occluded';}}
    b.elements.push(e);noEdit(pages[0],b);
  }
  const sameRaster=structuredClone(pages[1]);sameRaster.raster=structuredClone(pages[0].raster);noEdit(pages[0],sameRaster);
  const crossProducer=structuredClone(pages[1]);crossProducer.elements=[{...crossProducer.elements[1],method:'pdf_text',provenance:'observed'}];noEdit(pages[0],crossProducer);
  const unsupported=structuredClone(pages[1]);unsupported.elements[1].text='Revenue 1/2.3 won';noEdit(pages[0],unsupported);
  assert.ok(!positive.some(c=>c.kind==='page_deleted'||c.kind==='page_added'));pages.forEach(p=>Page.parse(p));
});

test('actual native Times numeric edit persists as inferred OCR while raw geometry remains unresolved',async()=>{
  const folder=await mkdtemp(join(tmpdir(),'docver-times-edit-')),library=join(folder,'library');let service=new DesktopService(library);
  try{
    const files:string[]=[];
    for(const value of ['100','120']){const d=new PDFDocument({size:[600,400],margin:0}),chunks:Buffer[]=[];d.on('data',b=>chunks.push(b));const done=new Promise<Buffer>(r=>d.on('end',()=>r(Buffer.concat(chunks))));d.font('Times-Roman').fontSize(32).text('Quarter 1 revenue',50,50,{lineBreak:false});d.text('Revenue '+value+' won',50,120,{lineBreak:false});d.font('Helvetica').fontSize(16).text('Stable public synthetic footer',50,300,{lineBreak:false});d.end();const file=join(folder,value+'.pdf');await writeFile(file,await done);files.push(file);}
    const project=await service.create('Native Times edit',files.map((file,i)=>({label:'v'+i,files:[file]}))),result=await service.run(project.project_id,undefined,undefined,false),edit=result.report.changes.find(c=>c.kind==='text_modified')!;
    assert.ok(edit,'High-confidence independently localized OCR must remain usable');assert.equal(edit.text_scope,'region');assert.equal(edit.text_assessment,'inferred');assert.equal(edit.before,'Revenue 100 won');assert.equal(edit.after,'Revenue 120 won');assert.ok(edit.evidence.every(e=>e.method==='vision_ocr'&&e.provenance==='inferred'));assert.ok(edit.coverage_gaps.some(g=>g.reason==='estimated_source_geometry_not_used_for_raster_pairing'));assert.ok(result.report.changes.some(c=>c.kind==='coverage_gap'));assert.ok(!result.report.changes.some(c=>c.kind==='page_deleted'||c.kind==='page_added'));
    service.commit(project.project_id,result);service.close();service=new DesktopService(library);const report=service.snapshot(project.project_id,result.report.report_id);Report.parse(report);assert.deepEqual(report,result.report);
    for(const revision of report.revisions){const page=service.pageData(project.project_id,report.report_id,revision.pages[0].page_id).page,raw=page.elements.find(e=>e.method==='pdf_text'&&e.text.startsWith('Revenue'))!;assert.equal(raw.visibility,'unverified');assert.equal(raw.comparison_role,'unresolved');assert.ok(raw.visibility_evidence?.some(v=>v.method===PDF_GEOMETRY_UNVERIFIED));assert.ok(page.elements.some(e=>e.method==='vision_ocr'&&e.comparison_role==='selected'&&(e.ocr?.confidence??0)>=.5&&e.ocr?.numeric_consensus));}
  }finally{service.close();await rm(folder,{recursive:true,force:true});}
});
