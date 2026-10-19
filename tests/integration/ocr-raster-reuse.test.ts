import {test} from 'node:test';
import {execFileSync} from 'node:child_process';
import {mkdtemp,mkdir,writeFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import assert from 'node:assert/strict';
import PDFDocument from 'pdfkit';
import {captureNativePages} from '../../packages/ingest/ocr.js';
import {visionExecutable} from '../../packages/runtime/tools.js';

// Exercise the actual subprocess, schema, cache and cancellation path without
// OCR nondeterminism. Pages1/2/4 share pixels; page3 has the same hash but a
// different pixel width, so it must never join that observation group.
async function fixture(body:string){
  const folder=await mkdtemp(join(tmpdir(),'docver-raster-reuse-'));
  try{
    const helper=join(folder,'vision.mjs'),log=join(folder,'calls.jsonl');
    const line={text:'Revenue 100',confidence:1,bbox:[.1,.2,.3,.05],strike_candidate:false,strike_status:'not_detected',strike_bbox:[0,0,0,0],numeric_consensus:true,numeric_status:'available',numeric_readings:['100'],numeric_observations:[{text:'100',bbox:[.25,.2,.1,.05],sources:['primary','tile']}],tokens:[{text:'Revenue',bbox:[.1,.2,.1,.05]},{text:'100',bbox:[.25,.2,.1,.05]}],alternatives:[],reconsideration:{status:'unsupported_background',band_bbox:[.1,.2,.3,.05],contexts:[]}};
    const base={version:'reuse-fixture',revision:3,languages:['ko-KR','en-US'],language_correction:false,renderer:'fixture',verification:'fixture',viewport_width:960,viewport_height:540,rotation:0,width:960,height:540,render_sha256:'a'.repeat(64),lines:[line],structure_status:'available',tables:[{cells:[{row:0,column:0,row_span:1,column_span:1,text:'100',bbox:[.1,.2,.3,.05]}]}],grid_status:'not_detected'};
    await writeFile(helper,`#!${process.execPath}
import {appendFileSync} from 'node:fs';
if(process.argv.includes('--info'))console.log(JSON.stringify({version:'fixture',os:'fixture',revision:3,languages:['ko-KR','en-US'],language_correction:false,font_inventory_sha256:'a'.repeat(64),font_families:[]}));
else{
 let input='';for await(const chunk of process.stdin)input+=chunk;const q=JSON.parse(input),mode=process.env.DOCVER_REUSE_MODE??'normal';
 appendFileSync(process.env.DOCVER_REUSE_LOG,JSON.stringify({...q,mode})+'\\n');
 const pages=q.pages.map(page=>{
  const ocr=q.ocr_pages.includes(page),value={...${JSON.stringify(base)},ocr_performed:ocr,viewport_width:960+page,viewport_height:540+page,rotation:page*90,width:page===3?961:960,render_sha256:page===5?'b'.repeat(64):'a'.repeat(64)};
  if(!ocr){value.lines=[];delete value.tables;value.structure_status='not_requested';}
  if(page===1&&ocr){
   if(mode==='error')return {page,error:'representative failed'};
   if(mode==='schema')value.width=0;
   if(mode==='mode')value.ocr_performed=false;
   if(mode==='hash')value.render_sha256='c'.repeat(64);
   if(mode==='dimensions')value.width=962;
  }
  if(page===1&&!ocr&&mode==='render_error')return {page,error:'render failed'};
  return {page,result:value};
 });console.log(JSON.stringify({pages}));
}`,{mode:0o755});
    const script=`import assert from 'node:assert/strict';
import {mkdir,readFile,rm} from 'node:fs/promises';import {join} from 'node:path';
import {captureNativePages,ocrEnvironment} from ${JSON.stringify(new URL('../../packages/ingest/ocr.ts',import.meta.url).href)};
import {hash,byteHash} from ${JSON.stringify(new URL('../../packages/schema/index.ts',import.meta.url).href)};
const folder=${JSON.stringify(folder)},log=${JSON.stringify(log)},bytes=new Uint8Array([1,2,3]),pages=[1,2,3,4,5];
const calls=async()=>{try{return (await readFile(log,'utf8')).trim().split('\\n').filter(Boolean).map(x=>JSON.parse(x));}catch{return [];}};
const cache=async(name)=>{const root=join(folder,name);await mkdir(join(root,'ocr','raster'),{recursive:true});return root;};
${body}`;
    execFileSync(process.execPath,['--import','tsx','--input-type=module','-e',script],{encoding:'utf8',env:{...process.env,DOCVER_VISION:helper,DOCVER_REUSE_LOG:log},timeout:30000});
  }finally{await rm(folder,{recursive:true,force:true});}
}

test('within-call raster reuse preserves numeric/table/ROI observations, own geometry and independent arrays',()=>fixture(`
const cacheRoot=await cache('grouped'),progress=[];
const result=await captureNativePages(bytes,pages,pages,{cacheRoot,onPage:(n,total)=>progress.push([n,total])});
assert.equal(result.failures.size,0);assert.equal(result.size,5);
assert.deepEqual((await calls()).map(c=>c.ocr_pages),[[],[1,3,5]]);
assert.deepEqual(progress,[[3,5],[5,5]]);
for(const page of pages){const r=result.get(page);assert.equal(r.viewport_width,960+page);assert.equal(r.viewport_height,540+page);assert.equal(r.rotation,page*90);assert.equal(r.lines[0].text,'Revenue 100');assert.deepEqual(r.lines[0].numeric_readings,['100']);assert.equal(r.tables[0].cells[0].text,'100');assert.equal(r.lines[0].reconsideration.status,'unsupported_background');}
assert.equal(result.get(3).width,961);result.get(1).lines[0].tokens[0].text='mutated';result.get(1).tables[0].cells[0].text='mutated';
assert.equal(result.get(2).lines[0].tokens[0].text,'Revenue');assert.equal(result.get(4).tables[0].cells[0].text,'100');
const before=(await calls()).length,cached=await captureNativePages(bytes,pages,pages,{cacheRoot});assert.equal((await calls()).length,before);assert.equal(cached.get(1).lines[0].tokens[0].text,'Revenue');
// A new source uses verified disk observations but keeps its own geometry.
const disk=await captureNativePages(new Uint8Array([4,5,6]),pages,pages,{cacheRoot});assert.equal((await calls()).length,before+1);assert.equal((await calls()).at(-1).ocr_pages.length,0);assert.equal(disk.get(3).width,961);assert.equal(disk.get(4).rotation,360);
`));

test('failed or mismatched representatives fall back per page without poisoning duplicate peers',()=>fixture(`
for(const mode of ['error','schema','mode','hash','dimensions','render_error']){
 process.env.DOCVER_REUSE_MODE=mode;const cacheRoot=await cache(mode),progress=[];
 const r=await captureNativePages(bytes,pages,pages,{cacheRoot,onPage:(n,total)=>progress.push([n,total])});
 const q=(await calls()).filter(c=>c.mode===mode);
 if(mode==='render_error')assert.deepEqual(q.map(c=>c.ocr_pages),[[],[1,2,3,5]]);
 else assert.deepEqual(q.map(c=>c.ocr_pages),[[],[1,3,5],[2,4]]);
 for(const page of [2,4]){assert.equal(r.get(page).render_sha256,'a'.repeat(64));assert.equal(r.get(page).width,960);assert.equal(r.get(page).lines[0].text,'Revenue 100');assert.equal(r.failures.has(page),false);}
 assert.equal(r.failures.get(1),mode==='error'?'NATIVE_PAGE_HELPER_ERROR':mode==='schema'?'NATIVE_RESULT_SCHEMA_INVALID':mode==='mode'?'NATIVE_OCR_MODE_MISMATCH':undefined);
 assert.equal(progress.at(-1)[0],5);assert.ok(progress.every(([n,t],i)=>t===5&&(!i||n>=progress[i-1][0])));
}
`));

test('raster reuse keeps cache-write diagnostics local and never persists operational warnings',()=>fixture(`
const cacheRoot=await cache('warning'),environment=await ocrEnvironment();
const path=(page,ocr)=>join(cacheRoot,'ocr',hash([byteHash(bytes),page,environment,ocr,'pdfkit-300dpi-4096-tiled-v4'])+'.json');
await mkdir(path(1,true));await mkdir(path(2,false));await mkdir(path(3,false));
const r=await captureNativePages(bytes,pages,pages,{cacheRoot});
assert.equal(r.get(1).cache_write_failed,true);assert.equal(r.get(2).cache_write_failed,true);
assert.equal(r.get(3).cache_write_failed,true,'An independently observed representative retains its own render-stage diagnostic');
assert.equal(r.get(4).cache_write_failed,undefined);assert.equal(r.get(4).lines[0].text,'Revenue 100');
const replay=await captureNativePages(bytes,[2,4],[2,4],{cacheRoot});for(const v of replay.values())assert.equal(v.cache_write_failed,undefined);
`));

test('cold caches and explicit no-reuse retain normal batching without an extra render pass',()=>fixture(`
for(const [name,options]of [['cold',{cacheRoot:join(folder,'cold')}],['disabled',{cacheRoot:await cache('disabled'),reuseRasterOcr:false}],['none',{}]]){
 const before=(await calls()).length,r=await captureNativePages(bytes,pages,pages,options),added=(await calls()).slice(before);
 assert.equal(r.size,5);assert.equal(added.length,1);assert.deepEqual(added[0].ocr_pages,pages);
}
`));

test('cancellation after representative observation rejects before duplicate cache publication',()=>fixture(`
const cacheRoot=await cache('cancel'),controller=new AbortController();
await assert.rejects(()=>captureNativePages(bytes,pages,pages,{cacheRoot,signal:controller.signal,onPage:()=>controller.abort()}),e=>e.name==='AbortError'||e.code==='CANCELLED');
assert.deepEqual((await calls()).map(c=>c.ocr_pages),[[],[1,3,5]]);
const environment=await ocrEnvironment(),key=hash([byteHash(bytes),2,environment,true,'pdfkit-300dpi-4096-tiled-v4']);
await assert.rejects(()=>readFile(join(cacheRoot,'ocr',key+'.json')),e=>e.code==='ENOENT');
`));

test('actual native identical-image reuse preserves primary numeric observations and different images',{
  skip:process.platform!=='darwin'||!visionExecutable(),
},async()=>{
  const folder=await mkdtemp(join(tmpdir(),'docver-native-reuse-'));
  try{
    const pdf=new PDFDocument({size:[480,270],margin:0}),chunks:Buffer[]=[];
    const complete=new Promise<Buffer>((resolve,reject)=>{pdf.on('data',chunk=>chunks.push(chunk));pdf.on('end',()=>resolve(Buffer.concat(chunks)));pdf.on('error',reject);});
    for(const [index,value]of [100,100,120].entries()){if(index)pdf.addPage();pdf.font('Helvetica').fontSize(28).text('Revenue '+value,50,70,{lineBreak:false});}pdf.end();
    const bytes=await complete,pages=[1,2,3],cacheRoot=join(folder,'cache');await mkdir(join(cacheRoot,'ocr','raster'),{recursive:true});
    const independent=await captureNativePages(bytes,pages,pages,{reuseRasterOcr:false}),reused=await captureNativePages(bytes,pages,pages,{cacheRoot});
    assert.equal(independent.failures.size,0);assert.equal(reused.failures.size,0);assert.equal(reused.size,3);
    assert.equal(reused.get(1)!.render_sha256,reused.get(2)!.render_sha256);assert.notEqual(reused.get(1)!.render_sha256,reused.get(3)!.render_sha256);
    // Optional contextual/structure availability may depend on time budgets.
    // Primary, numeric, strike, tokens and raster observations must be identical.
    for(const page of pages){const primary=(result:NonNullable<ReturnType<typeof reused.get>>)=>({...result,structure_status:undefined,structure_engine:undefined,tables:undefined,lines:result.lines.map(({reconsideration,...line})=>line)});
      assert.deepEqual(primary(reused.get(page)!),primary(independent.get(page)!));
      assert.ok(reused.get(page)!.lines.some(line=>line.text.includes(page===3?'120':'100')));
    }
    reused.get(1)!.lines[0].numeric_readings.push('mutation');assert.ok(!reused.get(2)!.lines[0].numeric_readings.includes('mutation'));
  }finally{await rm(folder,{recursive:true,force:true});}
});
