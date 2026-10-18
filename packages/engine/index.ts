import { resolve, dirname, join } from 'node:path';
import { readFileSync, existsSync } from 'node:fs';
import { readFile, stat } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { MAX_INPUT_BYTES,Manifest, Report, SCHEMA_VERSION, SCHEMA_HASH, ENGINE_VERSION, id, byteHash, DocverError, type InputManifest, type RevisionData, type ReportData } from '../schema/index.js';
import { ingest, type Extracted } from '../ingest/index.js';
import { matchPages, similarity } from '../matching/index.js';
import { diffRevisions } from '../diff/index.js';
import { Store } from '../storage/index.js';
import { ocrEnvironment } from '../ingest/ocr.js';
import { officeEnvironment,preparePptxPreview } from '../render/pptx-preview.js';
const require=createRequire(import.meta.url);
function dependencyVersion(name:string):string {
  let folder=dirname(require.resolve(name));
  while(folder!==dirname(folder)) {
    const path=join(folder,'package.json');
    if(existsSync(path)) {const data=JSON.parse(readFileSync(path,'utf8'));if(data.name===name)return data.version;}
    folder=dirname(folder);
  }
  throw new Error('Dependency metadata not found: '+name);
}
export interface AnalyzeProgress {analysis_run_id:string;phase:'extract'|'match'|'save'|'complete';current:number;total:number;label?:string}
export async function analyze(input:InputManifest,baseDir:string,store:Store,signal?:AbortSignal,onProgress?:(progress:AnalyzeProgress)=>void,options:{persist?:boolean;ocr?:'off'|'auto'|'all';pptxPreview?:boolean}={}):Promise<{report:ReportData,analysis_run_id:string}> {
  const manifest=Manifest.parse(input);
  const environment:Record<string,string>={node:process.version,platform:process.platform,arch:process.arch,engine:ENGINE_VERSION,
    pdfjs:dependencyVersion('pdfjs-dist'),xml:dependencyVersion('fast-xml-parser'),fflate:dependencyVersion('fflate'),
    renderer:options.pptxPreview===false?'disabled':await officeEnvironment()??'unavailable',ocr:options.ocr==='off'?'disabled':await ocrEnvironment(),settings:`ocr:${options.ocr??'auto'};max-input-512MiB;max-pdf-pages-1000`};
  const run=store.beginRun(manifest.project_id,manifest.title);
  try {
    onProgress?.({analysis_run_id:run,phase:'extract',current:0,total:manifest.revisions.length});
    const revisions:RevisionData[]=[];
    const timelineIdentity=[];
    for(const [index,entry] of manifest.revisions.entries()) {
      const inputs=[];
      for(const [fileIndex,file] of entry.files.entries()) {
        try {
          const path=resolve(baseDir,file),size=(await stat(path)).size;
          inputs.push(size>MAX_INPUT_BYTES?`oversized:${size}`:'sha256:'+byteHash(await readFile(path)));
        } catch {inputs.push(`unreadable:${index}:${fileIndex}`);}
      }
      timelineIdentity.push({label:entry.label,assets:inputs.sort()});
    }
    const timelineId=id('timeline',timelineIdentity);
    const cache=new Map<string,Extracted>();
    for(const [index,entry] of manifest.revisions.entries()) {
      signal?.throwIfAborted();
      onProgress?.({analysis_run_id:run,phase:'extract',current:index,total:manifest.revisions.length,label:entry.label});
      const extracted:Extracted[]=[], errors:RevisionData['errors']=[],failedInputs:string[]=[];
      for(const file of entry.files) {
        const path=resolve(baseDir,file);
        try {
          const observation=cache.get(path)??await ingest(path,{ocr:options.ocr??'auto',cacheRoot:join(store.root,'cache'),signal,onPage:(current,total)=>onProgress?.({analysis_run_id:run,phase:'extract',current:index,total:manifest.revisions.length,label:entry.label+` · PDF ${current}/${total}`})});
          if(!cache.has(path)&&observation.asset.format==='pptx'&&options.pptxPreview!==false){
            try{const pdf=await preparePptxPreview(path,observation.bytes,observation.pages,join(store.root,'cache'),signal);if(pdf)store.putAsset('sha256:'+byteHash(pdf),pdf);}
            catch(e){if(signal?.aborted||(e instanceof DocverError&&e.code==='CANCELLED'))throw e;for(const p of observation.pages){p.preview=undefined;p.capabilities.preview='unavailable';p.coverage_gaps.push({feature:'preview',reason:e instanceof DocverError?e.code:'CONVERSION_FAILED'});}}
          }
          cache.set(path,observation);
          store.putAsset(observation.asset.asset_id,observation.bytes);extracted.push(observation);
        } catch(e) {
          if(signal?.aborted||(e instanceof DocverError&&e.code==='CANCELLED'))throw e;
          // Preserve a content identity even when parsing fails; never put local paths in a report.
          try {const size=(await stat(path)).size;failedInputs.push(size>MAX_INPUT_BYTES?`oversized:${size}`:'sha256:'+byteHash(await readFile(path)));} catch {failedInputs.push('unreadable:'+failedInputs.length);}
          errors.push({code:e instanceof DocverError?e.code:'INPUT_UNREADABLE',message:e instanceof DocverError?e.message:'Input could not be read'});
        }
      }
      if(extracted.length===2&&extracted[0].asset.format===extracted[1].asset.format) throw new DocverError('INVALID_BUNDLE','Bundle requires one PPTX and one PDF');
      const revisionId=id('rev',[extracted.map(e=>e.asset.asset_id).sort(),failedInputs.sort()]);
      const occurrence=id('occ',[timelineId,index,revisionId]);
      const primary=extracted.find(e=>e.asset.format==='pptx')??extracted[0];
      const stamp=(pages:Extracted['pages'])=>pages.map(p=>({...p,page_id:id('pg',[occurrence,p.page_id]),
        elements:p.elements.map(e=>({...e,observation_id:id('obs',[occurrence,e.observation_id])}))}));
      const pages=stamp(primary?.pages??[]),bundleMapping:RevisionData['bundle_mapping']=[],gaps:RevisionData['coverage_gaps']=[];
      if(extracted.length===2) {
        const secondary=extracted.find(e=>e!==primary)!;
        const rendered=stamp(secondary.pages), visible=pages.filter(p=>!p.hidden),pairing=matchPages(visible,rendered);
        for(const m of pairing.matches.filter(m=>m.status!=='needs_review')) bundleMapping.push({source_page_id:m.from_page_id,rendered_page_id:m.to_page_id,score:m.score});
        if(pairing.matches.length!==visible.length||pairing.matches.length!==rendered.length||pairing.matches.some(m=>m.status==='needs_review'||m.score<0.95)||pairing.matches.some(m=>{
          const a=visible.find(p=>p.page_id===m.from_page_id)!,b=rendered.find(p=>p.page_id===m.to_page_id)!;
          return a.text.replace(/\s/g,'')!==b.text.replace(/\s/g,'');
        })) gaps.push({feature:'bundle',reason:'bundle_inconsistent'});
        // Keep the secondary source independently addressable; it is not silently substituted for structure.
        pages.push(...rendered);
      }
      const revision:RevisionData={revision_id:revisionId,revision_occurrence_id:occurrence,label:entry.label,assets:extracted.map(e=>e.asset),status:errors.length?(extracted.length?'partial':'failed'):'success',pages,
        coverage_gaps:[...gaps,...(errors.length?[{feature:'input',reason:'input_extraction_failed'}]:[]),...pages.flatMap(p=>p.coverage_gaps.map(g=>({...g,page_id:p.page_id,revision_id:revisionId})))],errors,bundle_mapping:bundleMapping};
      revisions.push(revision);
    }
    onProgress?.({analysis_run_id:run,phase:'match',current:revisions.length,total:revisions.length});
    signal?.throwIfAborted();
    const decisions=manifest.mapping_decisions;
    const allPageIds=new Set(revisions.flatMap(r=>r.pages.map(p=>p.page_id)));
    for(const d of decisions) {
      if(!allPageIds.has(d.from_page_id)||!allPageIds.has(d.to_page_id)) throw new DocverError('MAPPING_NOT_FOUND','Decision references a page outside this timeline');
      const a=revisions.findIndex(r=>r.pages.some(p=>p.page_id===d.from_page_id));
      const b=revisions.findIndex(r=>r.pages.some(p=>p.page_id===d.to_page_id));
      if(b!==a+1) throw new DocverError('MAPPING_INTERVAL','Manual decisions currently require adjacent revisions');
    }
    const matches:ReportData['matches']=[],candidates:ReportData['candidates']=[];
    const primaryPages=(r:RevisionData)=> r.assets.some(a=>a.format==='pptx')?r.pages.filter(p=>r.assets.find(a=>a.asset_id===p.asset_id)?.format==='pptx'):r.pages;
    for(let i=1;i<revisions.length;i++) {
      if(revisions[i-1].status==='failed'||revisions[i].status==='failed') continue;
      const pairing=matchPages(primaryPages(revisions[i-1]),primaryPages(revisions[i]),decisions);
      matches.push(...pairing.matches);candidates.push(...pairing.candidates);
    }
    // A known hidden slide can bridge an intermediate PDF visibility gap; no fictional delete/add.
    for(let i=2;i<revisions.length;i++) {
      if(!revisions[i-1].assets.every(a=>a.format==='pdf')||revisions[i-1].status!=='success') continue;
      for(const a of primaryPages(revisions[i-2]).filter(p=>p.hidden)) {
        const possible=primaryPages(revisions[i]).filter(b=>b.hidden&&similarity(a,b)>0.95);
        if(possible.length===1) matches.push({from_page_id:a.page_id,to_page_id:possible[0].page_id,score:similarity(a,possible[0]),status:'inferred',reasons:['hidden_slide_observation_gap']});
      }
    }
    const parent=new Map<string,string>();
    for(const p of revisions.flatMap(r=>r.pages)) parent.set(p.page_id,p.page_id);
    function root(p:string):string {const next=parent.get(p)!;if(next===p)return p;const r=root(next);parent.set(p,r);return r;}
    for(const m of matches) parent.set(root(m.to_page_id),root(m.from_page_id));
    const entityFor=(p:string)=>id('ent',[manifest.project_id,ENGINE_VERSION,root(p)]);
    const lineages:ReportData['lineages']=[];
    for(const p of revisions.flatMap(r=>r.pages)) {
      const entity=entityFor(p.page_id);let lineage=lineages.find(l=>l.entity_id===entity);
      if(!lineage) {lineage={entity_id:entity,page_ids:[],status:'inferred'};lineages.push(lineage);}lineage.page_ids.push(p.page_id);
    }
    for(const lineage of lineages) {
      const edges=matches.filter(m=>lineage.page_ids.includes(m.from_page_id));
      lineage.status=edges.some(m=>m.status==='needs_review')?'needs_review':edges.length&&edges.every(m=>m.status==='human_confirmed')?'human_confirmed':'inferred';
    }
    const comparisons=revisions.map(r=>({...r,pages:primaryPages(r)}));
    const changes=comparisons.slice(1).flatMap((r,i)=>diffRevisions(comparisons[i],r,matches,candidates,entityFor));
    const coverage=revisions.flatMap(r=>r.coverage_gaps);
    const base={schema_version:SCHEMA_VERSION,engine_version:ENGINE_VERSION,project_id:manifest.project_id,timeline_revision_id:timelineId,
      mapping_revision_id:id('mapping',decisions),schema_hash:SCHEMA_HASH,observation_environment:environment,revisions,matches,candidates,mapping_decisions:decisions,lineages,changes,coverage_gaps:coverage};
    const reportId=id('rpt',base);
    changes.forEach((c,i)=>{c.report_id=reportId;c.change_id=id('chg',[reportId,i,c]);c.evidence_uri=`docver://projects/${manifest.project_id}/reports/${reportId}/changes/${c.change_id}`;});
    const report=Report.parse({...base,report_id:reportId});
    onProgress?.({analysis_run_id:run,phase:'save',current:revisions.length,total:revisions.length});
    signal?.throwIfAborted();
    if(options.persist!==false){
      store.finishRun(run,report,revisions.some(r=>r.status!=='success')?'partial':'success');
      onProgress?.({analysis_run_id:run,phase:'complete',current:revisions.length,total:revisions.length});
    }
    return {report,analysis_run_id:run};
  } catch(e) {store.failRun(run,e instanceof DocverError?e.code:(e as Error).name);throw e;}
}
