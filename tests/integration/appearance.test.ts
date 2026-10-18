import { test } from 'node:test';
import assert from 'node:assert/strict';
import PDFDocument from 'pdfkit';
import pptxgen from 'pptxgenjs';
import { extractPdf } from '../../packages/ingest/pdf.js';
import { extractPptx } from '../../packages/ingest/pptx.js';
import { mkdtemp,writeFile,rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { DesktopService } from '../../packages/desktop/service.js';
async function pdf(draw:(doc:PDFKit.PDFDocument)=>void):Promise<Uint8Array>{
  const doc=new PDFDocument({size:[600,400],margin:0}),chunks:Buffer[]=[];doc.on('data',b=>chunks.push(b));const done=new Promise<Buffer>(res=>doc.on('end',()=>res(Buffer.concat(chunks))));draw(doc);doc.end();return done;
}
const text=(d:PDFKit.PDFDocument,value='Revenue 100')=>d.fillColor('black').fontSize(24).text(value,50,80,{lineBreak:false});
const get=async(draw:(d:PDFKit.PDFDocument)=>void)=>(await extractPdf(await pdf(draw),'sha256:test'))[0];
test('late opaque box suppresses old glyphs but not replacement painted afterward',async()=>{
  const page=await get(d=>{text(d);d.rect(45,76,170,35).fill('white');text(d,'Revenue 120');});
  const old=page.elements.find(e=>e.text==='Revenue 100')!,replacement=page.elements.find(e=>e.text==='Revenue 120')!;
  assert.equal(old.visibility,'occluded');assert.equal(replacement.visibility,'visible');assert.ok(old.visibility_spans!.every(s=>s.state==='occluded'));assert.ok(page.text.includes('100'));assert.ok(page.text.includes('120'));
  assert.ok(page.unresolved_text?.includes('100'));assert.ok(old.visibility_evidence!.some(e=>e.method==='later_opaque_rectangle_per_glyph'));
});
test('background before text, transparent overlay, underline, and table edge never certify deletion',async()=>{
  const background=await get(d=>{d.rect(45,76,170,35).fill('white');text(d);});assert.equal(background.elements[0].visibility,'visible');
  const alpha=await get(d=>{text(d);d.save().fillOpacity(0.4).rect(45,76,170,35).fill('yellow').restore();});assert.notEqual(alpha.elements[0].visibility,'occluded');
  const underline=await get(d=>{text(d);d.moveTo(50,108).lineTo(195,108).stroke();});assert.equal(underline.elements[0].visibility,'visible');
  const edge=await get(d=>{text(d);d.rect(45,76,200,40).stroke();});assert.equal(edge.elements[0].visibility,'visible');
});
test('partial masks retain per-glyph states and withhold definitive text delta',async()=>{
  const page=await get(d=>{text(d);d.rect(50,76,70,35).fill('white');});
  assert.equal(page.elements[0].visibility,'partially_occluded');assert.ok(page.elements[0].visibility_spans!.some(s=>s.state==='visible'));assert.ok(page.elements[0].visibility_spans!.some(s=>s.state==='occluded'));
  assert.ok(page.coverage_gaps.some(g=>g.reason.includes('visibility_requires_review')));
});
test('strike annotation, hidden annotation, flattened strike, and repeated gridlines are distinct',async()=>{
  const annotation=await get(d=>{text(d);d.strike(49,76,145,35,{color:'red'});});assert.equal(annotation.elements[0].visibility,'struck_through');assert.ok(annotation.elements[0].visibility_evidence!.some(e=>e.assessment==='observed'));
  const hidden=await get(d=>{text(d);d.strike(49,76,145,35,Object.assign({color:'red'},{F:32}));});assert.equal(hidden.elements[0].visibility,'visible');
  const line=await get(d=>{text(d);d.moveTo(50,90).lineTo(192,90).stroke('red');});assert.equal(line.elements[0].visibility,'struck_inferred');assert.ok(line.unresolved_text?.includes('Revenue'));
  const grid=await get(d=>{text(d);for(const y of [75,90,120])d.moveTo(45,y).lineTo(250,y).stroke();for(const x of [45,145,250])d.moveTo(x,75).lineTo(x,120).stroke();});assert.notEqual(grid.elements[0].visibility,'struck_inferred');
});
test('invisible OCR rendering mode and white-on-white remain explicit gaps',async()=>{
  const hidden=await get(d=>{d.addContent('3 Tr');text(d);});assert.equal(hidden.elements[0].visibility,'hidden_render_mode');assert.ok(hidden.unresolved_text?.includes('Revenue'));
  const white=await get(d=>{d.fillColor('white').fontSize(24).text('Hidden content',50,80,{lineBreak:false});});assert.equal(white.elements[0].visibility,'uncertain');
});
test('PPTX cell structure is observed; PDF grid inference never claims original table semantics',async()=>{
  const deck=new (pptxgen as unknown as typeof pptxgen.default)();deck.layout='LAYOUT_WIDE';const slide=deck.addSlide();slide.addTable([[{text:'Quarter'},{text:'Revenue'}],[{text:'Q1'},{text:'100'}]],{x:1,y:1,w:6,h:2,fontSize:20});
  const raw=await deck.write({outputType:'nodebuffer'}) as Buffer,pptx=extractPptx(raw,'sha256:table');
  const cells=pptx[0].elements.filter(e=>e.kind==='table_cell');assert.equal(cells.length,4);assert.ok(cells.every(e=>e.table?.origin==='ooxml_table'&&e.table.assessment==='observed'));assert.ok(pptx[0].text.includes('100'));
  const grid=await get(d=>{for(const x of [50,200,350])d.moveTo(x,50).lineTo(x,150).stroke();for(const y of [50,100,150])d.moveTo(50,y).lineTo(350,y).stroke();d.fontSize(16).text('Q1',60,65).text('100',210,65).text('Q2',60,115).text('120',210,115);});
  assert.equal(grid.elements.filter(e=>e.table?.origin==='pdf_grid_inferred').length,4);assert.ok(grid.elements.every(e=>e.kind==='text'));
  const framed=await get(d=>{d.rect(40,40,400,150).stroke();text(d);});assert.ok(framed.elements.every(e=>!e.table));
});
test('desktop compute is uncommitted until coordinator transaction; recovery and past snapshots persist',async()=>{
  const folder=await mkdtemp(join(tmpdir(),'docver-desktop-')),service=new DesktopService(join(folder,'library'));
  try{
    const file=join(folder,'source.pdf');await writeFile(file,await pdf(d=>text(d)));
    const p=await service.create('Native',[{label:'v1',files:[file]}]);const result=await service.run(p.project_id,undefined,undefined,false);
    assert.equal(service.reports(p.project_id).length,0);assert.equal(service.project(p.project_id).last_report_id,null);
    service.commit(p.project_id,result);assert.equal(service.reports(p.project_id).length,1);assert.equal(service.project(p.project_id).last_report_id,result.report.report_id);
    const second=await service.run(p.project_id,undefined,undefined,false);service.recover(second.analysis_run_id);assert.throws(()=>service.commit(p.project_id,second),{code:'INVALID_RUN'});
    assert.equal(service.reports(p.project_id).length,1);
  }finally{service.close();await rm(folder,{recursive:true,force:true});}
});

test('nonrectangular fills, clipped text, blended groups and partial strike stay conservative',async()=>{
  const polygon=await get(d=>{text(d);d.moveTo(45,76).lineTo(215,76).lineTo(180,111).lineTo(80,111).closePath().fill('white');});assert.notEqual(polygon.elements[0].visibility,'occluded');assert.ok(polygon.unresolved_text);
  const clipped=await get(d=>{d.save().rect(50,80,40,20).clip();text(d);d.restore();});assert.equal(clipped.elements[0].visibility,'unverified');assert.ok(clipped.coverage_gaps.some(g=>g.feature==='pdf_visibility'));
  const blend=await get(d=>{text(d);d.save();const gs=d.ref({Type:'ExtGState',BM:'Multiply'});gs.end('');d.page.ext_gstates['BlendTest']=gs;d.addContent('/BlendTest gs');d.rect(45,76,170,35).fill('white').restore();});assert.notEqual(blend.elements[0].visibility,'occluded');
  const partial=await get(d=>{text(d);d.strike(49,76,50,35,{color:'red'});});assert.equal(partial.elements[0].visibility,'partially_struck_through');assert.ok(partial.unresolved_text);
});
test('rotated and cropped PDF coordinates stay within normalized evidence bounds',async()=>{
  const rotated=await get(d=>{(d.page.dictionary.data as any).Rotate=90;(d.page.dictionary.data as any).CropBox=[20,20,580,380];text(d);d.rect(45,76,170,35).fill('white');});
  assert.equal(rotated.width,360);assert.equal(rotated.height,560);assert.equal(rotated.elements[0].visibility,'occluded');
  assert.ok(rotated.elements[0].visibility_spans!.every(s=>s.bbox.every(Number.isFinite)&&s.bbox[0]>=0&&s.bbox[1]>=0));
});
