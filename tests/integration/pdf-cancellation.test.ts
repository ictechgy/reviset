import {test} from 'node:test';
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {mkdtemp,writeFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import PDFDocument from 'pdfkit';
import {extractPdf} from '../../packages/ingest/pdf.js';
import {Page} from '../../packages/schema/index.js';

async function fixturePdf(count:number){
  const pdf=new PDFDocument({size:[480,270],margin:0}),chunks:Buffer[]=[];
  const done=new Promise<Buffer>((resolve,reject)=>{pdf.on('data',chunk=>chunks.push(chunk));pdf.on('end',()=>resolve(Buffer.concat(chunks)));pdf.on('error',reject);});
  for(let index=0;index<count;index++){if(index)pdf.addPage();pdf.font('Helvetica').fontSize(24).text('Cancellation fixture '+index,40,60,{lineBreak:false});}pdf.end();return done;
}

test('default abort during native observation rejects as cancellation before another batch starts',async()=>{
  const folder=await mkdtemp(join(tmpdir(),'reviset-pdf-cancel-'));
  try{
    const helper=join(folder,'vision.mjs'),source=join(folder,'fixture.pdf'),log=join(folder,'calls.jsonl');await writeFile(source,await fixturePdf(17));
    await writeFile(helper,`#!${process.execPath}
import {appendFileSync} from 'node:fs';
if(process.argv.includes('--info'))console.log(JSON.stringify({version:'cancel-fixture',os:'fixture',revision:3,languages:['ko-KR','en-US'],language_correction:false,font_inventory_sha256:'a'.repeat(64),font_families:[]}));
else{
 let input='';for await(const part of process.stdin)input+=part;const request=JSON.parse(input);appendFileSync(process.env.REVISET_CANCEL_LOG,JSON.stringify(request.pages)+'\\n');
 console.log(JSON.stringify({pages:request.pages.map(page=>({page,result:{version:'cancel-fixture',revision:3,languages:['ko-KR','en-US'],language_correction:false,ocr_performed:request.ocr_pages.includes(page),renderer:'fixture',verification:'fixture',viewport_width:480,viewport_height:270,rotation:0,width:480,height:270,render_sha256:'a'.repeat(64),lines:[]}}))}));
}`,{mode:0o755});
    const script=`import assert from 'node:assert/strict';import {readFile} from 'node:fs/promises';
import {extractPdf} from ${JSON.stringify(new URL('../../packages/ingest/pdf.ts',import.meta.url).href)};
import {visionExecutable} from ${JSON.stringify(new URL('../../packages/runtime/tools.ts',import.meta.url).href)};
assert.equal(visionExecutable(),${JSON.stringify(helper)},'This control must use its protocol fixture, not native OCR');
const controller=new AbortController(),progress=[],bytes=new Uint8Array(await readFile(${JSON.stringify(source)}));
await assert.rejects(()=>extractPdf(bytes,'sha256:cancellation',{ocr:'all',signal:controller.signal,onPage:(current,total)=>{progress.push([current,total]);controller.abort();}}),{code:'CANCELLED'});
assert.equal(controller.signal.reason.name,'AbortError');assert.deepEqual(progress,[[16,17]]);assert.deepEqual((await readFile(${JSON.stringify(log)},'utf8')).trim().split('\\n').map(line=>JSON.parse(line)),[Array.from({length:16},(_,i)=>i+1)]);`;
    // The body is generated test code; no document text is evaluated as code.
    execFileSync(process.execPath,['--import','tsx','--input-type=module','-e',script],{encoding:'utf8',env:{...process.env,DOCVER_VISION:helper,REVISET_CANCEL_LOG:log},timeout:30000});
  }finally{await rm(folder,{recursive:true,force:true});}
});

test('default abort between canonical page validations retains CANCELLED classification',async t=>{
  const bytes=await fixturePdf(2),controller=new AbortController(),parse=Page.safeParse.bind(Page);let validated=0;
  // Abort precisely after the first real canonical validation. This avoids a
  // timing-dependent test of the synchronous validation loop.
  t.mock.method(Page,'safeParse',(value:unknown)=>{const result=parse(value);assert.equal(result.success,true);validated++;controller.abort();return result;});
  await assert.rejects(()=>extractPdf(bytes,'sha256:validation-cancellation',{ocr:'off',signal:controller.signal}),{code:'CANCELLED'});
  assert.equal(controller.signal.reason.name,'AbortError');assert.equal(validated,1);
});

test('ordinary invalid PDF input still reports INVALID_PDF without cancellation',async()=>{
  await assert.rejects(()=>extractPdf(new Uint8Array([1,2,3]),'sha256:invalid',{ocr:'off'}),{code:'INVALID_PDF'});
});
