import { readFileSync,createReadStream } from 'node:fs';
import { createHash } from 'node:crypto';
import { mkdir,writeFile,readFile,rm,readdir,lstat } from 'node:fs/promises';
import { dirname,join,resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { z } from 'zod';
import { DesktopService,type DesktopDraft } from '../../packages/desktop/service.js';
import { DocverError, Decision, RelationSelection, BundleSelection,bundleDirectiveState, byteHash, hash,comparisonText,textChunk,unresolvedComparisonText, SCHEMA_VERSION, ENGINE_VERSION } from '../../packages/schema/index.js';
import { querySchemas } from '../../packages/query/index.js';
import {SidecarScope,createOnlyOfficeSidecar,closeOnlyOfficeSidecar,recoverOnlyOfficeSidecars,onlyOfficeSidecarConfigured} from '../../packages/render/onlyoffice-sidecar.js';
import {cancelActiveTools} from '../../packages/runtime/tools.js';
import {handleWorkbookAction} from './workbook.js';
const key=z.string().regex(/^[a-zA-Z0-9_-]{1,160}$/),scope=z.object({project_id:key,report_id:key});
const request=JSON.parse(readFileSync(0,'utf8')) as {action:string;args:any};
const rootArg=process.argv.indexOf('--root');if(rootArg<0)throw new Error('Explicit app library required');
const root=resolve(process.argv[rootArg+1]),service=new DesktopService(root),args=request.args??{};
function projectResponse(project:DesktopDraft){const {bundle_decisions,...rest}=project;return {...rest,bundle_decision_count:bundle_decisions.length,draft_hash:hash(service.manifest(project.project_id))};}
function readableDraftHash(projectId:string){try{return hash(service.manifest(projectId));}catch(error){if(error instanceof DocverError&&error.code==='DRAFT_UNREADABLE')return null;throw error;}}
function fixedLatestReport(projectId:string){try{return service.store.resolveReportId(projectId,'latest');}catch(error){if(error instanceof DocverError&&error.code==='REPORT_NOT_FOUND')return null;throw error;}}
async function stageCleanupPending(runId:string):Promise<boolean>{try{await lstat(join(root,'staging-v4',runId+'.json'));return true;}catch(error){return (error as NodeJS.ErrnoException).code!=='ENOENT';}}
async function verifiedSource(assetId:string):Promise<string>{
  if(!/^sha256:[a-f0-9]{64}$/.test(assetId))throw new DocverError('ASSET_ID','잘못된 원본 ID입니다.');
  const path=join(root,'assets',assetId.slice(7)),digest=createHash('sha256');for await(const chunk of createReadStream(path,{highWaterMark:1024*1024}))digest.update(chunk);
  if(digest.digest('hex')!==assetId.slice(7))throw new DocverError('ASSET_CORRUPT','표시할 원본의 hash가 일치하지 않습니다.');return path;
}
try{
  let value:unknown;
  if(request.action.startsWith('workbook')) {
    if(request.action==='workbookMcpConfig') {
      const {project_id}=z.object({project_id:key}).parse(args);await handleWorkbookAction(service.store,'workbookReports',{project_id});
      value=JSON.stringify({mcpServers:{reviset:{command:process.execPath,args:[join(dirname(fileURLToPath(import.meta.url)),'mcp.mjs'),'--store',root,'--project',project_id]}}},null,2);
    }else value=await handleWorkbookAction(service.store,request.action,args);
  }else switch(request.action){
    case 'sidecarInfo':value={configured:await onlyOfficeSidecarConfigured(join(dirname(fileURLToPath(import.meta.url)),'../onlyoffice-sidecar'))};break;
    case 'sidecarCreate':{
      const d=SidecarScope.parse(args),report=service.snapshot(d.project_id,d.report_id),controller=new AbortController(),cancel=()=>controller.abort();
      process.once('SIGTERM',cancel);process.once('SIGINT',cancel);
      const parent=process.ppid,parentWatch=setInterval(()=>{if(parent<=1||process.ppid!==parent){clearInterval(parentWatch);cancel();}},100);parentWatch.unref();
      try{value=await createOnlyOfficeSidecar({library:root,resources:join(dirname(fileURLToPath(import.meta.url)),'../onlyoffice-sidecar'),guard:join(dirname(process.execPath),'DocverRendererGuard'),report,scope:d,signal:controller.signal});}
      finally{clearInterval(parentWatch);process.removeListener('SIGTERM',cancel);process.removeListener('SIGINT',cancel);}break;
    }
    case 'sidecarClose':{const d=SidecarScope.parse(args);service.reports(d.project_id);await closeOnlyOfficeSidecar(root,d);value={closed:true};break;}
    case 'sidecarRecover':value=await recoverOnlyOfficeSidecars(root);break;
    case 'projects':{const projects=service.projects().map(projectResponse);value=[...projects,...service.unreadableProjects.map(p=>({...p,title:'입력 기록 확인 필요 · '+p.project_id.slice(0,20),unreadable:true,revisions:[],last_report_id:fixedLatestReport(p.project_id)}))];break;}
    case 'recover':{const d=z.object({run_id:z.string().optional()}).parse(args);value=service.recover(d.run_id).map(projectResponse);const folder=join(root,'staging-v4');try{for(const name of await readdir(folder))if(/^run_[a-f0-9-]+\.json$/.test(name)&&(!d.run_id||name===d.run_id+'.json'))await rm(join(folder,name));}catch(e){if((e as NodeJS.ErrnoException).code!=='ENOENT')throw e;}break;}
    case 'create':{const data=z.object({title:z.string().trim().min(1).max(200),revisions:z.array(z.object({label:z.string().trim().min(1).max(200),files:z.array(z.string()).min(1).max(2),expected_sha256:z.array(z.string().regex(/^[a-f0-9]{64}$/).nullable()).min(1).max(2).optional()}).refine(r=>!r.expected_sha256||r.expected_sha256.length===r.files.length,'File identity count must match input count')).min(1).max(100)}).parse(args);value=await service.create(data.title,data.revisions);break;}
    case 'analyze':{
      const {project_id}=z.object({project_id:key}).parse(args),controller=new AbortController(),cancel=()=>{controller.abort();cancelActiveTools();},parent=process.ppid;
      process.once('SIGTERM',cancel);process.once('SIGINT',cancel);
      const parentWatch=setInterval(()=>{if(parent<=1||process.ppid!==parent){clearInterval(parentWatch);cancel();}},100);parentWatch.unref();
      try {
        const result=await service.run(project_id,controller.signal,p=>process.stderr.write(JSON.stringify({event:'progress',progress:p})+'\n'),false);controller.signal.throwIfAborted();
        const data=Buffer.from(JSON.stringify(result.report)),folder=join(root,'staging-v4');await mkdir(folder,{recursive:true,mode:0o700});controller.signal.throwIfAborted();const name=result.analysis_run_id+'.json';await writeFile(join(folder,name),data,{flag:'wx',mode:0o600});value={analysis_run_id:result.analysis_run_id,report_id:result.report.report_id,staged_name:name,sha256:byteHash(data),draft_hash:result.draft_hash,project_id,schema_version:SCHEMA_VERSION,engine_version:ENGINE_VERSION};
      }finally{clearInterval(parentWatch);process.removeListener('SIGTERM',cancel);process.removeListener('SIGINT',cancel);}break;
    }
    case 'commit':{
      const {project_id}=z.object({project_id:key}).parse(args);
      const d=z.object({analysis_run_id:z.string().regex(/^run_[a-f0-9-]+$/),report_id:key,staged_name:z.string().regex(/^run_[a-f0-9-]+\.json$/),sha256:z.string().regex(/^[a-f0-9]{64}$/),draft_hash:z.string(),project_id:key,schema_version:z.literal(SCHEMA_VERSION),engine_version:z.literal(ENGINE_VERSION)}).parse(args.result);
      if(d.project_id!==project_id||d.staged_name!==d.analysis_run_id+'.json'||d.draft_hash!==hash(service.manifest(project_id)))throw new DocverError('STALE_RUN','입력이 바뀐 분석 결과는 저장하지 않습니다.');
      const path=join(root,'staging-v4',d.staged_name),data=await readFile(path);
      if(byteHash(data)!==d.sha256)throw new DocverError('STAGED_HASH','분석 결과 hash 검증에 실패했습니다.');
      const report=JSON.parse(data.toString('utf8'));
      if(report.report_id!==d.report_id)throw new DocverError('STAGED_ID','분석 보고서 ID가 일치하지 않습니다.');
      const reportId=service.commit(project_id,{report,analysis_run_id:d.analysis_run_id,draft_hash:d.draft_hash});
      let cleanupPending=false;try{await rm(path,{force:true});}catch{cleanupPending=true;}
      value={report_id:reportId,status:'complete',cleanup_pending:cleanupPending};break;
    }
    case 'runStatus':{
      const {project_id,analysis_run_id}=z.object({project_id:key,analysis_run_id:z.string().regex(/^run_[a-f0-9-]+$/)}).parse(args);
      const run=service.store.db.prepare('SELECT status,report_id FROM runs WHERE id=? AND project_id=?').get(analysis_run_id,project_id);
      if(!run)throw new DocverError('RUN_SCOPE','분석 실행이 이 프로젝트에 속하지 않습니다.');
      const status=String(run.status);if(!['running','success','partial','failed','interrupted'].includes(status))throw new DocverError('RUN_CORRUPT','분석 실행 상태를 확인할 수 없습니다.');
      const saved=status==='success'||status==='partial';
      if(saved&&(typeof run.report_id!=='string'||run.report_id==='latest'))throw new DocverError('RUN_CORRUPT','저장된 고정 보고서를 확인할 수 없습니다.');
      const reportId=saved?service.store.resolveReportId(project_id,String(run.report_id)):null;
      value={project_id,analysis_run_id,status,report_id:reportId,cleanup_pending:saved?await stageCleanupPending(analysis_run_id):false};break;
    }
    case 'reorder':{const d=z.object({project_id:key,order:z.array(z.number().int()),discard_human_decisions:z.boolean().default(false),draft_hash:z.string().regex(/^[a-f0-9]{64}$/).optional()}).parse(args);value=projectResponse(service.reorder(d.project_id,d.order,d.discard_human_decisions,d.draft_hash));break;}
    case 'mapping':{const d=scope.extend({decision:Decision}).parse(args);value=projectResponse(service.mapping(d.project_id,d.report_id,d.decision));break;}
    case 'mappingRelation':{const d=scope.extend({selection:RelationSelection,unlink:z.boolean().default(false),draft_hash:z.string().regex(/^[a-f0-9]{64}$/)}).parse(args);value=projectResponse(service.mappingRelation(d.project_id,d.report_id,d.selection,d.unlink,d.draft_hash));break;}
    case 'bundleMapping':{const d=scope.extend({selection:BundleSelection,draft_hash:z.string().regex(/^[a-f0-9]{64}$/)}).parse(args);value=service.bundleMapping(d.project_id,d.report_id,d.selection,d.draft_hash);break;}
    case 'bundleDecisions':{const d=querySchemas.list_bundle_decisions.parse(args);value=service.queryService(d.project_id).query('list_bundle_decisions',d);break;}
    case 'bundle':{
      const d=scope.extend({revision_occurrence_id:key}).parse(args),report=service.snapshot(d.project_id,d.report_id),revision=report.revisions.find(r=>r.revision_occurrence_id===d.revision_occurrence_id);
      if(!revision||revision.assets.length!==2||!revision.assets.some(a=>a.format==='pptx')||!revision.assets.some(a=>a.format==='pdf'))throw new DocverError('BUNDLE_SCOPE','같은 버전의 PPTX와 PDF 묶음을 선택하세요.');
      let project:DesktopDraft|undefined;try{project=service.project(d.project_id);}catch(error){if(!(error instanceof DocverError&&error.code==='DRAFT_UNREADABLE'))throw error;}
      const decisions=new Map((report.bundle_decisions??[]).map(v=>[v.decision_id,v])),ids=new Set(revision.pages.map(p=>p.page_id));
      value={project_id:d.project_id,report_id:d.report_id,draft_hash:readableDraftHash(d.project_id),current_snapshot:!!project&&!project.dirty&&project.last_report_id===d.report_id,revision:{...revision,pages:revision.pages.map(p=>({page_id:p.page_id,asset_id:p.asset_id,page:p.page,width:p.width,height:p.height,text:textChunk(comparisonText(p),0,180),comparison_text_hash:hash((revision.assets.find(a=>a.asset_id===p.asset_id)?.format==='pptx'?p.text:comparisonText(p)).normalize('NFC').replace(/\s/gu,'')),comparison_unresolved:!!unresolvedComparisonText(p),native_raster_available:!!p.raster,reference_transform_available:p.source_transform.length===6,hidden:p.hidden,appearance:p.appearance?{association:p.appearance.association}:undefined,coverage_gaps:p.coverage_gaps}))},mapping:revision.bundle_mapping.map(m=>({...m,association:m.association??'inferred',reason:m.decision_id?decisions.get(m.decision_id)?.reason??'':''})),manual_states:[...bundleDirectiveState(report.bundle_decisions??[]).values()].filter(v=>ids.has(v.source_page_id)).map(v=>({source_page_id:v.source_page_id,action:v.action,displaced:v.displaced,decision_id:v.decision.decision_id})),decision_count:(report.bundle_decisions??[]).filter(v=>v.revision_occurrence_id===revision.revision_occurrence_id).length};break;
    }
    case 'reports':value=service.reports(z.object({project_id:key}).parse(args).project_id);break;
    case 'changes':{const d=querySchemas.list_changes.parse(args);value=service.queryService(d.project_id).changeSet(d);break;}
    case 'view':{
      const d=scope.parse(args),r=service.snapshot(d.project_id,d.report_id);
      const revisions=r.revisions.map(({pages,...v})=>({...v,pages:pages.map(p=>({page_id:p.page_id,asset_id:p.asset_id,page:p.page,width:p.width,height:p.height,text:textChunk(comparisonText(p),0,180),capabilities:p.capabilities,hidden:p.hidden,ocr:p.ocr,appearance:p.appearance?{kind:p.appearance.kind,source_page_id:p.appearance.source_page_id,asset_id:p.appearance.asset_id,association:p.appearance.association}:undefined,coverage_gaps:p.coverage_gaps.slice(0,3)}))}));
      const all=r.revisions.flatMap(v=>v.pages),quality_counts={ocr_inferred_pages:all.filter(p=>p.elements.some(e=>e.method==='vision_ocr')).length,ocr_failed_pages:all.filter(p=>p.ocr&&['failed','unavailable'].includes(p.ocr.status)).length,unresolved_comparison_pages:all.filter(p=>!!unresolvedComparisonText(p)||!!p.ocr_unresolved_text).length,reference_pdf_pages:all.filter(p=>!!p.appearance).length,human_reference_pdf_pages:all.filter(p=>p.appearance?.association==='human_confirmed').length,inferred_reference_pdf_pages:all.filter(p=>p.appearance?.association==='inferred').length,pptx_without_render:all.filter(p=>!p.preview&&!p.appearance&&r.revisions.some(v=>v.assets.some(a=>a.asset_id===p.asset_id&&a.format==='pptx'))).length};
      value={...r,revisions,quality_counts,draft_hash:readableDraftHash(d.project_id),changes:undefined,candidates:undefined,bundle_decisions:undefined,bundle_decision_count:r.bundle_decisions?.length??0,matches:r.matches.map(({from_page_id,to_page_id,relation_id,relation_kind,status})=>({from_page_id,to_page_id,relation_id,relation_kind,status})),coverage_gaps:r.coverage_gaps.slice(0,500),coverage_gap_count:r.coverage_gaps.length,change_counts:r.changes.reduce<Record<string,number>>((a,c)=>(a[c.kind]=(a[c.kind]??0)+1,a),{})};break;
    }
    case 'page':{
      const d=scope.extend({page_id:key,basis:z.enum(['effective','source']).default('effective')}).parse(args),{page,asset,reference:effectiveReference}=service.pageData(d.project_id,d.report_id,d.page_id);
      const reference=d.basis==='source'?undefined:effectiveReference;
      if(reference){
        const path=await verifiedSource(reference.asset_id);
        value={page,display_page:reference,source:{kind:'pdf',origin:'reference_pdf',path,renderer:'Imported reference PDF',warnings:[]},display_page_number:reference.page};
      }else if(page.preview){
        const previewPath=await verifiedSource(page.preview.asset_id);
        value={page,display_page:{...page,width:page.preview.width,height:page.preview.height,source_transform:page.preview.source_transform},source:{kind:'pdf',origin:'pptx_converted',path:previewPath,renderer:page.preview.renderer,warnings:page.preview.warnings}};
      }else value={page,display_page:page,source:{kind:asset.format,path:await verifiedSource(asset.asset_id),origin:'original'}};break;
    }
    case 'export':{const d=scope.extend({folder:z.string().min(1)}).parse(args);value=await service.export(d.project_id,d.report_id,resolve(d.folder));break;}
    case 'mcpConfig':{const {project_id}=z.object({project_id:key}).parse(args);service.reports(project_id);value=JSON.stringify({mcpServers:{reviset:{command:process.execPath,args:[join(dirname(fileURLToPath(import.meta.url)),'mcp.mjs'),'--store',root,'--project',project_id]}}},null,2);break;}
    default:throw new DocverError('UNKNOWN_ACTION','지원하지 않는 작업입니다.');
  }
  process.stdout.write(JSON.stringify({protocol_version:'0.1.0',schema_version:SCHEMA_VERSION,engine_version:ENGINE_VERSION,ok:true,value})+'\n');
}catch(e){process.stdout.write(JSON.stringify({protocol_version:'0.1.0',schema_version:SCHEMA_VERSION,engine_version:ENGINE_VERSION,ok:false,error:{code:e instanceof DocverError?e.code:'REQUEST_FAILED',message:e instanceof DocverError?e.message:(e as Error).message}})+'\n');process.exitCode=1;}
finally{service.close();}
