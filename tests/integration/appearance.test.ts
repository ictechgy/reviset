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
  const page=await get(d=>{text(d);d.rect(45,74,170,40).fill('white');text(d,'Revenue 120');});
  const old=page.elements.find(e=>e.text==='Revenue 100')!,replacement=page.elements.find(e=>e.text==='Revenue 120')!;
  assert.equal(old.visibility,'occluded');assert.equal(replacement.visibility,'visible');assert.ok(old.visibility_spans!.every(s=>s.state==='occluded'));assert.ok(page.text.includes('100'));assert.ok(page.text.includes('120'));
  assert.ok(page.suppressed_text?.includes('100'));assert.ok(old.visibility_evidence!.some(e=>e.method==='later_opaque_rectangle_per_glyph'));
});
test('background before text, transparent overlay, underline, and table edge never certify deletion',async()=>{
  const background=await get(d=>{d.rect(45,74,170,40).fill('white');text(d);});assert.equal(background.elements[0].visibility,'visible');
  const alpha=await get(d=>{text(d);d.save().fillOpacity(0.4).rect(45,76,170,35).fill('yellow').restore();});assert.notEqual(alpha.elements[0].visibility,'occluded');
  const underline=await get(d=>{text(d);d.moveTo(50,108).lineTo(195,108).stroke();});assert.equal(underline.elements[0].visibility,'visible');
  const edge=await get(d=>{text(d);d.rect(45,76,200,40).stroke();});assert.equal(edge.elements[0].visibility,'uncertain'); // Border intersects the font-metric box; ink separation is unverified.
  const outside=await get(d=>{text(d);d.rect(40,60,220,70).stroke();});assert.equal(outside.elements[0].visibility,'visible');
});
test('partial masks retain per-glyph states and withhold definitive text delta',async()=>{
  const page=await get(d=>{text(d);d.rect(50,74,70,40).fill('white');});
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
  const blend=await get(d=>{text(d);d.save();const gs=d.ref({Type:'ExtGState',BM:'Multiply'});gs.end('');d.page.ext_gstates['BlendTest']=gs;d.addContent('/BlendTest gs');d.rect(45,74,170,40).fill('white').restore();});assert.notEqual(blend.elements[0].visibility,'occluded');
  const partial=await get(d=>{text(d);d.strike(49,76,50,35,{color:'red'});});assert.equal(partial.elements[0].visibility,'partially_struck_through');assert.ok(partial.unresolved_text);
});
test('rotated and cropped PDF coordinates stay within normalized evidence bounds',async()=>{
  const rotated=await get(d=>{(d.page.dictionary.data as any).Rotate=90;(d.page.dictionary.data as any).CropBox=[20,20,580,380];text(d);d.rect(45,74,170,40).fill('white');});
  assert.equal(rotated.width,360);assert.equal(rotated.height,560);assert.equal(rotated.elements[0].visibility,'occluded');
  assert.ok(rotated.elements[0].visibility_spans!.every(s=>s.bbox.every(Number.isFinite)&&s.bbox[0]>=0&&s.bbox[1]>=0));
});
test('solid image masks are not certified visible and compound grid paths are parsed',async()=>{
  const masked=await get(d=>{text(d);const image=d.ref({Type:'XObject',Subtype:'Image',Width:1,Height:1,ImageMask:true,BitsPerComponent:1,Decode:[0,1]});image.end(Buffer.from([0]));d.page.xobjects.MaskTest=image;d.addContent('q\n1 1 1 rg\n170 0 0 35 45 76 cm\n/MaskTest Do\nQ');});
  assert.equal(masked.elements[0].visibility,'uncertain');assert.ok(masked.unresolved_text?.includes('100'));assert.ok(masked.coverage_gaps.some(g=>g.feature==='pdf_visibility'));
  const grid=await get(d=>{for(const x of [50,200,350])d.moveTo(x,50).lineTo(x,150);for(const y of [50,100,150])d.moveTo(50,y).lineTo(350,y);d.stroke();d.fontSize(16).text('Q1',60,65).text('100',210,65).text('Q2',60,115).text('120',210,115);});
  assert.equal(grid.elements.filter(e=>e.table?.origin==='pdf_grid_inferred').length,4);
});
test('full opaque cover replacement yields visible delta while preserving suppressed raw text',async()=>{
  const folder=await mkdtemp(join(tmpdir(),'docver-cover-')),service=new DesktopService(join(folder,'library'));
  try{
    const a=join(folder,'a.pdf'),b=join(folder,'b.pdf');await writeFile(a,await pdf(d=>text(d)));await writeFile(b,await pdf(d=>{text(d);d.rect(45,74,170,40).fill('white');text(d,'Revenue 120');}));
    const project=await service.create('Cover',[{label:'Before',files:[a]},{label:'After',files:[b]}]),{report}=await service.run(project.project_id);
    const c=report.changes.find(c=>c.kind==='text_modified');assert.ok(c);assert.equal(c.before,'Revenue 100');assert.equal(c.after,'Revenue 120');assert.ok(c.coverage_gaps.some(g=>g.reason==='visible_text_after_inferred_opaque_cover'));assert.ok(report.changes.some(c=>c.kind==='text_occluded'));
  }finally{service.close();await rm(folder,{recursive:true,force:true});}
});
test('long PDF element text and glyph visibility are independently traversable within MCP budget',async()=>{
  const folder=await mkdtemp(join(tmpdir(),'docver-spans-')),service=new DesktopService(join(folder,'library'));
  try{
    const source=join(folder,'long.pdf'),value='Revenue 100 verified. '.repeat(10);await writeFile(source,await pdf(d=>d.fillColor('black').fontSize(3).text(value,20,80,{lineBreak:false})));
    const project=await service.create('Spans',[{label:'v1',files:[source]}]),{report}=await service.run(project.project_id),e=report.revisions[0].pages[0].elements[0];assert.ok(e.visibility_spans!.length>100);
    const q=service.queryService(project.project_id),args={project_id:project.project_id,report_id:report.report_id,observation_id:e.observation_id,max_output_tokens:8000};let offset=0,recovered='';
    while(true){const r=q.query('get_element',{...args,text_offset:offset,text_length:19});assert.ok(Buffer.byteLength(JSON.stringify(r))<=8000);const item=r.items[0];assert.equal(item.visibility_spans,undefined);recovered+=item.text;if(item.next_text_offset===null)break;offset=Number(item.next_text_offset);}
    assert.equal(recovered,e.text);offset=0;let count=0;
    while(true){const r=q.query('get_element',{...args,text_length:1,span_offset:offset,span_limit:8});assert.ok(Buffer.byteLength(JSON.stringify(r))<=8000);const item=r.items[0];count+=(item.visibility_spans as unknown[]).length;if(item.next_span_offset===null)break;assert.ok(Number(item.next_span_offset)>offset);offset=Number(item.next_span_offset);}
    assert.equal(count,e.visibility_spans!.length);
  }finally{service.close();await rm(folder,{recursive:true,force:true});}
});
import { matchPages } from '../../packages/matching/index.js';
import { diffRevisions } from '../../packages/diff/index.js';
import type { RevisionData } from '../../packages/schema/index.js';
test('bounded candidates preserve incoming and outgoing ambiguity beyond eight templates',async()=>{
  const template=await get(d=>text(d)),pages=(prefix:string,n:number)=>Array.from({length:n},(_,i)=>({...template,page_id:prefix+i,page:i+1}));
  for(const [left,right] of [[pages('a',1),pages('b',12)],[pages('a',12),pages('b',1)]]){
    const pairing=matchPages(left,right),rev=(id:string,p:typeof left)=>({revision_id:id,revision_occurrence_id:id,label:id,assets:[],status:'success',pages:p,coverage_gaps:[],errors:[],bundle_mapping:[]}) as RevisionData;
    assert.ok(left.every(p=>pairing.candidates.some(c=>c.from_page_id===p.page_id)));assert.ok(right.every(p=>pairing.candidates.some(c=>c.to_page_id===p.page_id)));assert.ok(pairing.matches.every(m=>pairing.candidates.some(c=>c.from_page_id===m.from_page_id&&c.to_page_id===m.to_page_id)));
    const changes=diffRevisions(rev('before',left),rev('after',right),pairing.matches,pairing.candidates,p=>p);assert.ok(changes.every(c=>c.kind!=='page_added'&&c.kind!=='page_deleted'));assert.ok(changes.some(c=>c.coverage_gaps.some(g=>g.reason==='unresolved_mapping')));
  }
});
test('page bounds clips and Form BBoxes do not block ordinary visible text',async()=>{
  const clipped=await get(d=>{d.save().rect(0,0,600,400).clip();text(d);d.restore();});assert.equal(clipped.elements[0].visibility,'visible');assert.equal(clipped.unresolved_text,'');
  const form=await get(d=>{const x=d.ref({Type:'XObject',Subtype:'Form',FormType:1,BBox:[0,0,600,400],Resources:(d.page as any).resources});x.end('q 1 0 0 -1 0 400 cm BT /F1 24 Tf 50 300 Td (Revenue 100) Tj ET Q');d.font('Helvetica');d.page.fonts.F1=(d as any)._font.ref();d.page.xobjects.FormTest=x;d.addContent('/FormTest Do');});
  assert.equal(form.elements[0].visibility,'visible');
});
test('annotation overlay is uncertain while a displayed strike annotation remains observed',async()=>{
  const overlay=await get(d=>{text(d);d.annotate(45,76,170,35,Object.assign({},{Subtype:'Square',IC:[1,1,1],C:[1,1,1]}));});assert.equal(overlay.elements[0].visibility,'uncertain');assert.ok(overlay.elements[0].visibility_evidence!.some(v=>v.method==='annotation_overlay_unverified'));
});
import { OPS } from 'pdfjs-dist/legacy/build/pdf.mjs';
import { paintedGlyphs } from '../../packages/ingest/pdf-glyphs.js';
import { unzipSync,zipSync,strFromU8,strToU8 } from 'fflate';
test('double-quote text operator applies spacing and unknown color cannot certify visibility',()=>{
  const g=(text:string,width:number,space=false)=>({unicode:text,width,isSpace:space}),page={commonObjs:{get:()=>({ascent:0.8,descent:-0.2})}},viewport={width:600,height:400,transform:[1,0,0,-1,0,400]};
  const ops={fnArray:[OPS.beginText,OPS.setFont,OPS.setTextMatrix,OPS.nextLineSetSpacingShowText],argsArray:[null,['font',20],[1,0,0,1,50,300],[10,5,[g('A',500),g(' ',250,true),g('B',500)]]]};
  const glyphs=paintedGlyphs(page,viewport,ops);assert.equal(glyphs.length,3);assert.ok(Math.abs(glyphs[2].bbox[0]-85/600)<0.00001);
  ops.fnArray.splice(3,0,OPS.setFillGray);ops.argsArray.splice(3,0,[1]);assert.equal(paintedGlyphs(page,viewport,ops)[0].reliable,false);
});
test('font geometry rejects degenerate metrics and malformed matrices while matching the renderer default',()=>{
  const viewport={width:600,height:400,transform:[1,0,0,-1,0,400]},ops={fnArray:[OPS.beginText,OPS.setFont,OPS.setTextMatrix,OPS.showText],argsArray:[null,['font',20],[1,0,0,1,50,300],[[{unicode:'A',width:500}]]]};
  const glyph=(font:any,metrics:any)=>paintedGlyphs({commonObjs:{get:()=>font}},viewport,ops,{font:metrics})[0];
  assert.equal(glyph({}, {ascent:0.8,descent:-0.2}).reliable,true);
  for(const metrics of [{ascent:0,descent:-0.2},{ascent:0.1,descent:-0.1},{ascent:0.8,descent:0.2},{descent:-0.2}])assert.equal(glyph({},metrics).reliable,false);
  for(const fontMatrix of [[],[0.001,0,0,0.001,0],[0.002,0,0,0.002,0,0],[NaN,0,0,0.001,0,0],0])assert.equal(glyph({fontMatrix},{ascent:0.8,descent:-0.2}).reliable,false);
});
test('merged OOXML placeholders do not duplicate text and omitted placeholders keep column geometry',async()=>{
  const deck=new (pptxgen as unknown as typeof pptxgen.default)();deck.layout='LAYOUT_WIDE';deck.addSlide().addTable([['A','B','C'],['D','E','F']].map(row=>row.map(text=>({text}))),{x:1,y:1,w:6,h:2});const raw=await deck.write({outputType:'nodebuffer'}) as Buffer;
  for(const compact of [false,true]){
    const zip=unzipSync(raw),path='ppt/slides/slide1.xml';let xml=strFromU8(zip[path]);xml=xml.replace(/<a:tr\b[^>]*>[\s\S]*?<\/a:tr>/,row=>{let index=0;return row.replace(/<a:tc\b[^>]*>[\s\S]*?<\/a:tc>/g,cell=>{index++;if(index===1)return cell.replace('<a:tc>','<a:tc gridSpan="2">');if(index===2)return compact?'':cell.replace('<a:tc>','<a:tc hMerge="1">');return cell;});});zip[path]=strToU8(xml);
    const cells=extractPptx(zipSync(zip),'sha256:merged')[0].elements.filter(e=>e.kind==='table_cell');assert.equal(cells.length,5);assert.ok(!cells.some(e=>e.text==='B'));const a=cells.find(e=>e.text==='A')!,c=cells.find(e=>e.text==='C')!;assert.equal(c.table!.column,2);assert.ok(Math.abs(a.bbox[0]+a.bbox[2]-c.bbox[0])<0.00001);
  }
});

