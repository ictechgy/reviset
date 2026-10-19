import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {mkdir,readFile,writeFile,rename,rm,lstat,readlink} from 'node:fs/promises';
import {resolve,join} from 'node:path';
import {randomUUID} from 'node:crypto';
import PDFDocument from 'pdfkit';
import {createCanvas,loadImage} from '@napi-rs/canvas';
import {unzipSync,zipSync,strToU8} from 'fflate';
import {extractPdf} from '../packages/ingest/pdf.js';
import {extractPptx} from '../packages/ingest/pptx.js';
import {captureNativePages,type NativePageResult} from '../packages/ingest/ocr.js';
import {preparePptxPreview} from '../packages/render/pptx-preview.js';
import {validateRenderPackage,renderPdf} from '../packages/render/index.js';
import {runTool,visionExecutable,visionInfo} from '../packages/runtime/tools.js';
import {byteHash,normalize,ENGINE_VERSION} from '../packages/schema/index.js';
import {DesktopService} from '../packages/desktop/service.js';
import {fileSha256} from '../packages/runtime/file-hash.js';

type Box=[number,number,number,number];
type Region={text:string;bbox:Box};
type Source={id:string;url:string;format:'pdf'|'pptx';sha256:string;bytes:number;pages?:number;expected_pages?:number;expected_nonempty_table_cells?:{row:number;column:number;text:string;row_span:number;column_span:number}[][];passive_scan:{result:string}};
const folder=resolve('output/public-corpus'),cache=join(folder,'cache'),download=process.argv.includes('--download');
const manifest=JSON.parse(await readFile('docs/fixtures/public-corpus.json','utf8')) as {sources:Source[]};
const truth=JSON.parse(await readFile('docs/fixtures/public-corpus-truth.json','utf8')) as {regions:Record<string,Region[]>};
const head=execFileSync('git',['rev-parse','HEAD'],{encoding:'utf8'}).trim(),patch=execFileSync('git',['diff','--binary','HEAD']);
const untracked: {path:string;kind:string;sha256:string}[]=[];
for(const path of execFileSync('git',['ls-files','--others','--exclude-standard','-z'],{encoding:'utf8'}).split('\0').filter(Boolean).sort()){
  const stat=await lstat(path);
  if(!stat.isFile()&&!stat.isSymbolicLink())throw new Error('Cannot fingerprint non-regular untracked source: '+JSON.stringify(path));
  // Hash link text rather than reading a target that may be outside the repository.
  untracked.push({path,kind:stat.isSymbolicLink()?'symlink':'file',sha256:stat.isSymbolicLink()?byteHash(Buffer.from(await readlink(path))):await fileSha256(path)});
}
const sourceClean=!patch.length&&!untracked.length,patchSha=patch.length?byteHash(patch):null,dirtySha=sourceClean?null:byteHash(Buffer.from(JSON.stringify({patchSha,untracked})));
const run=join(folder,'runs',head.slice(0,8)+(dirtySha?'-dirty-'+dirtySha.slice(0,8):''));await mkdir(run,{recursive:true});
const compact=(s:string)=>normalize(s).normalize('NFKC').toLowerCase().replace(/\s/gu,'').replace(/⁄/g,'/');
function intersects(a:Box,b:Box){return Math.max(0,Math.min(a[0]+a[2],b[0]+b[2])-Math.max(a[0],b[0]))*Math.max(0,Math.min(a[1]+a[3],b[1]+b[3])-Math.max(a[1],b[1]));}
function regionResult(native:NativePageResult,regions:Region[],occluded?:Box){return regions.map(region=>{
  const rows=native.lines.filter(line=>intersects(line.bbox,region.bbox)>0.2*line.bbox[2]*line.bbox[3]),text=rows.map(l=>l.text).join(' '),hidden=occluded&&intersects(occluded,region.bbox)>=0.95*region.bbox[2]*region.bbox[3];
  return {...region,state:hidden?'fully_occluded':occluded&&intersects(occluded,region.bbox)?'partially_occluded':'visible',raw_exact:text.includes(region.text),normalized_found:compact(text).includes(compact(region.text)),readings:rows.map(l=>({text:l.text,bbox:l.bbox,confidence:l.confidence,numeric_consensus:l.numeric_consensus})),scoring:'Selected-region recognition only, not whole-document accuracy; fully occluded regions excluded from recall'};
});}
async function bytesFor(source:Source){
  assert.match(source.id,/^[a-z0-9-]+$/);assert.equal(source.passive_scan.result,'PASS');
  const path=join(folder,source.id+'.'+source.format);let bytes:Buffer|undefined;try{bytes=await readFile(path);}catch{/* explicit download below */}
  if(!bytes||byteHash(bytes)!==source.sha256){
    assert.ok(download,'Missing/corrupt pinned fixture; run with --download: '+source.id);
    const url=new URL(source.url);assert.equal(url.protocol,'https:');assert.ok(['raw.githubusercontent.com','www.w3.org'].includes(url.hostname));assert.equal(url.username+url.password,'');
    const response=await fetch(url,{redirect:'error',signal:AbortSignal.timeout(30000)});assert.ok(response.ok,'HTTP '+response.status);assert.ok(Number(response.headers.get('content-length')??0)<=12*1024*1024);
    const chunks:Uint8Array[]=[];let length=0;try{for await(const chunk of response.body!){length+=chunk.length;assert.ok(length<=12*1024*1024,'Download byte limit');chunks.push(chunk);}}catch(e){await response.body?.cancel().catch(()=>{});throw e;}
    bytes=Buffer.concat(chunks);assert.equal(byteHash(bytes),source.sha256,'Pinned SHA mismatch');const temp=path+'.'+randomUUID()+'.tmp';try{await writeFile(temp,bytes,{flag:'wx'});await rename(temp,path);}finally{await rm(temp,{force:true});}
  }
  assert.equal(bytes.length,source.bytes);assert.equal(byteHash(bytes),source.sha256);assert.ok(source.format==='pdf'?bytes.subarray(0,5).toString()==='%PDF-':bytes.subarray(0,2).toString()==='PK');return {path,bytes};
}
async function pdfImage(image:Buffer,width:number,height:number){const d=new PDFDocument({size:[width,height],margin:0}),chunks:Buffer[]=[];d.on('data',b=>chunks.push(b));const done=new Promise<Buffer>(r=>d.on('end',()=>r(Buffer.concat(chunks))));d.image(image,0,0,{width,height});d.end();return done;}
const results:any[]=[];const variants:any[]=[];
for(const source of manifest.sources){
  const {path,bytes}=await bytesFor(source),out=join(run,source.id);await mkdir(out,{recursive:true});const start=Date.now();
  if(source.format==='pdf'){
    const numbers=Array.from({length:source.pages!},(_,i)=>i+1),native=await captureNativePages(bytes,numbers,numbers,{sourceFile:path,cacheRoot:cache,reuseRasterOcr:false});assert.equal(native.size,numbers.length,'Every source page must return a native observation');assert.ok([...native.values()].every(n=>n.ocr_performed&&n.lines.length),'No silent failed/empty native OCR');
    const pages=await extractPdf(bytes,'sha256:'+source.sha256,{ocr:'all',sourceFile:path,cacheRoot:cache,reuseRasterOcr:false});assert.equal(pages.length,source.pages);
    await writeFile(join(out,'native.json'),JSON.stringify([...native],null,2));await writeFile(join(out,'pages.json'),JSON.stringify(pages,null,2));await runTool(visionExecutable()!,[],{input:JSON.stringify({path,page:1,render_only:true,render_path:join(out,'page-1.png')})});
    const first=native.get(1)!;results.push({id:source.id,source_sha256:source.sha256,pages:pages.length,ocr_lines:pages.map(p=>native.get(p.page)!.lines.length),native_tables:pages.map(p=>native.get(p.page)!.tables?.length??0),raster_grid_tables:pages.map(p=>native.get(p.page)!.grid_tables?.length??0),uncertain_ocr_lines:pages.map(p=>p.elements.filter(e=>e.method==='vision_ocr'&&e.visibility!=='visible').length),regions:regionResult(first,truth.regions[source.id]??[]),seconds:(Date.now()-start)/1000});
    if(source.id==='azure-layout'){const grids=first.grid_tables??[];assert.ok(grids.some(t=>t.cells.length===9&&t.cells.some(c=>c.row===2&&c.column===1&&c.text==='Microsoft')&&t.cells.filter(c=>!c.text.trim()).length===2),'Downloaded Microsoft3x3 table and two unobserved values must retain structure');}
    if(truth.regions[source.id]){
      const image=await loadImage(join(out,'page-1.png')),page=pages[0];
      for(const kind of ['flattened','low-resolution-jpeg','skew-1.5deg','occluded'] as const){
        const scale=kind==='low-resolution-jpeg'?0.45:1,w=Math.round(image.width*scale),h=Math.round(image.height*scale),canvas=createCanvas(w,h),ctx=canvas.getContext('2d'),angle=kind==='skew-1.5deg'?1.5*Math.PI/180:0;
        ctx.fillStyle='white';ctx.fillRect(0,0,w,h);ctx.translate(w/2,h/2);ctx.rotate(angle);ctx.drawImage(image,-w/2,-h/2,w,h);ctx.resetTransform();
        const mask:Box|undefined=kind==='occluded'?[...truth.regions[source.id][0].bbox]:undefined;if(mask){ctx.fillStyle='#555';ctx.fillRect(mask[0]*w,mask[1]*h,mask[2]*w,mask[3]*h);}
        const raster=kind==='low-resolution-jpeg'?canvas.toBuffer('image/jpeg',55):canvas.toBuffer('image/png'),pdf=await pdfImage(raster,page.width,page.height),variant=join(out,kind+'.pdf');await writeFile(variant,pdf);
        const observed=await captureNativePages(pdf,[1],[1],{sourceFile:variant,cacheRoot:cache,reuseRasterOcr:false});assert.equal(observed.size,1);const result=observed.get(1)!;
        const c=Math.cos(angle),s=Math.sin(angle),matrix=[c,s*w/h,-s*h/w,c,(1-c)/2+s*h/w/2,(1-c)/2-s*w/h/2];
        const projected=truth.regions[source.id].map(r=>{const [x,y,rw,rh]=r.bbox,points=[[x,y],[x+rw,y],[x,y+rh],[x+rw,y+rh]].map(([x,y])=>[matrix[0]*x+matrix[2]*y+matrix[4],matrix[1]*x+matrix[3]*y+matrix[5]]),xs=points.map(p=>p[0]),ys=points.map(p=>p[1]);return {...r,bbox:[Math.min(...xs),Math.min(...ys),Math.max(...xs)-Math.min(...xs),Math.max(...ys)-Math.min(...ys)] as Box};});
        await writeFile(join(out,kind+'-native.json'),JSON.stringify(result,null,2));variants.push({id:source.id,kind,pdf_sha256:byteHash(pdf),raster_sha256:byteHash(raster),raster_pixels:[w,h],embedded_dpi:[w/page.width*72,h/page.height*72],helper_pixels:[result.width,result.height],ingestion:'Image-only PDF at original physical page size, through actual product PDFKit300DPI/cap rendering; low-resolution input is deliberately resampled by that path',normalized_forward_affine:matrix,occlusion:mask,regions:regionResult(result,projected,mask)});
      }
    }
  }else{
    validateRenderPackage(bytes);const pages=extractPptx(bytes,'sha256:'+source.sha256);assert.equal(pages.length,source.expected_pages);
    for(const [i,page]of pages.entries()){const expected=source.expected_nonempty_table_cells![i],actual=page.elements.filter(e=>e.method==='ooxml_table_cell').map(e=>({row:e.table!.row,column:e.table!.column,text:e.text,row_span:e.table!.row_span??1,column_span:e.table!.column_span??1}));assert.deepEqual(actual,expected,'Independent XML table-cell coordinates/text/spans');}
    const preview=await preparePptxPreview(path,bytes,pages,cache);assert.ok(preview);await writeFile(join(out,'preview.pdf'),preview);await writeFile(join(out,'page-1.png'),await renderPdf(preview,1,1440));await writeFile(join(out,'pages.json'),JSON.stringify(pages,null,2));results.push({id:source.id,source_sha256:source.sha256,pages:pages.length,table_cells:pages.map(p=>p.elements.filter(e=>e.method==='ooxml_table_cell').length),warnings:[...new Set(pages.flatMap(p=>p.preview?.warnings??[]))],seconds:(Date.now()-start)/1000,truth:'Pinned OOXML source structure; LibreOffice preview is under test, not a PowerPoint ground truth'});
  }
  const row=results.at(-1);console.log(JSON.stringify({id:source.id,pages:row.pages,selected_regions_found:row.regions?.filter((r:any)=>r.normalized_found).length,selected_regions:row.regions?.length,native_tables:row.native_tables,raster_grid_tables:row.raster_grid_tables,seconds:row.seconds}));
}
// Positive and negative controls exercise the tracker, not just the OCR observer.
const service=new DesktopService(join(run,'control-library'));
let controls:any;
try{
  const source=manifest.sources.find(s=>s.id==='python-pptx-txt-text')!,original=(await bytesFor(source)).bytes,zip=unzipSync(original),part='ppt/slides/slide1.xml',xml=new TextDecoder().decode(zip[part]),needle=' Foo Bar ';assert.ok(xml.includes(needle));const paths:string[]=[];
  for(const [name,value]of [['before',needle],['replacement',' Foo Bat '],['insertion',' Foo Bar Inserted '],['text-removal',' ']]){const file=join(run,'control-'+name+'.pptx');await writeFile(file,zipSync({...zip,[part]:strToU8(xml.replace(needle,value))}));paths.push(file);}
  const project=await service.create('Public source positive edit controls',paths.map((file,i)=>({label:String(i),files:[file]}))),report=(await service.run(project.project_id)).report;
  assert.ok(report.changes.some(c=>c.kind==='text_modified'&&c.before?.includes('Foo Bar')&&c.after?.includes('Foo Bat')));assert.ok(report.changes.some(c=>c.kind==='text_modified'&&c.after?.includes('Inserted')));assert.ok(report.changes.some(c=>c.kind==='text_modified'&&c.before?.includes('Inserted')&&!c.after?.includes('Inserted')));
  const before=join(run,'azure-invoice','flattened.pdf'),hidden=join(run,'azure-invoice','occluded.pdf'),uncertain=await service.create('Downloaded scan occlusion is not a deletion',[{label:'original raster',files:[before]},{label:'covered raster',files:[hidden]}]),gap=(await service.run(uncertain.project_id)).report;
  assert.ok(!gap.changes.some(c=>/deleted|removed/.test(c.kind)));assert.ok(gap.changes.some(c=>c.kind==='coverage_gap'),'Withheld comparison must be visible');
  controls={source_report_id:report.report_id,source_text_events:report.changes.filter(c=>c.kind==='text_modified').length,source_control_scope:'Text replacement/insertion/removal within a surviving OOXML text element, not whole-element deletion',occlusion_report_id:gap.report_id,occlusion_gap_events:gap.changes.filter(c=>c.kind==='coverage_gap').length,status:'PASS known source text replacement/insertion/removal and raster-occlusion negative control'};
}finally{service.close();}
const output={head,source_clean:sourceClean,working_patch_sha256:patchSha,untracked_sources:untracked,dirty_source_sha256:dirtySha,engine:ENGINE_VERSION,environment:await visionInfo(),source_manifest_sha256:byteHash(await readFile('docs/fixtures/public-corpus.json')),selected_truth_sha256:byteHash(await readFile('docs/fixtures/public-corpus-truth.json')),sources:results,variants,controls,scope:'Parse/structure/control gates passed; OCR selected-region misses retained. No universal accuracy, absence proof, security proof or strict PowerPoint pixel-equivalence claim. W3C prior OCR excluded from truth.'};
await writeFile(join(run,'result.json'),JSON.stringify(output,null,2));await writeFile(join(folder,'latest.json'),JSON.stringify({run,result:join(run,'result.json')},null,2));console.log(JSON.stringify({run,sources:results.length,source_pages:results.reduce((n,r)=>n+r.pages,0),variant_pages:variants.length,controls}));
