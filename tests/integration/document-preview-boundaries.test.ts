import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,mkdir,open,readFile,rm,symlink,writeFile} from 'node:fs/promises';
import {existsSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {spawnSync} from 'node:child_process';
import PDFDocument from 'pdfkit';
import {convertPptxDetailed} from '../../packages/render/index.js';
import {officeExecutable} from '../../packages/runtime/tools.js';
import {MAX_INPUT_BYTES,byteHash} from '../../packages/schema/index.js';
import {makePptx} from '../../scripts/generate-fixtures.js';

function fifo(path:string){const result=spawnSync('/usr/bin/mkfifo',[path],{encoding:'utf8',timeout:2000});assert.ifError(result.error);assert.equal(result.status,0,result.stderr);}
function preview(path:string,out:string,timeout=6000){
  const result=spawnSync(process.execPath,['--import','tsx',resolve('apps/cli/main.ts'),'preview','--file',path,'--out',out],{encoding:'utf8',timeout,killSignal:'SIGKILL'});
  assert.ifError(result.error);return result;
}
async function sparse(path:string){const handle=await open(path,'w');try{await handle.truncate(MAX_INPUT_BYTES+1);}finally{await handle.close();}}
async function pdfBytes(){
  const doc=new PDFDocument({size:[300,200]}),chunks:Buffer[]=[];doc.on('data',chunk=>chunks.push(chunk));
  const completed=new Promise<Buffer>((resolve,reject)=>{doc.on('end',()=>resolve(Buffer.concat(chunks)));doc.on('error',reject);});
  doc.fontSize(18).text('Regular preview source',30,40);doc.end();return completed;
}
function png(bytes:Buffer){assert.deepEqual(bytes.subarray(0,8),Buffer.from([137,80,78,71,13,10,26,10]));assert.ok(bytes.length>100);}

test('actual CLI preview rejects FIFO, symlink, directory and oversized PDF/PPTX before rendering',{skip:process.platform==='win32'},async()=>{
  const root=await mkdtemp(join(tmpdir(),'docver-preview-boundaries-'));
  try{
    for(const ext of ['pdf','pptx']){
      const regular=join(root,'source.'+ext);await writeFile(regular,'regular target');
      const pipe=join(root,'pipe.'+ext),link=join(root,'link.'+ext),directory=join(root,'directory.'+ext),large=join(root,'large.'+ext);
      fifo(pipe);await symlink(regular,link);await mkdir(directory);await sparse(large);
      for(const [path,code] of [[pipe,'INPUT_NOT_REGULAR'],[link,'INPUT_NOT_REGULAR'],[directory,'INPUT_NOT_REGULAR'],[large,'FILE_LIMIT']]){
        const out=path+'.png',result=preview(path,out);assert.equal(result.status,1,result.stdout);assert.equal(JSON.parse(result.stderr.trim()).code,code);assert.equal(existsSync(out),false);
      }
      assert.equal((await readFile(regular)).toString(),'regular target');
    }
  }finally{await rm(root,{recursive:true,force:true});}
});

test('actual CLI renders an ordinary PDF to PNG and preserves its source bytes',async()=>{
  const root=await mkdtemp(join(tmpdir(),'docver-preview-pdf-'));
  try{
    const path=join(root,'source.pdf'),out=join(root,'preview.png'),bytes=await pdfBytes();await writeFile(path,bytes);
    const result=preview(path,out);assert.equal(result.status,0,result.stderr);assert.equal(JSON.parse(result.stdout).preview,out);png(await readFile(out));assert.deepEqual(await readFile(path),bytes);
  }finally{await rm(root,{recursive:true,force:true});}
});

test('standalone PPTX converter fallback rejects special and oversized sources and honors cancellation',{skip:process.platform==='win32'},async()=>{
  const root=await mkdtemp(join(tmpdir(),'docver-converter-boundaries-'));
  try{
    const regular=join(root,'source.pptx'),pipe=join(root,'pipe.pptx'),link=join(root,'link.pptx'),directory=join(root,'directory.pptx'),large=join(root,'large.pptx');
    await writeFile(regular,'unchanged source');fifo(pipe);await symlink(regular,link);await mkdir(directory);await sparse(large);
    for(const path of [pipe,link,directory])await assert.rejects(convertPptxDetailed(path,'/usr/bin/true'),{code:'INPUT_NOT_REGULAR'});
    await assert.rejects(convertPptxDetailed(large,'/usr/bin/true'),{code:'FILE_LIMIT'});
    const controller=new AbortController();controller.abort();
    await assert.rejects(convertPptxDetailed(regular,'/usr/bin/true',1000,controller.signal),{name:'AbortError'});
    await assert.rejects(convertPptxDetailed(pipe,'/usr/bin/true',1000,controller.signal,Buffer.from('supplied bytes')),{name:'AbortError'});
    assert.equal((await readFile(regular)).toString(),'unchanged source');
  }finally{await rm(root,{recursive:true,force:true});}
});

test('existing PPTX fixture renders through CLI and explicit source bytes do not reopen a replaced pathname',{skip:!officeExecutable(),timeout:120000},async()=>{
  const root=await mkdtemp(join(tmpdir(),'docver-preview-pptx-'));
  try{
    const bytes=await makePptx([{key:'preview',title:'Preview control',body:'Original document 123'}]),path=join(root,'source.pptx'),out=join(root,'preview.png');await writeFile(path,bytes);
    const result=preview(path,out,60000);assert.equal(result.status,0,result.stderr);png(await readFile(out));assert.equal(byteHash(await readFile(path)),byteHash(bytes));
    const replaced=join(root,'replaced.pptx');await mkdir(replaced);
    const converted=await convertPptxDetailed(replaced,officeExecutable(),60000,undefined,bytes);assert.equal(converted.pdf.subarray(0,5).toString(),'%PDF-');assert.ok(converted.pdf.length>100);
    assert.deepEqual(await readFile(path),bytes);
  }finally{await rm(root,{recursive:true,force:true});}
});
