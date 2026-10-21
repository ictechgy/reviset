import { resolve, dirname, join } from 'node:path';
import { readFileSync, existsSync } from 'node:fs';
import { stat,readFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { MAX_INPUT_BYTES,Manifest, Report, SCHEMA_VERSION, SCHEMA_HASH, ENGINE_VERSION, id, byteHash, DocverError, validBundleDecisionLog, type InputManifest, type RevisionData, type ReportData } from '../schema/index.js';
import { ingest, type Extracted } from '../ingest/index.js';
import {PPTX_TEXT_POLICY} from '../ingest/pptx.js';
import {PDF_TEXT_GEOMETRY_POLICY} from '../ingest/pdf.js';
import { matchPagesCooperative, similarity,MATCHING_WORK_POLICY,MAX_ASSIGNMENT_COSTS,MAX_MATCHING_MATRIX_CELLS } from '../matching/index.js';
import {primaryPages,validateMappings} from '../matching/relations.js';
import { diffRevisions } from '../diff/index.js';
import {applyBundleDecisions} from '../bundle/index.js';
import { Store } from '../storage/index.js';
import { fileSha256 } from '../runtime/file-hash.js';
import {pdfWorkerEnvironment} from '../runtime/pdfjs-environment.js';
import { ocrEnvironment } from '../ingest/ocr.js';
import { officeEnvironment,preparePptxPreview } from '../render/pptx-preview.js';
import {qualifyReferenceAppearance,attachReferenceAppearance} from '../render/reference-appearance.js';
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
export interface AnalyzeProgress {analysis_run_id:string;phase:'extract'|'render'|'match'|'save'|'complete';current:number;total:number;label?:string}
export async function analyze(input:InputManifest,baseDir:string,store:Store,signal?:AbortSignal,onProgress?:(progress:AnalyzeProgress)=>void,options:{persist?:boolean;ocr?:'off'|'auto'|'all';pptxPreview?:boolean}={}):Promise<{report:ReportData,analysis_run_id:string}> {
  const manifest=Manifest.parse(input);
  const environment:Record<string,string>={node:process.version,platform:process.platform,arch:process.arch,engine:ENGINE_VERSION,
    pdfjs:dependencyVersion('pdfjs-dist'),pdfjs_worker_sha256:await pdfWorkerEnvironment(),pdf_text_geometry_policy:PDF_TEXT_GEOMETRY_POLICY,matching_work_policy:MATCHING_WORK_POLICY,xml:dependencyVersion('fast-xml-parser'),fflate:dependencyVersion('fflate'),pptx_text_policy:PPTX_TEXT_POLICY,
    renderer:options.pptxPreview===false?'disabled':manifest.revisions.some(r=>r.files.some(f=>/\.pptx$/i.test(f)))?await officeEnvironment()??'unavailable':'not_used',ocr:options.ocr==='off'?'disabled':await ocrEnvironment(),settings:`ocr:${options.ocr??'auto'};max-input-512MiB;max-pdf-pages-1000`};
  const run=store.beginRun(manifest.project_id,manifest.title);
  try {
    onProgress?.({analysis_run_id:run,phase:'extract',current:0,total:manifest.revisions.length});
    const revisions:RevisionData[]=[];
    const timelineIdentity=[],inputIdentities:string[][]=[],referenceSources=new Map<string,Set<string>>();
    for(const [index,entry] of manifest.revisions.entries()) {
      const inputs=[];
      for(const [fileIndex,file] of entry.files.entries()) {
        try {
          const path=resolve(baseDir,file),size=(await stat(path)).size;
          inputs.push(size>MAX_INPUT_BYTES?`oversized:${size}`:'sha256:'+await fileSha256(path,signal));
        } catch {inputs.push(`unreadable:${index}:${fileIndex}`);}
      }
      inputIdentities.push([...inputs]);
      const pptx=entry.files.findIndex(f=>/\.pptx$/i.test(f)),pdf=entry.files.findIndex(f=>/\.pdf$/i.test(f));
      if(pptx>=0&&pdf>=0&&inputs[pptx].startsWith('sha256:')&&inputs[pdf].startsWith('sha256:')){
        const sources=referenceSources.get(inputs[pdf])??new Set<string>();sources.add(inputs[pptx]);referenceSources.set(inputs[pdf],sources);
      }
      timelineIdentity.push({label:entry.label,assets:[...inputs].sort()});
    }
    const timelineId=id('timeline',timelineIdentity);
    const cache=new Map<string,Omit<Extracted,'bytes'>>();
    for(const [index,entry] of manifest.revisions.entries()) {
      signal?.throwIfAborted();
      onProgress?.({analysis_run_id:run,phase:'extract',current:index,total:manifest.revisions.length,label:entry.label});
      const extracted:Omit<Extracted,'bytes'>[]=[], errors:RevisionData['errors']=[],failedInputs:string[]=[];
      for(const [fileIndex,file] of entry.files.entries()) {
        const path=resolve(baseDir,file);
        try {
          const expected=inputIdentities[index][fileIndex],cacheKey=JSON.stringify([expected,/\.pptx$/i.test(file)?'pptx':'pdf']);
          let observation=cache.get(cacheKey);
          if(!observation){const loaded=await ingest(path,{ocr:options.ocr??'auto',reuseRasterOcr:revisions.some(r=>r.pages.some(p=>p.ocr?.status==='available')),cacheRoot:join(store.root,'cache'),signal,onPage:(current,total)=>onProgress?.({analysis_run_id:run,phase:'extract',current:index,total:manifest.revisions.length,label:entry.label+` · PDF ${current}/${total}`})});
            if(loaded.asset.asset_id!==expected)throw new DocverError('SOURCE_CHANGED','Input changed while analysis was starting; retry with stable source files');
            store.putAsset(loaded.asset.asset_id,loaded.bytes);const {bytes,...metadata}=loaded;observation=structuredClone(metadata);cache.set(cacheKey,observation);
          }
          // Raw parse observations belong to the asset. Bundle/preview enrichment
          // belongs to this occurrence and must never leak through the cache.
          extracted.push(structuredClone(observation));

        } catch(e) {
          if(signal?.aborted||(e instanceof DocverError&&['CANCELLED','SOURCE_CHANGED'].includes(e.code)))throw e;
          // Preserve a content identity even when parsing fails; never put local paths in a report.
          try {const size=(await stat(path)).size;failedInputs.push(size>MAX_INPUT_BYTES?`oversized:${size}`:'sha256:'+await fileSha256(path,signal));} catch {failedInputs.push('unreadable:'+failedInputs.length);}
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
      let referenceQualified=false;
      if(extracted.length===2) {
        const secondary=extracted.find(e=>e!==primary)!;
        const rendered=stamp(secondary.pages), visible=pages.filter(p=>!p.hidden),pairing=await matchPagesCooperative(visible,rendered,[],[],{maxCosts:MAX_ASSIGNMENT_COSTS,maxMatrixCells:MAX_MATCHING_MATRIX_CELLS,signal});
        for(const m of pairing.matches.filter(m=>m.status!=='needs_review')) bundleMapping.push({source_page_id:m.from_page_id,rendered_page_id:m.to_page_id,score:m.score});
        if(pairing.matches.length!==visible.length||pairing.matches.length!==rendered.length||pairing.matches.some(m=>m.status==='needs_review'||m.score<0.95)||pairing.matches.some(m=>{
          const a=visible.find(p=>p.page_id===m.from_page_id)!,b=rendered.find(p=>p.page_id===m.to_page_id)!;
          return a.text.replace(/\s/g,'')!==b.text.replace(/\s/g,'');
        })) gaps.push({feature:'bundle',reason:'bundle_inconsistent'});
        if(primary?.asset.format==='pptx'&&secondary.asset.format==='pdf'){
          const qualification=qualifyReferenceAppearance(pages,rendered,bundleMapping,pairing.matches.some(m=>m.status==='needs_review')||gaps.some(g=>g.reason==='bundle_inconsistent'),(referenceSources.get(secondary.asset.asset_id)?.size??0)>1);
          referenceQualified=qualification.qualified;
          if(referenceQualified)attachReferenceAppearance(pages,rendered,bundleMapping);
          else gaps.push({feature:'reference_appearance',reason:qualification.reason});
        }
        // Keep the secondary source independently addressable; it is not silently substituted for structure.
        pages.push(...rendered);
      }
      signal?.throwIfAborted();
      const revision:RevisionData={revision_id:revisionId,revision_occurrence_id:occurrence,label:entry.label,assets:extracted.map(e=>e.asset),status:errors.length?(extracted.length?'partial':'failed'):'success',pages,
        reference_appearance_policy:'bundle-reference-v2',
        coverage_gaps:[...gaps,...(errors.length?[{feature:'input',reason:'input_extraction_failed'}]:[]),...pages.flatMap(p=>p.coverage_gaps.map(g=>({...g,page_id:p.page_id,revision_id:revisionId})))],errors,bundle_mapping:bundleMapping,bundle_mapping_basis:structuredClone(bundleMapping)};
      revisions.push(revision);
    }
    const bundleDecisions=manifest.bundle_decisions??[];
    if(!validBundleDecisionLog(revisions,bundleDecisions))throw new DocverError('BUNDLE_HISTORY','페이지 연결 이력을 검증하지 못해 새 보고서를 저장하지 않았습니다. 문서 판독 결과와 이력을 확인하세요. 이전 보고서는 그대로 열 수 있습니다. 같은 원본을 새 프로젝트로 가져오면 연결을 다시 확인해야 합니다.');
    for(const [index,revision]of revisions.entries()){
      signal?.throwIfAborted();
      const pdf=revision.assets.find(a=>a.format==='pdf');
      applyBundleDecisions(revision,bundleDecisions,!!pdf&&(referenceSources.get(pdf.asset_id)?.size??0)>1);
      const source=revision.assets.find(a=>a.format==='pptx'),sourcePages=revision.pages.filter(p=>p.asset_id===source?.asset_id),visible=sourcePages.filter(p=>!p.hidden);
      const allDisplayed=visible.length>0?visible.every(p=>!!p.appearance):sourcePages.length>0&&sourcePages.every(p=>!!p.appearance);
      if(source&&options.pptxPreview!==false&&!allDisplayed){
        onProgress?.({analysis_run_id:run,phase:'render',current:index,total:revisions.length,label:revision.label});
        try{
          const bytes=await readFile(join(store.root,'assets',source.asset_id.slice(7)));
          if('sha256:'+byteHash(bytes)!==source.asset_id)throw new DocverError('ASSET_CORRUPT','Stored source hash mismatch');
          const derived=structuredClone(sourcePages);for(const page of derived)page.appearance=undefined;
          const sourcePath=manifest.revisions[index].files.find(file=>/\.pptx$/i.test(file))!;
          const converted=await preparePptxPreview(resolve(baseDir,sourcePath),bytes,derived,join(store.root,'cache'),signal);if(converted)store.putAsset('sha256:'+byteHash(converted),converted);
          for(const [i,page]of sourcePages.entries())if(!page.appearance){page.preview=derived[i].preview;page.raster=derived[i].raster;page.capabilities.preview=derived[i].capabilities.preview;page.coverage_gaps=derived[i].coverage_gaps;}
        }catch(e){if(signal?.aborted||(e instanceof DocverError&&e.code==='CANCELLED'))throw e;for(const page of sourcePages.filter(p=>!p.appearance)){page.preview=undefined;page.raster=undefined;page.capabilities.preview='unavailable';page.coverage_gaps=page.coverage_gaps.filter(g=>g.feature!=='render_fidelity');page.coverage_gaps.push({feature:'preview',reason:e instanceof DocverError?e.code:'CONVERSION_FAILED'});}}
      }
      revision.coverage_gaps=[...revision.coverage_gaps.filter(g=>!g.page_id),...revision.pages.flatMap(p=>p.coverage_gaps.map(g=>({...g,page_id:p.page_id,revision_id:revision.revision_id})))];
    }
    onProgress?.({analysis_run_id:run,phase:'match',current:revisions.length,total:revisions.length});
    signal?.throwIfAborted();
    const decisions=manifest.mapping_decisions;
    const relations=validateMappings(revisions,decisions,manifest.mapping_relations??[]);
    const matches:ReportData['matches']=[],candidates:ReportData['candidates']=[];
    for(let i=1;i<revisions.length;i++) {
      if(revisions[i-1].status==='failed'||revisions[i].status==='failed') continue;
      await new Promise<void>(resume=>setImmediate(resume));signal?.throwIfAborted();
      const pairing=await matchPagesCooperative(primaryPages(revisions[i-1]),primaryPages(revisions[i]),decisions,relations.filter(r=>r.from_occurrence===revisions[i-1].revision_occurrence_id&&r.to_occurrence===revisions[i].revision_occurrence_id),{maxCosts:MAX_ASSIGNMENT_COSTS,maxMatrixCells:MAX_MATCHING_MATRIX_CELLS,signal});
      matches.push(...pairing.matches);candidates.push(...pairing.candidates);
    }
    // A known hidden slide can bridge an intermediate PDF visibility gap; no fictional delete/add.
    for(let i=2;i<revisions.length;i++) {
      if(!revisions[i-1].assets.every(a=>a.format==='pdf')||revisions[i-1].status!=='success') continue;
      for(const a of primaryPages(revisions[i-2]).filter(p=>p.hidden)) {
        const possible=primaryPages(revisions[i]).filter(b=>b.hidden&&similarity(a,b)>0.95);
        if(possible.length===1&&!matches.some(m=>m.from_page_id===a.page_id||m.to_page_id===possible[0].page_id)&&!decisions.some(d=>d.action==='unlink'&&(d.from_page_id===a.page_id||d.to_page_id===possible[0].page_id))) matches.push({from_page_id:a.page_id,to_page_id:possible[0].page_id,score:similarity(a,possible[0]),status:'inferred',reasons:['hidden_slide_observation_gap']});
      }
    }
    const parent=new Map<string,string>();
    for(const p of revisions.flatMap(r=>r.pages)) parent.set(p.page_id,p.page_id);
    function root(p:string):string {const next=parent.get(p)!;if(next===p)return p;const r=root(next);parent.set(p,r);return r;}
    for(const m of matches) parent.set(root(m.to_page_id),root(m.from_page_id));
    const entityFor=(p:string)=>id('ent',[manifest.project_id,ENGINE_VERSION,root(p)]);
    const lineages:ReportData['lineages']=[],byEntity=new Map<string,ReportData['lineages'][number]>();
    for(const p of revisions.flatMap(r=>r.pages)) {
      const entity=entityFor(p.page_id);let lineage=byEntity.get(entity);
      if(!lineage) {lineage={entity_id:entity,page_ids:[],status:'inferred'};lineages.push(lineage);byEntity.set(entity,lineage);}lineage.page_ids.push(p.page_id);
    }
    const edgeStates=new Map<string,{count:number;review:boolean;human:boolean}>();
    for(const edge of matches){const entity=entityFor(edge.from_page_id),state=edgeStates.get(entity)??{count:0,review:false,human:true};state.count++;state.review ||= edge.status==='needs_review';state.human &&= edge.status==='human_confirmed';edgeStates.set(entity,state);}
    for(const lineage of lineages) {
      const state=edgeStates.get(lineage.entity_id);
      lineage.status=state?.review?'needs_review':state?.count&&state.human?'human_confirmed':'inferred';
    }
    const comparisons=revisions.map(r=>({...r,pages:primaryPages(r)}));
    const changes=comparisons.slice(1).flatMap((r,i)=>diffRevisions(comparisons[i],r,matches,candidates,entityFor));
    const coverage=revisions.flatMap(r=>r.coverage_gaps);
    const base={schema_version:SCHEMA_VERSION,engine_version:ENGINE_VERSION,project_id:manifest.project_id,timeline_revision_id:timelineId,
      mapping_revision_id:id('mapping',[decisions,relations,bundleDecisions]),schema_hash:SCHEMA_HASH,observation_environment:environment,revisions,matches,candidates,mapping_decisions:decisions,mapping_relations:relations,bundle_decisions:bundleDecisions,lineages,changes,coverage_gaps:coverage};
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
