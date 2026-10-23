import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,rm,writeFile,readFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {spawnSync} from 'node:child_process';
import PDFDocument from 'pdfkit';
import {DesktopService} from '../../packages/desktop/service.js';
import {pagePreview} from '../../packages/desktop/preview.js';
import {makePptx} from '../../scripts/generate-fixtures.js';

async function pdfBytes(){
  const pdf=new PDFDocument({size:[720,405]}),chunks:Buffer[]=[];
  const done=new Promise<Buffer>((ok,fail)=>{pdf.on('data',(b:Buffer)=>chunks.push(b));pdf.on('end',()=>ok(Buffer.concat(chunks)));pdf.on('error',fail);});
  pdf.fontSize(24).text('Revenue 120',40,40);pdf.end();return done;
}
test('native page preview binds a verified source to fixed report/page and preserves report bytes',async()=>{
  const root=await mkdtemp(join(tmpdir(),'reviset-native-preview-')),library=join(root,'library'),service=new DesktopService(library);
  try{
    const file=join(root,'source.pdf');await writeFile(file,await pdfBytes());
    const draft=await service.create('Preview control',[{label:'v1',files:[file]}]),run=await service.run(draft.project_id),report=run.report,page=report.revisions[0].pages[0];
    assert.equal(report.revisions[0].status,'success',JSON.stringify(report.revisions[0].errors));assert.ok(page,'A successful PDF import must produce a page');
    const before=JSON.stringify(service.snapshot(draft.project_id,report.report_id));
    const args={project_id:draft.project_id,report_id:report.report_id,page_id:page.page_id,max_width:640};
    const result=await pagePreview(service,library,args);
    assert.equal(result.source,'original_pdf');assert.equal(result.text,page.text);
    assert.ok('png_base64' in result);const image=Buffer.from(result.png_base64!,'base64');assert.equal(image.subarray(1,4).toString(),'PNG');assert.equal(result.width,640);assert.ok(result.height>0);
    assert.equal(JSON.stringify(service.snapshot(draft.project_id,report.report_id)),before);
    await assert.rejects(pagePreview(service,library,{...args,page_id:'pg_foreign'}));
    await assert.rejects(pagePreview(service,library,{...args,project_id:'prj_foreign'}));
    const bridge=(extra:unknown)=>spawnSync(process.execPath,['--import','tsx',resolve('apps/bridge/main.ts'),'--root',library],{input:JSON.stringify({action:'pagePreview',args:extra}),encoding:'utf8',timeout:20_000});
    for(const invalid of [{...args,report_id:'latest'},{...args,max_width:1},{...args,path:file}]){
      const response=bridge(invalid);assert.equal(response.status,1);assert.equal(JSON.parse(response.stdout).ok,false);
    }
    const asset=join(library,'assets',page.asset_id.slice(7)),original=await readFile(asset);await writeFile(asset,Buffer.alloc(original.length,0));
    await assert.rejects(pagePreview(service,library,args),{code:'ASSET_CORRUPT'});
  }finally{service.close();await rm(root,{recursive:true,force:true});}
});

test('PPTX preview without renderer returns explicit structure provenance',async()=>{
  const root=await mkdtemp(join(tmpdir(),'reviset-native-structure-')),library=join(root,'library'),service=new DesktopService(library);
  try{
    const path=join(root,'source.pptx');await writeFile(path,await makePptx([{key:'control',title:'Original source',body:'Revenue 110'}]));
    const draft=await service.create('Structure control',[{label:'v1',files:[path]}]);
    // Build the stored observation without a renderer, as on Windows.
    const {analyze}=await import('../../packages/engine/index.js');
    const run=await analyze(service.manifest(draft.project_id),service.root,service.store,undefined,undefined,{ocr:'off',pptxPreview:false});
    const page=run.report.revisions[0].pages[0],result=await pagePreview(service,library,{project_id:draft.project_id,report_id:run.report.report_id,page_id:page.page_id,max_width:640});
    assert.equal(result.source,'pptx_structure');assert.ok('unavailable_reason' in result&&result.unavailable_reason);assert.equal('png_base64' in result,false);assert.match(result.text,/Revenue 110/);
  }finally{service.close();await rm(root,{recursive:true,force:true});}
});
