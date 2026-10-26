import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,writeFile,rm} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {spawnSync} from 'node:child_process';
import {zipSync,unzipSync,strToU8} from 'fflate';
import {makePptx} from '../../scripts/generate-fixtures.js';
import PDFDocument from 'pdfkit';
import {DesktopService} from '../../packages/desktop/service.js';
import {analyze} from '../../packages/engine/index.js';
import {canonical,hash} from '../../packages/schema/index.js';
import {Store} from '../../packages/storage/index.js';
import {nativeWarningReasons} from '../../packages/desktop/warning-summary.js';

// This reference contains only ASCII. PDFKit's standard font avoids a host
// Korean-font dependency in the Windows portability gate.
async function referencePdf():Promise<Buffer>{
  const document=new PDFDocument({size:[720,405],margin:40}),chunks:Buffer[]=[];
  const done=new Promise<Buffer>((ok,fail)=>{document.on('data',(chunk:Buffer)=>chunks.push(chunk));document.on('end',()=>ok(Buffer.concat(chunks)));document.on('error',fail);});
  document.font('Helvetica').fontSize(24).text('Reference only',40,40).fontSize(14).text('Independent supplied PDF',40,90);document.end();return done;
}

test('real native outlines omit repeated revision evidence and bundle warnings preserve every distinct reason and late reused-PDF caution',async t=>{
  const root=await mkdtemp(join(tmpdir(),'reviset-native-projection-')),library=join(root,'library'),service=new DesktopService(library);
  try{
    const reference=join(root,'reference.pdf');await writeFile(reference,await referencePdf());
    const inputs=[];
    for(let version=0;version<2;version++){
      const parts=unzipSync(await makePptx([{key:'source',title:'Source',body:'Synthetic source'}]));
      parts['ppt/slides/slide1.xml']=strToU8('<p:sld xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"><p:cSld><p:spTree>'+Array.from({length:1000},(_,i)=>'<p:sp><p:nvSpPr><p:cNvPr id="'+(i+1)+'" name="v'+version+'"/></p:nvSpPr></p:sp>').join('')+'</p:spTree></p:cSld></p:sld>');
      const file=join(root,'source-'+version+'.pptx');await writeFile(file,zipSync(parts));inputs.push({label:'v'+version,files:[file,reference]});
    }
    const draft=await service.create('Repeated warning projection',inputs),manifest=service.manifest(draft.project_id),run=await analyze(manifest,root,service.store,undefined,undefined,{persist:false,pptxPreview:false,ocr:'off'});
    service.commit(draft.project_id,{...run,draft_hash:hash(manifest)});
    const report=service.snapshot(draft.project_id,run.report.report_id),before=canonical(report),base={project_id:draft.project_id,report_id:report.report_id};
    const bridge=(action:string,args:Record<string,unknown>)=>{
      const result=spawnSync(process.execPath,['--import','tsx',resolve('apps/bridge/main.ts'),'--root',library],{input:JSON.stringify({action,args}),encoding:'utf8',timeout:20000,maxBuffer:8*1024*1024});
      assert.ifError(result.error);assert.equal(result.status,0,result.stderr);const reply=JSON.parse(result.stdout);assert.equal(reply.ok,true,JSON.stringify(reply.error));return reply.value;
    };
    const view=bridge('view',base);assert.equal(view.report_id,report.report_id);
    assert.deepEqual(view.lineages,report.lineages);assert.deepEqual(view.mapping_relations,report.mapping_relations);
    assert.ok(Buffer.byteLength(JSON.stringify(view))<256*1024,'Outline payload must not scale with every repeated revision gap');
    for(const [index,revision]of report.revisions.entries()){
      assert.ok(revision.coverage_gaps.length>1000,'Real extraction must retain repeated source warnings');
      assert.equal(view.revisions[index].coverage_gaps,undefined);assert.equal(view.revisions[index].coverage_gap_count,revision.coverage_gaps.length);
      assert.ok(view.revisions[index].pages.every((p:any)=>!('elements'in p)&&!('visibility_spans'in p)));
      const bundle=bridge('bundle',{...base,revision_occurrence_id:revision.revision_occurrence_id});
      const reasons=(gaps:{feature:string;reason:string}[])=>[...new Set(gaps.map(g=>JSON.stringify([g.feature,g.reason])))].sort();
      assert.deepEqual(reasons(bundle.revision.coverage_gaps),reasons(revision.coverage_gaps));
      assert.equal(bundle.revision.coverage_gap_count,revision.coverage_gaps.length);
      const lateWarnings=[...revision.coverage_gaps.filter(g=>g.reason!=='reference_pdf_reused_for_different_pptx'),...revision.coverage_gaps.filter(g=>g.reason==='reference_pdf_reused_for_different_pptx')];
      assert.ok(lateWarnings.findIndex(g=>g.reason==='reference_pdf_reused_for_different_pptx')>3,'Boundary control must place the actual mandatory caution after a naive first-N slice');
      assert.ok(nativeWarningReasons(lateWarnings).some(g=>g.reason==='reference_pdf_reused_for_different_pptx'),'Warning projection must retain a mandatory reason regardless of its original position');
      assert.ok(bundle.revision.coverage_gaps.some((g:any)=>g.reason==='reference_pdf_reused_for_different_pptx'));
      for(const [pageIndex,page]of revision.pages.entries()){
        assert.deepEqual(reasons(bundle.revision.pages[pageIndex].coverage_gaps),reasons(page.coverage_gaps));
        assert.equal(bundle.revision.pages[pageIndex].coverage_gap_count,page.coverage_gaps.length);
      }
      assert.ok(Buffer.byteLength(JSON.stringify(bundle))<64*1024,'Complete distinct warning captions must not repeat per-shape evidence IDs');
    }
    const reopened=new Store(library,true);try{assert.equal(canonical(reopened.report(draft.project_id,report.report_id)),before,'Native metadata reads never rewrite canonical gaps or source observations');}finally{reopened.close();}
    const q=service.queryService(draft.project_id);let cursor:string|undefined,found=false,count=0;const recovered=new Set<number>();
    do{const page=q.query('list_coverage_gaps',{...base,revision_id:report.revisions[0].revision_occurrence_id,limit:100,max_output_tokens:8000,...(cursor?{cursor}:{})});for(const gap of page.items){assert.equal(gap.text,report.revisions[0].coverage_gaps[Number(gap.gap_index)].reason);recovered.add(Number(gap.gap_index));found ||=gap.text==='reference_pdf_reused_for_different_pptx';}count+=page.items.length;cursor=page.next_cursor??undefined;assert.ok(count<5000);}while(cursor);
    assert.ok(found&&recovered.size===report.revisions[0].coverage_gaps.length,'Bounded MCP must still recover the unabridged revision evidence');
    t.diagnostic(JSON.stringify({revisionGaps:report.revisions.map(r=>r.coverage_gaps.length),outlineBytes:Buffer.byteLength(JSON.stringify(view)),fullEvidenceRetained:true}));
  }finally{service.close();await rm(root,{recursive:true,force:true});}
});