test('unsupported thick curve stroke retains covered text as uncertain with an explicit gap',async()=>{
  const page=await get(d=>{text(d);d.lineWidth(40).moveTo(45,95).bezierCurveTo(90,95,140,95,215,95).stroke('white');});
  assert.equal(page.elements[0].visibility,'uncertain');assert.ok(page.text.includes('Revenue 100'));assert.ok(page.unresolved_text?.includes('100'));assert.equal(page.visible_text,'');assert.ok(page.coverage_gaps.some(g=>g.reason==='curve_stroke_visibility_unverified'));
});
test('hidden optional-content paint cannot certify occlusion of ordinary visible text',async()=>{
  const page=await get(d=>{text(d);const oc=d.ref({Type:'OCG',Name:'Hidden'});oc.end('');(d as any)._root.data.OCProperties={OCGs:[oc],D:{BaseState:'ON',OFF:[oc]}};(d.page as any).resources.data.Properties={HiddenLayer:oc};d.addContent('/OC /HiddenLayer BDC');d.rect(45,74,170,40).fill('white');d.addContent('EMC');});
  assert.equal(page.elements[0].visibility,'uncertain');assert.ok(page.unresolved_text?.includes('100'));assert.ok(page.coverage_gaps.some(g=>g.reason==='optional_content_visibility_unverified'));
});
test('text rendering clip cannot turn a later bounding rectangle into definite occlusion',async()=>{
  const page=await get(d=>{text(d);d.save();d.addContent('BT /F1 24 Tf 4 Tr 0 100 Td (X) Tj ET');d.rect(45,74,170,40).fill('white');d.restore();});assert.equal(page.elements[0].visibility,'uncertain');assert.ok(page.unresolved_text?.includes('Revenue'));assert.ok(page.coverage_gaps.some(g=>g.reason==='clipping_or_soft_mask_visibility_not_fully_verified'));
});
test('strike markup stays in visible text and suppressed raw-layer edits remain explicit',async()=>{
  const folder=await mkdtemp(join(tmpdir(),'docver-layer-')),service=new DesktopService(join(folder,'library'));
  try{
    const plain=join(folder,'plain.pdf'),strike=join(folder,'strike.pdf');await writeFile(plain,await pdf(d=>text(d)));await writeFile(strike,await pdf(d=>{text(d);d.strike(49,76,145,35,{color:'red'});}));
    let project=await service.create('Strike',[{label:'Before',files:[plain]},{label:'After',files:[strike]}]),result=await service.run(project.project_id);
    assert.equal(result.report.revisions[1].pages[0].visible_text,'Revenue 100');assert.ok(!result.report.changes.some(c=>c.kind==='text_modified'));assert.equal(result.report.changes.find(c=>c.kind==='text_struck_through')?.appearance_assessment,'observed');
    const paths=[];for(const number of ['100','200']){const file=join(folder,number+'.pdf');await writeFile(file,await pdf(d=>{text(d,'Revenue '+number);d.rect(45,74,170,40).fill('white');}));paths.push(file);}
    project=await service.create('Suppressed',[{label:'Before',files:[paths[0]]},{label:'After',files:[paths[1]]}]);result=await service.run(project.project_id);
    const gap=result.report.changes.find(c=>c.coverage_gaps.some(g=>g.reason==='raw_text_changed_in_suppressed_layer'));assert.ok(gap);assert.ok(gap.before?.includes('100'));assert.ok(gap.after?.includes('200'));
  }finally{service.close();await rm(folder,{recursive:true,force:true});}
});
test('strike annotation cannot promote hidden or uncertain glyphs to definite visible text',async()=>{
  const hidden=await get(d=>{d.addContent('3 Tr');text(d);d.rect(45,74,170,40).fill('white');d.strike(49,76,145,35,{color:'red'});});assert.equal(hidden.elements[0].visibility,'hidden_render_mode');assert.equal(hidden.visible_text,'');assert.ok(hidden.unresolved_text?.includes('100'));
  const uncertain=await get(d=>{text(d);const image=d.ref({Type:'XObject',Subtype:'Image',Width:1,Height:1,ImageMask:true,BitsPerComponent:1,Decode:[0,1]});image.end(Buffer.from([0]));d.page.xobjects.Mask=image;d.addContent('q 1 1 1 rg 170 0 0 35 45 76 cm /Mask Do Q');d.strike(49,76,145,35,{color:'red'});});assert.equal(uncertain.elements[0].visibility,'uncertain');assert.equal(uncertain.visible_text,'');
});
test('scaled stroke widths and small-font stroke footprints remain uncertain',async()=>{
  const scaled=await get(d=>{text(d);d.save().scale(10).lineWidth(3).moveTo(5,9).lineTo(21.5,9).stroke('white').restore();});assert.equal(scaled.elements[0].visibility,'uncertain');assert.ok(scaled.coverage_gaps.some(g=>g.reason==='thick_stroke_overlap_requires_review'));
  const tiny=await get(d=>{d.fillColor('black').fontSize(2).text('tiny100',50,80,{lineBreak:false});d.lineWidth(2).moveTo(45,81).lineTo(100,81).stroke('white');});assert.equal(tiny.elements[0].visibility,'uncertain');
});
test('fractional text alpha and fill-plus-stroke alpha do not invent definite visibility',async()=>{
  const fractional=await get(d=>{d.fillOpacity(0.01);text(d);});assert.equal(fractional.elements[0].visibility,'unverified');assert.ok(fractional.unresolved_text?.includes('100'));
  const outline=await get(d=>{d.fillOpacity(0).strokeOpacity(1).addContent('2 Tr');text(d);});assert.equal(outline.elements[0].visibility,'unverified');assert.notEqual(outline.elements[0].visibility,'hidden_render_mode');
});
import { renderPdf } from '../../packages/render/index.js';
test('equal-render fill-plus-stroke text never becomes a definitive visible text delta',async()=>{
  const a=await pdf(d=>{d.fillColor('black').strokeColor('white').lineWidth(100).addContent('2 Tr').fontSize(24).text('A100 Stable shared title',50,80,{lineBreak:false});}),b=await pdf(d=>{d.fillColor('black').strokeColor('white').lineWidth(100).addContent('2 Tr').fontSize(24).text('B100 Stable shared title',50,80,{lineBreak:false});});
  assert.deepEqual(await renderPdf(a,1,600),await renderPdf(b,1,600));
  const left=(await extractPdf(a,'sha256:a'))[0],right=(await extractPdf(b,'sha256:b'))[0];assert.equal(left.elements[0].visibility,'unverified');assert.equal(right.elements[0].visibility,'unverified');assert.ok(left.unresolved_text?.includes('A100'));
  const rev=(id:string,p:typeof left)=>({revision_id:id,revision_occurrence_id:id,label:id,assets:[],status:'success',pages:[p],coverage_gaps:[],errors:[],bundle_mapping:[]}) as RevisionData,pair=matchPages([left],[right]);const changes=diffRevisions(rev('a',left),rev('b',right),pair.matches,pair.candidates,p=>p);assert.ok(!changes.some(c=>c.kind==='text_modified'));assert.ok(changes.some(c=>c.kind==='coverage_gap'));
});
test('PDF.js source-over blend retains normal visible text, opaque cover and numeric diff',async()=>{
  const normal=(d:PDFKit.PDFDocument)=>{const gs=d.ref({Type:'ExtGState',BM:'Normal',ca:1,CA:1});gs.end('');d.page.ext_gstates.NormalTest=gs;d.addContent('/NormalTest gs');};
  const before=await get(d=>{normal(d);text(d);}),after=await get(d=>{normal(d);text(d,'Revenue 120');}),cover=await get(d=>{normal(d);text(d);d.rect(45,74,170,40).fill('white');});assert.equal(before.elements[0].visibility,'visible');assert.equal(after.elements[0].visibility,'visible');assert.equal(cover.elements[0].visibility,'occluded');
  before.page_id='left';after.page_id='right';const rev=(id:string,p:typeof before)=>({revision_id:id,revision_occurrence_id:id,label:id,assets:[],status:'success',pages:[p],coverage_gaps:[],errors:[],bundle_mapping:[]}) as RevisionData,pair=matchPages([before],[after]);assert.ok(diffRevisions(rev('a',before),rev('b',after),pair.matches,pair.candidates,p=>p).some(c=>c.kind==='text_modified'));
});
test('unmatched hidden or fully covered pages never fabricate definitive add/delete events',async()=>{
  for(const mode of ['invisible','covered']){
    const make=(value:string)=>pdf(d=>{if(mode==='invisible')d.addContent('3 Tr');text(d,value);if(mode==='covered')d.rect(45,74,170,40).fill('white');});const a=await make('Revenue 100'),b=await make('ZZZZ');assert.deepEqual(await renderPdf(a,1,600),await renderPdf(b,1,600));
    const left=(await extractPdf(a,'sha256:a'))[0],right=(await extractPdf(b,'sha256:b'))[0],rev=(id:string,p:typeof left)=>({revision_id:id,revision_occurrence_id:id,label:id,assets:[],status:'success',pages:[p],coverage_gaps:[],errors:[],bundle_mapping:[]}) as RevisionData,pair=matchPages([left],[right]);assert.equal(pair.matches.length,0);assert.equal(pair.candidates.length,0);
    const changes=diffRevisions(rev('a',left),rev('b',right),pair.matches,pair.candidates,p=>p);assert.equal(changes.length,2);assert.ok(changes.every(c=>c.kind==='coverage_gap'&&c.coverage_gaps.length));
  }
});
test('small nearly opaque covers and short strokes across a minus glyph remain unresolved',async()=>{
  const draw=(d:PDFKit.PDFDocument)=>d.fillColor('black').fontSize(12).text('-500',50,80,{lineBreak:false}),base=await get(draw),minus=base.elements[0].visibility_spans!.find(s=>s.text==='-')!,b=minus.bbox;
  for(const kind of ['fill','stroke']){
    const page=await get(d=>{draw(d);const x=b[0]*600,y=(b[1]+b[3]*0.5)*400,w=b[2]*600;
      if(kind==='fill')d.fillOpacity(0.995).rect(x,y-b[3]*400*0.05,w,b[3]*400*0.1).fill('white');
      else d.lineWidth(2).moveTo(x,y).lineTo(x+w,y).stroke('white');
    });
    assert.equal(page.elements[0].visibility,'uncertain',kind);assert.equal(page.elements[0].visibility_spans!.find(s=>s.text==='-')!.state,'uncertain');assert.ok(page.unresolved_text?.includes('-500'));assert.ok(!page.visible_text?.includes('-'));assert.ok(page.text.includes('-500'));
  }
});
import { createCanvas,loadImage } from '@napi-rs/canvas';
test('sub-five-percent covers over actual punctuation ink preserve uncertainty and raw values',async()=>{
  for(const value of ['1.5','1,000']){
    const draw=(d:PDFKit.PDFDocument)=>d.fillColor('black').fontSize(12).text('Revenue '+value,50,80,{lineBreak:false}),raw=await pdf(draw),before=(await extractPdf(raw,'sha256:punct-before'))[0],punctuation=value.includes('.')?'.':',',span=before.elements[0].visibility_spans!.find(s=>s.text===punctuation)!,b=span.bbox;
    const png=await loadImage(await renderPdf(raw,1,2400)),canvas=createCanvas(png.width,png.height),ctx=canvas.getContext('2d');ctx.drawImage(png,0,0);const pixels=ctx.getImageData(0,0,png.width,png.height).data;
    const ink:number[][]=[];for(let y=Math.ceil(b[1]*png.height);y<Math.floor((b[1]+b[3])*png.height);y++)for(let x=Math.ceil(b[0]*png.width);x<Math.floor((b[0]+b[2])*png.width);x++)if(pixels[(y*png.width+x)*4]<128)ink.push([x,y]);assert.ok(ink.length);
    const scale=png.width/600,x=ink[0][0]/scale,y=ink[0][1]/scale,w=1.3,h=1.3;assert.ok(w*h/(b[2]*600*b[3]*400)<0.05);
    for(const kind of ['fill','stroke','Square','SquareInvisible','Redact','Link','StrikeOut']){
      const afterRaw=await pdf(d=>{draw(d);if(kind==='fill')d.rect(x,y,w,h).fill('white');else if(kind==='stroke')d.lineWidth(0.2).moveTo(x,y+0.125).lineTo(x+w,y+0.125).stroke('white');else{const appearance=d.ref({Type:'XObject',Subtype:'Form',BBox:[0,0,w,h],Resources:{}});appearance.end('1 1 1 rg 0 0 1.3 1.3 re f');d.annotate(x,y,w,h,Object.assign({},{Subtype:kind==='SquareInvisible'?'Square':kind,IC:[1,1,1],C:[1,1,1],AP:{N:appearance}},kind==='SquareInvisible'?{F:1}:{},kind==='StrikeOut'?{QuadPoints:[x,400-y,x+w,400-y,x,400-y-h,x+w,400-y-h]}:{}));}}),after=(await extractPdf(afterRaw,'sha256:punct-after'))[0];
      assert.equal(after.elements[0].visibility,'uncertain',value+':'+kind);assert.equal(after.elements[0].visibility_spans!.find(s=>s.text===punctuation)!.state,'uncertain');assert.ok(after.text.includes(value));assert.ok(after.unresolved_text?.includes(value));
      const rev=(id:string,p:typeof before)=>({revision_id:id,revision_occurrence_id:id,label:id,assets:[],status:'success',pages:[p],coverage_gaps:[],errors:[],bundle_mapping:[]}) as RevisionData,pair=matchPages([before],[after]),changes=diffRevisions(rev('a',before),rev('b',after),pair.matches,pair.candidates,p=>p);assert.ok(changes.some(c=>c.coverage_gaps.some(g=>g.reason==='pdf_visibility_unresolved_text_comparison_withheld')));
    }
  }
});
test('zero-width device hairlines and curves cannot create an equal-render numeric delta',async()=>{
  for(const curve of [false,true]){
    const make=(value:string)=>pdf(d=>{d.fillColor('black').fontSize(12).text('Revenue '+value,50,80,{lineBreak:false});for(let y=85;y<=92;y+=0.25){d.lineWidth(0).moveTo(107,y);if(curve)d.bezierCurveTo(108,y,109.5,y,110.5,y);else d.lineTo(110.5,y);d.stroke('white');}}),a=await make('1.5'),b=await make('1,5');
    if(!curve)assert.equal(Buffer.compare(await renderPdf(a,1,1200),await renderPdf(b,1,1200)),0,'straight hairline reproduction must render identically');
    const left=(await extractPdf(a,'sha256:hairline-a'))[0],right=(await extractPdf(b,'sha256:hairline-b'))[0];assert.ok(left.unresolved_text?.includes('1.5'));assert.ok(right.unresolved_text?.includes('1,5'));assert.ok(left.coverage_gaps.some(g=>g.reason==='device_hairline_visibility_unverified'));
    const rev=(id:string,p:typeof left)=>({revision_id:id,revision_occurrence_id:id,label:id,assets:[],status:'success',pages:[p],coverage_gaps:[],errors:[],bundle_mapping:[]}) as RevisionData,pair=matchPages([left],[right]),changes=diffRevisions(rev('a',left),rev('b',right),pair.matches,pair.candidates,p=>p);assert.ok(!changes.some(c=>c.kind==='text_modified'));assert.ok(changes.some(c=>c.kind==='coverage_gap'));
  }
});
test('miter joins outside segment padding preserve equal-render numeric uncertainty including ExtGState',async()=>{
  for(const gs of [false,true]){
    const make=(value:string)=>pdf(d=>{d.fillColor('black').fontSize(12).text('Revenue '+value,50,80,{lineBreak:false});if(gs){const style=d.ref({Type:'ExtGState',LW:2,LC:0,LJ:0,ML:10});style.end('');d.page.ext_gstates.JoinTest=style;d.addContent('/JoinTest gs');}else d.lineWidth(2).lineJoin('miter').miterLimit(10);
      for(let x=106;x<=112;x+=0.125)d.moveTo(x-1.1,103).lineTo(x,93).lineTo(x+1.1,103).stroke('white');}),a=await make('1.5'),b=await make('1,5');
    assert.equal(Buffer.compare(await renderPdf(a,1,1200),await renderPdf(b,1,1200)),0);
    const left=(await extractPdf(a,'sha256:join-a'))[0],right=(await extractPdf(b,'sha256:join-b'))[0];assert.ok(left.unresolved_text?.includes('1.5'));assert.ok(right.unresolved_text?.includes('1,5'));assert.ok(left.coverage_gaps.some(g=>g.reason==='stroke_join_geometry_unverified'));
    const rev=(id:string,p:typeof left)=>({revision_id:id,revision_occurrence_id:id,label:id,assets:[],status:'success',pages:[p],coverage_gaps:[],errors:[],bundle_mapping:[]}) as RevisionData,pair=matchPages([left],[right]),changes=diffRevisions(rev('a',left),rev('b',right),pair.matches,pair.candidates,p=>p);assert.ok(!changes.some(c=>c.kind==='text_modified'));assert.ok(changes.some(c=>c.kind==='coverage_gap'));
  }
});
test('ExtGState thick and zero-width strokes never use stale line width',async()=>{
  for(const width of [0,30]){
    const make=(value:string)=>pdf(d=>{d.fillColor('black').fontSize(12).text('Revenue '+value,50,80,{lineBreak:false});const gs=d.ref({Type:'ExtGState',LW:width});gs.end('');d.page.ext_gstates.WidthTest=gs;d.addContent('/WidthTest gs');if(width===0){for(let y=85;y<=92;y+=0.25)d.moveTo(107,y).lineTo(110.5,y).stroke('white');}else d.moveTo(40,100).lineTo(300,100).stroke('white');}),a=await make('1.5'),b=await make('1,5');assert.equal(Buffer.compare(await renderPdf(a,1,1200),await renderPdf(b,1,1200)),0);
    const left=(await extractPdf(a,'sha256:gs-a'))[0],right=(await extractPdf(b,'sha256:gs-b'))[0];assert.ok(left.unresolved_text?.includes('1.5'));assert.ok(right.unresolved_text?.includes('1,5'));if(width===0)assert.ok(left.coverage_gaps.some(g=>g.reason==='device_hairline_visibility_unverified'));
  }
});
test('unimplemented ExtGState font changes cannot certify stale glyph geometry',async()=>{
  const page=await get(d=>{d.fillColor('black').fontSize(12).text('Stable title',50,30,{lineBreak:false});const f=(d as any)._font,gs=d.ref({Type:'ExtGState',Font:[f.ref(),24]});gs.end('');d.page.ext_gstates.FontTest=gs;d.addContent(`BT /${f.id} 12 Tf /FontTest gs 1 0 0 1 50 300 Tm (Revenue 1.5) Tj ET`);});
  assert.ok(page.text.includes('Revenue 1.5'));assert.ok(page.unresolved_text?.includes('Revenue 1.5'));assert.ok(page.coverage_gaps.some(g=>g.reason==='unsupported_graphics_state:Font'));assert.ok(page.elements.some(e=>e.visibility==='unverified'));
});
test('real subpixel stroke ink remains unresolved for direct, GS, nonuniform and sheared transforms',async()=>{
  const draw=(d:PDFKit.PDFDocument)=>d.fillColor('black').fontSize(12).text('Revenue 1.5',50,80,{lineBreak:false}),raw=await pdf(draw),base=(await extractPdf(raw,'sha256:thin-before'))[0],b=base.elements[0].visibility_spans!.find(s=>s.text==='.')!.bbox;
  const crop=async(bytes:Uint8Array)=>{const img=await loadImage(await renderPdf(bytes,1,600)),canvas=createCanvas(img.width,img.height),ctx=canvas.getContext('2d');ctx.drawImage(img,0,0);return Buffer.from(ctx.getImageData(Math.floor(b[0]*600),Math.floor(b[1]*400),Math.ceil(b[2]*600),Math.ceil(b[3]*400)).data);},original=await crop(raw);
  for(const matrix of [[1,0,0,1],[1.2,0,0,0.8],[1,0.3,0.2,1]])for(const gs of [false,true]){
    const [a,c1,c2,d1]=matrix,det=a*d1-c1*c2,point=(x:number,y:number)=>[(d1*x-c2*y)/det,(a*y-c1*x)/det];
    const afterRaw=await pdf(d=>{draw(d);d.save().transform(a,c1,c2,d1,0,0);if(gs){const style=d.ref({Type:'ExtGState',LW:0.05});style.end('');d.page.ext_gstates.ThinTest=style;d.addContent('/ThinTest gs');}else d.lineWidth(0.05);const start=point(108.5,88.125),end=point(109.8,88.125);d.moveTo(start[0],start[1]).lineTo(end[0],end[1]).stroke('white').restore();}),after=(await extractPdf(afterRaw,'sha256:thin-after'))[0];
    assert.notEqual(Buffer.compare(original,await crop(afterRaw)),0,'stroke must change actual punctuation ink');assert.equal(after.elements[0].visibility,'uncertain');assert.ok(after.text.includes('1.5'));assert.ok(after.unresolved_text?.includes('1.5'));
  }
});
test('right-angle cell corners do not make six-point-padded readable text uncertain',async()=>{
  const make=(first:boolean)=>pdf(d=>{const border=()=>d.lineWidth(1).lineJoin('miter').miterLimit(10).rect(50,70,180,40).stroke('black');if(first)border();d.fillColor('black').fontSize(12).text('Revenue 1.5',56,76,{lineBreak:false});if(!first)border();}),a=await make(true),b=await make(false);assert.equal(Buffer.compare(await renderPdf(a,1,1200),await renderPdf(b,1,1200)),0);
  assert.equal((await extractPdf(a,'sha256:cell-a'))[0].elements[0].visibility,'visible');assert.equal((await extractPdf(b,'sha256:cell-b'))[0].elements[0].visibility,'visible');
});
