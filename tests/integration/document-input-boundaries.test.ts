import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp,mkdir,open,readFile,readdir,rename,rm,symlink,writeFile,appendFile } from 'node:fs/promises';
import { writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join,resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import PDFDocument from 'pdfkit';
import { DesktopService,DESKTOP_PROJECTS_TABLE } from '../../packages/desktop/service.js';
import { analyze } from '../../packages/engine/index.js';
import { ingest } from '../../packages/ingest/index.js';
import { Store } from '../../packages/storage/index.js';
import { fileSha256 } from '../../packages/runtime/file-hash.js';
import { readRegularFile,regularFileChunks } from '../../packages/runtime/regular-file.js';
import { byteHash,MAX_INPUT_BYTES } from '../../packages/schema/index.js';

function fifo(path:string){const result=spawnSync('/usr/bin/mkfifo',[path],{encoding:'utf8',timeout:2000});assert.ifError(result.error);assert.equal(result.status,0,result.stderr);}
function bridge(library:string,action:string,args:unknown){
  const result=spawnSync(process.execPath,['--import','tsx',resolve('apps/bridge/main.ts'),'--root',library],{input:JSON.stringify({action,args}),encoding:'utf8',timeout:15000});
  assert.ifError(result.error);const response=JSON.parse(result.stdout);assert.equal(result.status,response.ok?0:1,result.stderr);return response;
}
async function documentBytes(){
  const pdf=new PDFDocument({compress:false}),chunks:Buffer[]=[];
  pdf.on('data',(chunk:Buffer)=>chunks.push(chunk));
  const complete=new Promise<Buffer>((resolve,reject)=>{pdf.on('end',()=>resolve(Buffer.concat([...chunks,Buffer.from('\n% AAAA\n')])));pdf.on('error',reject);});
  pdf.text('Document input boundary control',40,40);pdf.end();return complete;
}

test('actual document bridge rejects FIFO, symlink and directory inputs and still imports a regular control',{skip:process.platform==='win32'},async()=>{
  const root=await mkdtemp(join(tmpdir(),'docver-input-types-')),library=join(root,'library');
  try{
    const pipe=join(root,'pipe.pdf'),directory=join(root,'directory.pptx'),link=join(root,'linked.pdf'),source=join(root,'source.pdf'),bytes=Buffer.from('selected document bytes');
    fifo(pipe);await mkdir(directory);await writeFile(source,bytes);await symlink(source,link);
    for(const path of [pipe,link,directory]){
      const response=bridge(library,'create',{title:'Rejected input',revisions:[{label:'v1',files:[path]}]});
      assert.equal(response.ok,false);assert.equal(response.error.code,'INPUT_NOT_REGULAR');
      await assert.rejects(ingest(path),{code:'INPUT_NOT_REGULAR'});
      await assert.rejects(fileSha256(path),{code:'INPUT_NOT_REGULAR'});
    }
    const service=new DesktopService(library);try{assert.deepEqual(service.projects(),[]);assert.equal(service.store.db.prepare('SELECT COUNT(*) AS count FROM reports').get()?.count,0);assert.deepEqual(await readdir(join(library,'imports')),[]);}finally{service.close();}
    const control=bridge(library,'create',{title:'Regular input',revisions:[{label:'v1',files:[source],expected_sha256:[byteHash(bytes)]}]});
    assert.equal(control.ok,true);assert.equal(control.value.revisions[0].files[0].blob,byteHash(bytes)+'.pdf');
    assert.deepEqual(await readFile(join(library,'imports',control.value.revisions[0].files[0].blob)),bytes);
  }finally{await rm(root,{recursive:true,force:true});}
});

test('regular reader and hashing preserve exact bytes, honor caps, detect growth and cancel between chunks',async()=>{
  const root=await mkdtemp(join(tmpdir(),'docver-input-reader-'));
  try{
    const path=join(root,'bytes.pdf'),bytes=Buffer.from([0,255,13,10,128,42]);await writeFile(path,bytes);
    assert.deepEqual(await readRegularFile(path,{maxBytes:bytes.length}),bytes);assert.equal(await fileSha256(path),byteHash(bytes));
    await assert.rejects(readRegularFile(path,{maxBytes:bytes.length-1}),{code:'FILE_LIMIT'});
    await writeFile(path,Buffer.alloc(0));assert.equal((await readRegularFile(path,{maxBytes:0})).length,0);
    await writeFile(path,'1234');const growing=regularFileChunks(path,{maxBytes:8});assert.equal((await growing.next()).value?.toString(),'1234');await appendFile(path,'56789');await assert.rejects(growing.next(),{code:'FILE_LIMIT'});
    await writeFile(path,'original');const controller=new AbortController(),cancelled=regularFileChunks(path,{signal:controller.signal});assert.equal((await cancelled.next()).value?.toString(),'original');controller.abort();await assert.rejects(cancelled.next(),{name:'AbortError'});
    await assert.rejects(readRegularFile(path,{signal:controller.signal}),{name:'AbortError'});await assert.rejects(fileSha256(path,controller.signal),{name:'AbortError'});await assert.rejects(ingest(path,{signal:controller.signal}),{name:'AbortError'});
  }finally{await rm(root,{recursive:true,force:true});}
});

test('a pathname replacement after opening cannot redirect descriptor reads to a FIFO',{skip:process.platform==='win32'},async()=>{
  const root=await mkdtemp(join(tmpdir(),'docver-input-descriptor-'));
  try{
    const path=join(root,'source.pdf'),bytes=Buffer.alloc(1024*1024+13,42);await writeFile(path,bytes);
    const chunks=regularFileChunks(path),first=await chunks.next();assert.equal(first.done,false);assert.equal(first.value!.length,1024*1024);
    await rename(path,path+'.original');fifo(path);
    const read=[first.value!];for await(const chunk of chunks)read.push(chunk);
    assert.deepEqual(Buffer.concat(read),bytes);
  }finally{await rm(root,{recursive:true,force:true});}
});

test('oversized sparse documents are rejected before reading in desktop create, ingest and hashing',async()=>{
  const root=await mkdtemp(join(tmpdir(),'docver-input-limit-')),service=new DesktopService(join(root,'library'));
  try{
    const path=join(root,'large.pdf'),handle=await open(path,'w');try{await handle.truncate(MAX_INPUT_BYTES+1);}finally{await handle.close();}
    await assert.rejects(fileSha256(path),{code:'FILE_LIMIT'});await assert.rejects(ingest(path),{code:'FILE_LIMIT'});await assert.rejects(service.create('Too large',[{label:'v1',files:[path]}]),{code:'FILE_LIMIT'});
    const controller=new AbortController();controller.abort();await assert.rejects(service.create('Cancelled',[{label:'v1',files:[path]}],controller.signal),{name:'AbortError'});
    assert.deepEqual(service.projects(),[]);assert.deepEqual(await readdir(join(service.root,'imports')),[]);
  }finally{service.close();await rm(root,{recursive:true,force:true});}
});

test('desktop persisted import identity rejects same-size mutation before reading, during ingest and on cache reuse',async()=>{
  const root=await mkdtemp(join(tmpdir(),'docver-input-identity-')),service=new DesktopService(join(root,'library'));
  try{
    const bytes=await documentBytes(),modified=Buffer.from(bytes);modified[modified.length-3]=66;assert.notEqual(byteHash(modified),byteHash(bytes));assert.equal(modified.length,bytes.length);
    const source=join(root,'source.pdf');await writeFile(source,bytes);
    const draft=await service.create('Bound original',[{label:'first',files:[source]},{label:'repeat',files:[source]}]),initial=(await service.run(draft.project_id)).report;
    assert.ok(initial.revisions.every(revision=>revision.status==='success'));assert.ok(initial.revisions.every(revision=>revision.assets[0].asset_id==='sha256:'+byteHash(bytes)));
    const imported=join(service.root,'imports',draft.revisions[0].files[0].blob),draftBefore=service.store.db.prepare(`SELECT body FROM ${DESKTOP_PROJECTS_TABLE} WHERE id=?`).get(draft.project_id)?.body,reportBefore=service.store.db.prepare('SELECT body FROM reports WHERE id=?').get(initial.report_id)?.body;
    const unchanged=()=>{assert.equal(service.store.db.prepare(`SELECT body FROM ${DESKTOP_PROJECTS_TABLE} WHERE id=?`).get(draft.project_id)?.body,draftBefore);assert.equal(service.store.db.prepare('SELECT body FROM reports WHERE id=?').get(initial.report_id)?.body,reportBefore);assert.equal(service.reports(draft.project_id).length,1);assert.equal(service.project(draft.project_id).last_report_id,initial.report_id);};
    await writeFile(imported,modified);const response=bridge(service.root,'analyze',{project_id:draft.project_id});assert.equal(response.ok,false);assert.equal(response.error.code,'SOURCE_CHANGED');unchanged();
    for(const label of ['first','repeat']){
      await writeFile(imported,bytes);let mutated=false;
      await assert.rejects(service.run(draft.project_id,undefined,progress=>{if(progress.phase==='extract'&&progress.label===label){writeFileSync(imported,modified);mutated=true;}}),{code:'SOURCE_CHANGED'});
      assert.equal(mutated,true);unchanged();
    }
    if(process.platform!=='win32'){
      for(const kind of ['symlink','directory','fifo']){
        await rm(imported);if(kind==='symlink')await symlink(source,imported);else if(kind==='directory')await mkdir(imported);else fifo(imported);
        await assert.rejects(service.run(draft.project_id),{code:'SOURCE_CHANGED'});unchanged();
        await rm(imported,{recursive:true,force:true});await writeFile(imported,bytes);
      }
    }
    await writeFile(imported,bytes);const restored=(await service.run(draft.project_id)).report;assert.equal(restored.report_id,initial.report_id);
  }finally{service.close();await rm(root,{recursive:true,force:true});}
});

test('ordinary engine file inputs remain supported and duplicate cached occurrences are revalidated',async()=>{
  const root=await mkdtemp(join(tmpdir(),'docver-input-cli-')),store=new Store(join(root,'store'));
  try{
    const bytes=await documentBytes(),changed=Buffer.from(bytes);changed[changed.length-3]=66;
    const first=join(root,'first.pdf'),second=join(root,'second.pdf');await writeFile(first,bytes);await writeFile(second,bytes);
    const input={project_id:'project_regular_inputs',title:'Regular CLI input',mapping_decisions:[],revisions:[{label:'first',files:[first]},{label:'second',files:[second]}]};
    const initial=(await analyze(input,root,store,undefined,undefined,{ocr:'off',pptxPreview:false})).report;assert.ok(initial.revisions.every(revision=>revision.status==='success'));
    const controller=new AbortController();await assert.rejects(analyze(input,root,store,controller.signal,progress=>{if(progress.phase==='extract'&&progress.label==='second')controller.abort();},{ocr:'off',pptxPreview:false}),{name:'AbortError'});
    await assert.rejects(analyze(input,root,store,undefined,progress=>{if(progress.phase==='extract'&&progress.label==='second')writeFileSync(second,changed);},{ocr:'off',pptxPreview:false}),{code:'SOURCE_CHANGED'});
    assert.equal(store.reports(input.project_id).length,1);
  }finally{store.close();await rm(root,{recursive:true,force:true});}
});
