import { z } from 'zod';
import { readFile, mkdir } from 'node:fs/promises';
import { join, extname, basename } from 'node:path';
import { randomUUID } from 'node:crypto';
import { Store } from '../storage/index.js';
import { QueryService } from '../query/index.js';
import { analyze, type AnalyzeProgress } from '../engine/index.js';
import { exportReport,type ExportLanguage } from '../export/index.js';
import { renderPdf } from '../render/index.js';
import { byteHash, DocverError, Decision, StoredDecision, MappingRelation,hash,canonical,BundleDecision,type BundleSelectionData,type RelationSelectionData, type InputManifest, type ReportData } from '../schema/index.js';
import { readRegularFile } from '../runtime/regular-file.js';

import {createBundleDecision} from '../bundle/index.js';
import {rewriteMappings} from '../matching/relations.js';
const FileRef=z.object({blob:z.string().regex(/^[a-f0-9]{64}\.(pptx|pdf)$/),name:z.string(),bytes:z.number().int().nonnegative()});
const CommitIdentity=z.object({project_id:z.string(),report_id:z.string(),revisions:z.array(z.object({status:z.enum(['success','partial','failed'])}))});
export const DESKTOP_PROJECTS_TABLE='desktop_projects_v4';
const Draft=z.object({project_id:z.string(),title:z.string().min(1).max(200),revisions:z.array(z.object({label:z.string().min(1).max(200),files:z.array(FileRef).min(1).max(2)})).min(1).max(100),mapping_decisions:z.array(StoredDecision),mapping_relations:z.array(MappingRelation).default([]),bundle_decisions:z.array(BundleDecision).max(10000).default([]),last_report_id:z.string().nullable(),dirty:z.boolean()});
export type DesktopDraft=z.infer<typeof Draft>;
import {publishContent} from '../runtime/atomic-content.js';
export class DesktopService {
  readonly store:Store;
  private snapshots=new Map<string,ReportData>();
  readonly unreadableProjects:{project_id:string;code:'DRAFT_UNREADABLE'}[]=[];
  constructor(readonly root:string) {
    this.store=new Store(root);
    this.store.db.exec(`PRAGMA busy_timeout=5000;
      CREATE TABLE IF NOT EXISTS desktop_projects (id TEXT PRIMARY KEY,body TEXT NOT NULL,updated_at TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS ${DESKTOP_PROJECTS_TABLE} (id TEXT PRIMARY KEY,body TEXT NOT NULL,updated_at TEXT NOT NULL);
      INSERT OR IGNORE INTO ${DESKTOP_PROJECTS_TABLE} SELECT legacy.id,legacy.body,legacy.updated_at FROM desktop_projects legacy WHERE NOT EXISTS (SELECT 1 FROM ${DESKTOP_PROJECTS_TABLE} current_draft WHERE current_draft.id=legacy.id);`);
  }
  projects():DesktopDraft[]{
    this.unreadableProjects.length=0;const projects:DesktopDraft[]=[];
    for(const row of this.store.db.prepare(`SELECT id,body FROM ${DESKTOP_PROJECTS_TABLE} ORDER BY updated_at DESC,id`).all()){
      try{const project=Draft.parse(JSON.parse(String(row.body)));if(project.project_id!==String(row.id))throw new Error('Draft identity mismatch');projects.push(project);}
      catch{this.unreadableProjects.push({project_id:String(row.id),code:'DRAFT_UNREADABLE'});}
    }
    return projects;
  }
  project(projectId:string):DesktopDraft {
    const row=this.store.db.prepare(`SELECT body FROM ${DESKTOP_PROJECTS_TABLE} WHERE id=?`).get(projectId);
    if(!row)throw new DocverError('PROJECT_NOT_FOUND','프로젝트를 찾을 수 없습니다.');
    try{const project=Draft.parse(JSON.parse(String(row.body)));if(project.project_id!==projectId)throw new Error('Draft identity mismatch');return project;}catch{throw new DocverError('DRAFT_UNREADABLE','이 프로젝트의 입력 기록을 읽지 못했습니다. 저장된 원문과 고정 보고서는 보존했습니다. 다른 프로젝트는 계속 사용할 수 있습니다.');}
  }
  private save(project:DesktopDraft){this.store.db.prepare(`INSERT INTO ${DESKTOP_PROJECTS_TABLE} VALUES (?,?,?) ON CONFLICT(id) DO UPDATE SET body=excluded.body,updated_at=excluded.updated_at`).run(project.project_id,JSON.stringify(Draft.parse(project)),new Date().toISOString());return project;}
  recover(runId?:string) {
    if(runId)this.store.db.prepare("UPDATE runs SET status='interrupted',finished_at=? WHERE id=? AND status='running'").run(new Date().toISOString(),runId);
    else this.store.db.prepare(`UPDATE runs SET status='interrupted',finished_at=? WHERE status='running' AND project_id IN (SELECT id FROM ${DESKTOP_PROJECTS_TABLE})`).run(new Date().toISOString());
    return this.projects();
  }
  async create(title:string,revisions:{label:string;files:string[];expected_sha256?:(string|null)[]}[],signal?:AbortSignal):Promise<DesktopDraft> {
    const imported:DesktopDraft['revisions']=[];await mkdir(join(this.root,'imports'),{recursive:true});
    for(const rev of revisions) {
      if(rev.expected_sha256&&(rev.expected_sha256.length!==rev.files.length||rev.expected_sha256.some(v=>v!==null&&!/^[a-f0-9]{64}$/.test(v))))throw new DocverError('INPUT_IDENTITY','선택한 파일의 검증 정보를 확인하세요.');
      const files:z.infer<typeof FileRef>[]=[];
      for(const [index,path] of rev.files.entries()) {
        const ext=extname(path).toLowerCase();
        if(!['.pptx','.pdf'].includes(ext))throw new DocverError('UNSUPPORTED_FORMAT','PPTX 또는 PDF 파일을 선택하세요.');
        const bytes=await readRegularFile(path,{signal});
        const digest=byteHash(bytes);
        if(rev.expected_sha256?.[index]&&rev.expected_sha256[index]!==digest)throw new DocverError('SOURCE_CHANGED',`선택 후 파일 내용이 변경되었습니다: ${basename(path)}. 파일을 다시 선택하세요.`);
        const blob=digest+ext,target=join(this.root,'imports',blob);
        await publishContent(target,bytes,digest);
        files.push({blob,name:basename(path),bytes:bytes.length});
      }
      if(files.length===2&&extname(files[0].blob)===extname(files[1].blob))throw new DocverError('INVALID_BUNDLE','같은 버전은 PPTX와 PDF를 하나씩 묶을 수 있습니다.');
      imported.push({label:rev.label,files});
    }
    signal?.throwIfAborted();return this.save(Draft.parse({project_id:'prj_'+randomUUID().replaceAll('-',''),title,revisions:imported,mapping_decisions:[],last_report_id:null,dirty:true}));
  }
  private projectManifest(p:DesktopDraft):InputManifest {
    return {project_id:p.project_id,title:p.title,revisions:p.revisions.map(r=>({label:r.label,files:r.files.map(f=>join(this.root,'imports',f.blob))})),mapping_decisions:p.mapping_decisions,mapping_relations:p.mapping_relations,bundle_decisions:p.bundle_decisions};
  }
  manifest(projectId:string):InputManifest {return this.projectManifest(this.project(projectId));}
  async run(projectId:string,signal?:AbortSignal,onProgress?:(progress:AnalyzeProgress)=>void,persist=true) {
    const project=this.project(projectId),input=this.projectManifest(project),draft_hash=hash(input),expectedInputSha256=project.revisions.map(revision=>revision.files.map(file=>file.blob.slice(0,64)));
    const result={...await analyze(input,this.root,this.store,signal,onProgress,{persist:false,expectedInputSha256}),draft_hash};
    if(persist){try{this.commit(projectId,result);}catch(e){this.store.failRun(result.analysis_run_id,e instanceof DocverError?e.code:'COMMIT_FAILED');throw e;}}return result;
  }
  commit(projectId:string,result:{report:ReportData;analysis_run_id:string;draft_hash:string}) {
    // Store.finishRun validates and normalizes the complete mutable input at
    // the write boundary. Avoid retaining another full report clone here.
    const report=result.report,identity=CommitIdentity.parse(report);
    const run=this.store.db.prepare('SELECT status FROM runs WHERE id=? AND project_id=?').get(result.analysis_run_id,projectId);
    if(identity.project_id!==projectId||run?.status!=='running')throw new DocverError('INVALID_RUN','분석 실행을 저장할 수 없습니다.');
    this.store.finishRun(result.analysis_run_id,report,identity.revisions.some(r=>r.status!=='success')?'partial':'success',()=>{
      // This check and the latest-pointer update share finishRun's write transaction.
      if(result.draft_hash!==hash(this.manifest(projectId)))throw new DocverError('STALE_RUN','입력이 바뀐 분석 결과는 저장하지 않습니다.');
      const p=this.project(projectId);this.save({...p,last_report_id:identity.report_id,dirty:false});
    });
    return identity.report_id;
  }
  private mutate<T>(operation:()=>T):T {
    this.store.db.exec('BEGIN IMMEDIATE');
    try{const value=operation();this.store.db.exec('COMMIT');return value;}
    catch(error){
      // SQLite may have ended the transaction itself; retain that failure.
      if(this.store.db.isTransaction){
        try{this.store.db.exec('ROLLBACK');}
        catch(rollbackError){throw new AggregateError([error,rollbackError],'Draft operation failed and rollback also failed',{cause:error});}
      }
      throw error;
    }
  }
  reorder(projectId:string,order:number[],discardHumanDecisions=false,expectedDraftHash?:string) {
    return this.mutate(()=>{
      const p=this.project(projectId);
      if(expectedDraftHash!==undefined&&expectedDraftHash!==hash(this.manifest(projectId)))throw new DocverError('STALE_REPORT','입력이나 연결이 바뀌었습니다. 현재 내용을 확인한 뒤 순서를 다시 변경하세요.');
      if(p.dirty&&p.bundle_decisions.length&&canonical(p.bundle_decisions)!==canonical(p.last_report_id?this.snapshot(projectId,p.last_report_id).bundle_decisions??[]:[]))throw new DocverError('PENDING_BUNDLE_DECISIONS','페이지 연결 변경을 먼저 분석한 뒤 버전 순서를 바꾸세요. 기존 보고서는 그대로 보존됩니다.');
      if(p.dirty&&(p.mapping_decisions.length||p.mapping_relations.length)){
        const previous=p.last_report_id?this.snapshot(projectId,p.last_report_id):undefined;
        if(canonical(p.mapping_decisions)!==canonical(previous?.mapping_decisions??[])||canonical(p.mapping_relations)!==canonical(previous?.mapping_relations??[]))throw new DocverError('PENDING_MAPPING_DECISIONS','대응 변경을 먼저 분석한 뒤 버전 순서를 바꾸세요. 입력한 이유와 기존 보고서는 유지됩니다.');
      }
      if(discardHumanDecisions&&!expectedDraftHash)throw new DocverError('REORDER_CONFIRMATION_REQUIRED','현재 입력의 hash를 확인한 순서 변경 요청이 필요합니다.');
      if((p.mapping_decisions.length||p.mapping_relations.length||p.bundle_decisions.length)&&!discardHumanDecisions)throw new DocverError('REORDER_CONFIRMATION_REQUIRED','순서를 바꾸면 현재 입력의 사용자 대응과 제공 PDF 연결 이력이 초기화됩니다. 이전 고정 보고서는 유지됩니다. 내용을 확인하고 순서 변경을 승인하세요.');
      if(order.length!==p.revisions.length||new Set(order).size!==order.length||order.some(n=>!Number.isInteger(n)||n<0||n>=order.length))throw new DocverError('INVALID_ORDER','버전 순서를 확인하세요.');
      return this.save({...p,revisions:order.map(n=>p.revisions[n]),mapping_decisions:[],mapping_relations:[],bundle_decisions:[],dirty:true});
    });
  }
  mapping(projectId:string,reportId:string,decision:z.infer<typeof Decision>) {
    const d=Decision.parse(decision),r=this.snapshot(projectId,reportId),from=r.revisions.find(v=>v.pages.some(p=>p.page_id===d.from_page_id)),to=r.revisions.find(v=>v.pages.some(p=>p.page_id===d.to_page_id));
    if(!from||!to)throw new DocverError('MAPPING_NOT_FOUND','현재 보고서의 페이지를 선택하세요.');
    return this.mappingRelation(projectId,reportId,{kind:'continuation',from_occurrence:from.revision_occurrence_id,to_occurrence:to.revision_occurrence_id,from_page_ids:[d.from_page_id],to_page_ids:[d.to_page_id],reason:d.reason},d.action==='unlink');
  }
  mappingRelation(projectId:string,reportId:string,selection:RelationSelectionData,unlink=false,expectedDraftHash?:string) {
    return this.mutate(()=>{
      const p=this.project(projectId);
      if(p.dirty||p.last_report_id!==reportId||expectedDraftHash!==undefined&&expectedDraftHash!==hash(this.manifest(projectId)))throw new DocverError('STALE_REPORT','최신 분석 결과에서 대응을 수정하세요.');
      const r=this.snapshot(projectId,reportId),next=rewriteMappings(r,p.mapping_decisions,p.mapping_relations,selection,unlink);
      return this.save({...p,...next,dirty:true});
    });
  }
  bundleMapping(projectId:string,reportId:string,selection:BundleSelectionData,expectedDraftHash:string){
    return this.mutate(()=>{
      const project=this.project(projectId);
      if(project.dirty||project.last_report_id!==reportId||expectedDraftHash!==hash(this.manifest(projectId)))throw new DocverError('STALE_REPORT','최신 분석 결과에서 제공 PDF 페이지 연결을 수정하세요. 입력한 사유는 닫기 전까지 유지됩니다.');
      const report=this.snapshot(projectId,reportId),decision=createBundleDecision(report,project.bundle_decisions,selection);
      this.save({...project,bundle_decisions:[...project.bundle_decisions,decision],dirty:true});return {project_id:projectId,decision_id:decision.decision_id,dirty:true,last_report_id:project.last_report_id};
    });
  }
  private requireProjectRecord(projectId:string){if(!this.store.db.prepare(`SELECT 1 FROM ${DESKTOP_PROJECTS_TABLE} WHERE id=?`).get(projectId))throw new DocverError('PROJECT_NOT_FOUND','프로젝트를 찾을 수 없습니다.');}
  queryService(projectId:string){this.requireProjectRecord(projectId);return new QueryService(this.store,new Set([projectId]),(p,r)=>{const key=p+'|'+r;if(r!=='latest'&&this.snapshots.has(key))return this.snapshots.get(key)!;const report=this.store.report(p,r);if(this.snapshots.size>=2)this.snapshots.delete(this.snapshots.keys().next().value!);this.snapshots.set(p+'|'+report.report_id,report);return report;});}
  snapshot(projectId:string,reportId:string):ReportData{return this.queryService(projectId).snapshot(projectId,reportId);}
  pageData(projectId:string,reportId:string,pageId:string){this.requireProjectRecord(projectId);return this.store.nativePage(projectId,reportId,pageId);}
  reports(projectId:string){this.requireProjectRecord(projectId);return this.store.reports(projectId);}
  async preview(projectId:string,reportId:string,pageId:string) {
    const r=this.snapshot(projectId,reportId),revision=r.revisions.find(v=>v.pages.some(p=>p.page_id===pageId)),page=revision?.pages.find(p=>p.page_id===pageId);
    if(!revision||!page)throw new DocverError('PAGE_NOT_FOUND','원문 페이지를 찾을 수 없습니다.');
    const asset=revision.assets.find(a=>a.asset_id===page.asset_id)!;
    if(asset.format==='pdf') {
      const bytes=await readFile(join(this.root,'assets',asset.asset_id.slice(7)));
      if(byteHash(bytes)!==asset.asset_id.slice(7))throw new DocverError('ASSET_CORRUPT','원본 hash가 일치하지 않습니다.');
      const png=await renderPdf(bytes,page.page,1600);return {kind:'pdf' as const,data_url:'data:image/png;base64,'+png.toString('base64')};
    }
    return {kind:'structure' as const,data_url:null};
  }
  async export(projectId:string,reportId:string,folder:string,language:ExportLanguage='ko'){return exportReport(this.queryService(projectId),projectId,reportId,folder,language);}
  close(){this.store.close();}
}
