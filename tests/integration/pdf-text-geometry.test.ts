import {test} from 'node:test';
import assert from 'node:assert/strict';
import PDFDocument from 'pdfkit';
import {getDocument} from 'pdfjs-dist/legacy/build/pdf.mjs';
import {extractPdf,pdfOptions} from '../../packages/ingest/pdf.js';
import {Page,Report,byteHash,type ElementData} from '../../packages/schema/index.js';
import {PDF_GEOMETRY_UNVERIFIED} from '../../packages/ingest/pdf-text-geometry.js';
import {selectHybridComparison} from '../../packages/ingest/comparison-selection.js';
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
  const bytes=await pdf(d=>{for(const x of [20,140,280])d.moveTo(x,20).lineTo(x,160).stroke();for(const y of [20,90,160])d.moveTo(20,y).lineTo(280,y).stroke();for(const [value,x,y]of [['Q1',40,35],['100',160,35],['Q2',40,105],['120',160,105]] as const)write(d,'Times-Roman',value,x,y);d.strike(38,32,50,25);d.rect(150,100,100,35).fill('white');});
  const [page]=await extractPdf(bytes,'sha256:'+byteHash(bytes),{ocr:'off'});assert.equal(page.elements.length,4);assert.ok(page.elements.every(e=>!e.table&&e.visibility==='unverified'&&!e.visibility_spans?.length));
  const raw=page.elements[0],ocr:ElementData={...structuredClone(raw),observation_id:'independent-raster',method:'vision_ocr',source_ref:'raster:1',provenance:'inferred',visibility:'visible',visibility_evidence:[],bbox:[Math.max(0,raw.bbox[0]-.02),Math.max(0,raw.bbox[1]-.02),raw.bbox[2]+.04,raw.bbox[3]+.04]};page.elements.push(ocr);selectHybridComparison(page);
  assert.equal(raw.comparison_role,'unresolved');assert.equal(ocr.comparison_role,'selected');assert.ok(page.coverage_gaps.some(g=>g.reason==='estimated_source_geometry_remains_unresolved'));Page.parse(page);
});

test('unknown painted font extent withholds earlier visibility while later reliable source stays visible',async()=>{
  const bytes=await pdf(d=>{write(d,'Helvetica','Earlier');write(d,'Times-Roman','Unknown');write(d,'Helvetica','Later',40,140);}),[page]=await extractPdf(bytes,'sha256:'+byteHash(bytes),{ocr:'off'});
  const earlier=page.elements.find(e=>e.text==='Earlier')!,unknown=page.elements.find(e=>e.text==='Unknown')!,later=page.elements.find(e=>e.text==='Later')!;
  assert.equal(earlier.visibility,'uncertain');assert.ok(earlier.visibility_evidence?.some(v=>v.method==='later_text_geometry_unverified'));assert.equal(unknown.visibility,'unverified');assert.equal(later.visibility,'visible');assert.ok(later.visibility_spans?.length);Page.parse(page);
  const hidden=await pdf(d=>{write(d,'Helvetica','Clear');d.addContent('3 Tr');write(d,'Times-Roman','Not painted');}),[control]=await extractPdf(hidden,'sha256:'+byteHash(hidden),{ocr:'off'});assert.equal(control.elements.find(e=>e.text==='Clear')!.visibility,'visible');
});

test('standard-font page commits and reloads through actual desktop report and native-page storage',async()=>{
  const folder=await mkdtemp(join(tmpdir(),'docver-standard-font-')),library=join(folder,'library');let service=new DesktopService(library);
  try{const file=join(folder,'times.pdf');await writeFile(file,await pdf(d=>{write(d,'Times-Roman','Original raw text');write(d,'Helvetica','Reliable control',40,140);}));const project=await service.create('Standard font import',[{label:'original',files:[file]}]),result=await service.run(project.project_id,undefined,undefined,false);Report.parse(result.report);assert.equal(result.report.revisions[0].status,'success');assert.equal(result.report.revisions[0].pages.length,1);assert.equal(service.reports(project.project_id).length,0);service.commit(project.project_id,result);service.close();service=new DesktopService(library);const report=service.snapshot(project.project_id,result.report.report_id),page=report.revisions[0].pages[0];assert.deepEqual(report,result.report);assert.deepEqual(service.pageData(project.project_id,report.report_id,page.page_id).page,page);assert.ok(page.elements.some(e=>e.text==='Original raw text'&&e.visibility==='unverified'));}finally{service.close();await rm(folder,{recursive:true,force:true});}
});

test('public-corpus gate rejects nonfinite geometry before JSON can serialize it as null',async()=>{
  const [page]=await extractPdf(await pdf(d=>write(d,'Helvetica','Finite')),'sha256:finite',{ocr:'off'});assert.equal(validateCorpusPages([page],'control').length,1);const invalid=structuredClone(page);invalid.elements[0].bbox[0]=NaN;assert.throws(()=>validateCorpusPages([invalid],'invalid-standard-font'),/invalid-standard-font page 1 failed canonical Page validation/);assert.ok(JSON.stringify(invalid).includes('null'));
});
