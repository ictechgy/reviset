import { readFileSync,createReadStream } from 'node:fs';
import { createHash } from 'node:crypto';
import { mkdir,writeFile,readFile,rm,readdir } from 'node:fs/promises';
import { dirname,join,resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { z } from 'zod';
import { DesktopService } from '../../packages/desktop/service.js';
import { DocverError, Decision, RelationSelection, byteHash, hash,comparisonText,textChunk,unresolvedComparisonText, SCHEMA_VERSION, ENGINE_VERSION } from '../../packages/schema/index.js';
import { querySchemas } from '../../packages/query/index.js';
const key=z.string().regex(/^[a-zA-Z0-9_-]{1,160}$/),scope=z.object({project_id:key,report_id:key});
const request=JSON.parse(readFileSync(0,'utf8')) as {action:string;args:any};
const rootArg=process.argv.indexOf('--root');if(rootArg<0)throw new Error('Explicit app library required');
const root=resolve(process.argv[rootArg+1]),service=new DesktopService(root),args=request.args??{};
async function verifiedSource(assetId:string):Promise<string>{
  if(!/^sha256:[a-f0-9]{64}$/.test(assetId))throw new DocverError('ASSET_ID','잘못된 원본 ID입니다.');
  const path=join(root,'assets',assetId.slice(7)),digest=createHash('sha256');for await(const chunk of createReadStream(path,{highWaterMark:1024*1024}))digest.update(chunk);
  if(digest.digest('hex')!==assetId.slice(7))throw new DocverError('ASSET_CORRUPT','표시할 원본의 hash가 일치하지 않습니다.');return path;
}
try{
  let value:unknown;
  switch(request.action){
    case 'projects':value=service.projects();break;
    case 'recover':{const d=z.object({run_id:z.string().optional()}).parse(args);value=service.recover(d.run_id);const folder=join(root,'staging');try{for(const name of await readdir(folder))if(/^run_[a-f0-9-]+\.json$/.test(name)&&(!d.run_id||name===d.run_id+'.json'))await rm(join(folder,name));}catch(e){if((e as NodeJS.ErrnoException).code!=='ENOENT')throw e;}break;}
    case 'create':{const data=z.object({title:z.string().trim().min(1).max(200),revisions:z.array(z.object({label:z.string().trim().min(1).max(200),files:z.array(z.string()).min(1).max(2)})).min(1).max(100)}).parse(args);value=await service.create(data.title,data.revisions);break;}
    case 'analyze':{const {project_id}=z.object({project_id:key}).parse(args);const result=await service.run(project_id,undefined,p=>process.stderr.write(JSON.stringify({event:'progress',progress:p})+'\n'),false);const data=Buffer.from(JSON.stringify(result.report));const folder=join(root,'staging');await mkdir(folder,{recursive:true,mode:0o700});const name=result.analysis_run_id+'.json';await writeFile(join(folder,name),data,{flag:'wx',mode:0o600});value={analysis_run_id:result.analysis_run_id,report_id:result.report.report_id,staged_name:name,sha256:byteHash(data),draft_hash:result.draft_hash,project_id,schema_version:SCHEMA_VERSION,engine_version:ENGINE_VERSION};break;}
    case 'commit':{const {project_id}=z.object({project_id:key}).parse(args);const d=z.object({analysis_run_id:z.string().regex(/^run_[a-f0-9-]+$/),report_id:key,staged_name:z.string().regex(/^run_[a-f0-9-]+\.json$/),sha256:z.string().regex(/^[a-f0-9]{64}$/),draft_hash:z.string(),project_id:key,schema_version:z.literal(SCHEMA_VERSION),engine_version:z.literal(ENGINE_VERSION)}).parse(args.result);if(d.project_id!==project_id||d.staged_name!==d.analysis_run_id+'.json'||d.draft_hash!==hash(service.manifest(project_id)))throw new DocverError('STALE_RUN','입력이 바뀐 분석 결과는 저장하지 않습니다.');const path=join(root,'staging',d.staged_name),data=await readFile(path);if(byteHash(data)!==d.sha256)throw new DocverError('STAGED_HASH','분석 결과 hash 검증에 실패했습니다.');const report=JSON.parse(data.toString('utf8'));if(report.report_id!==d.report_id)throw new DocverError('STAGED_ID','분석 보고서 ID가 일치하지 않습니다.');value=service.commit(project_id,{report,analysis_run_id:d.analysis_run_id,draft_hash:d.draft_hash});await rm(path);break;}
    case 'reorder':{const d=z.object({project_id:key,order:z.array(z.number().int())}).parse(args);value=service.reorder(d.project_id,d.order);break;}
    case 'mapping':{const d=scope.extend({decision:Decision}).parse(args);value=service.mapping(d.project_id,d.report_id,d.decision);break;}
    case 'mappingRelation':{const d=scope.extend({selection:RelationSelection,unlink:z.boolean().default(false),draft_hash:z.string().regex(/^[a-f0-9]{64}$/)}).parse(args);value=service.mappingRelation(d.project_id,d.report_id,d.selection,d.unlink,d.draft_hash);break;}
    case 'reports':value=service.reports(z.object({project_id:key}).parse(args).project_id);break;
    case 'changes':{const d=querySchemas.list_changes.parse(args);value=service.queryService(d.project_id).changeSet(d);break;}
    case 'view':{
      const d=scope.parse(args),r=service.snapshot(d.project_id,d.report_id);
      const revisions=r.revisions.map(({pages,...v})=>({...v,pages:pages.map(p=>({page_id:p.page_id,asset_id:p.asset_id,page:p.page,width:p.width,height:p.height,text:textChunk(comparisonText(p),0,180),capabilities:p.capabilities,hidden:p.hidden,ocr:p.ocr,coverage_gaps:p.coverage_gaps.slice(0,3)}))}));
      const all=r.revisions.flatMap(v=>v.pages),quality_counts={ocr_inferred_pages:all.filter(p=>p.elements.some(e=>e.method==='vision_ocr')).length,ocr_failed_pages:all.filter(p=>p.ocr&&['failed','unavailable'].includes(p.ocr.status)).length,unresolved_comparison_pages:all.filter(p=>!!unresolvedComparisonText(p)||!!p.ocr_unresolved_text).length,pptx_without_render:all.filter(p=>!p.preview&&r.revisions.some(v=>v.assets.some(a=>a.asset_id===p.asset_id&&a.format==='pptx'))).length};
      value={...r,revisions,quality_counts,draft_hash:hash(service.manifest(d.project_id)),changes:undefined,candidates:undefined,matches:r.matches.map(({from_page_id,to_page_id,relation_id,relation_kind,status})=>({from_page_id,to_page_id,relation_id,relation_kind,status})),coverage_gaps:r.coverage_gaps.slice(0,500),coverage_gap_count:r.coverage_gaps.length,change_counts:r.changes.reduce<Record<string,number>>((a,c)=>(a[c.kind]=(a[c.kind]??0)+1,a),{})};break;
    }
    case 'page':{
      const d=scope.extend({page_id:key}).parse(args),{page,asset,reference}=service.pageData(d.project_id,d.report_id,d.page_id);
      if(reference){
        const path=await verifiedSource(reference.asset_id);
        value={page,display_page:reference,source:{kind:'pdf',origin:'reference_pdf',path,renderer:'Imported reference PDF',warnings:[]},display_page_number:reference.page};
      }else if(page.preview){
        const previewPath=await verifiedSource(page.preview.asset_id);
        value={page,display_page:{...page,width:page.preview.width,height:page.preview.height,source_transform:page.preview.source_transform},source:{kind:'pdf',origin:'pptx_converted',path:previewPath,renderer:page.preview.renderer,warnings:page.preview.warnings}};
      }else value={page,display_page:page,source:{kind:asset.format,path:await verifiedSource(asset.asset_id),origin:'original'}};break;
    }
    case 'export':{const d=scope.extend({folder:z.string().min(1)}).parse(args);value=await service.export(d.project_id,d.report_id,resolve(d.folder));break;}
    case 'mcpConfig':{const {project_id}=z.object({project_id:key}).parse(args);service.project(project_id);value=JSON.stringify({mcpServers:{docver:{command:process.execPath,args:[join(dirname(fileURLToPath(import.meta.url)),'mcp.mjs'),'--store',root,'--project',project_id]}}},null,2);break;}
    default:throw new DocverError('UNKNOWN_ACTION','지원하지 않는 작업입니다.');
  }
  process.stdout.write(JSON.stringify({protocol_version:'0.1.0',schema_version:SCHEMA_VERSION,engine_version:ENGINE_VERSION,ok:true,value})+'\n');
}catch(e){process.stdout.write(JSON.stringify({protocol_version:'0.1.0',schema_version:SCHEMA_VERSION,engine_version:ENGINE_VERSION,ok:false,error:{code:e instanceof DocverError?e.code:'REQUEST_FAILED',message:e instanceof DocverError?e.message:(e as Error).message}})+'\n');process.exitCode=1;}
finally{service.close();}
