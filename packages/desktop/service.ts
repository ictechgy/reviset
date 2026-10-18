import { z } from 'zod';
import { readFile, writeFile, mkdir, stat } from 'node:fs/promises';
import { join, extname, basename } from 'node:path';
import { randomUUID } from 'node:crypto';
import { Store } from '../storage/index.js';
import { QueryService } from '../query/index.js';
import { analyze, type AnalyzeProgress } from '../engine/index.js';
import { exportReport } from '../export/index.js';
import { renderPdf } from '../render/index.js';
import { byteHash, DocverError, Report, Decision, type InputManifest, type ReportData } from '../schema/index.js';

const FileRef=z.object({blob:z.string().regex(/^[a-f0-9]{64}\.(pptx|pdf)$/),name:z.string(),bytes:z.number().int().nonnegative()});
const Draft=z.object({project_id:z.string(),title:z.string().min(1).max(200),revisions:z.array(z.object({label:z.string().min(1).max(200),files:z.array(FileRef).min(1).max(2)})).min(1).max(100),mapping_decisions:z.array(Decision),last_report_id:z.string().nullable(),dirty:z.boolean()});
export type DesktopDraft=z.infer<typeof Draft>;
export class DesktopService {
  readonly store:Store;
  private snapshots=new Map<string,ReportData>();
  constructor(readonly root:string) {
    this.store=new Store(root);
    this.store.db.exec('PRAGMA busy_timeout=5000; CREATE TABLE IF NOT EXISTS desktop_projects (id TEXT PRIMARY KEY,body TEXT NOT NULL,updated_at TEXT NOT NULL)');
  }
  projects():DesktopDraft[]{return this.store.db.prepare('SELECT body FROM desktop_projects ORDER BY updated_at DESC,id').all().map(r=>Draft.parse(JSON.parse(String(r.body))));}
  project(projectId:string):DesktopDraft {
    const row=this.store.db.prepare('SELECT body FROM desktop_projects WHERE id=?').get(projectId);
    if(!row)throw new DocverError('PROJECT_NOT_FOUND','프로젝트를 찾을 수 없습니다.');return Draft.parse(JSON.parse(String(row.body)));
  }
  private save(project:DesktopDraft){this.store.db.prepare('INSERT INTO desktop_projects VALUES (?,?,?) ON CONFLICT(id) DO UPDATE SET body=excluded.body,updated_at=excluded.updated_at').run(project.project_id,JSON.stringify(Draft.parse(project)),new Date().toISOString());return project;}
  recover(runId?:string) {
    if(runId)this.store.db.prepare("UPDATE runs SET status='interrupted',finished_at=? WHERE id=? AND status='running'").run(new Date().toISOString(),runId);
    else this.store.db.prepare("UPDATE runs SET status='interrupted',finished_at=? WHERE status='running' AND project_id IN (SELECT id FROM desktop_projects)").run(new Date().toISOString());
    return this.projects();
  }
  async create(title:string,revisions:{label:string;files:string[]}[]):Promise<DesktopDraft> {
    const imported:DesktopDraft['revisions']=[];await mkdir(join(this.root,'imports'),{recursive:true});
    for(const rev of revisions) {
      const files:z.infer<typeof FileRef>[]=[];
      for(const path of rev.files) {
        const ext=extname(path).toLowerCase();
        if(!['.pptx','.pdf'].includes(ext))throw new DocverError('UNSUPPORTED_FORMAT','PPTX 또는 PDF 파일을 선택하세요.');
        const size=(await stat(path)).size;if(size>50*1024*1024)throw new DocverError('FILE_LIMIT','파일당 50 MiB 이하를 지원합니다.');
        const bytes=await readFile(path);if(bytes.length>50*1024*1024)throw new DocverError('FILE_LIMIT','파일 크기가 가져오기 한도를 넘었습니다.');
        const blob=byteHash(bytes)+ext,target=join(this.root,'imports',blob);
        try{await writeFile(target,bytes,{flag:'wx'});}catch(e){if((e as NodeJS.ErrnoException).code!=='EEXIST')throw e;if(byteHash(await readFile(target))!==byteHash(bytes))throw new DocverError('ASSET_CORRUPT','가져온 원본의 검증에 실패했습니다.');}
        files.push({blob,name:basename(path),bytes:bytes.length});
      }
      if(files.length===2&&extname(files[0].blob)===extname(files[1].blob))throw new DocverError('INVALID_BUNDLE','같은 버전은 PPTX와 PDF를 하나씩 묶을 수 있습니다.');
      imported.push({label:rev.label,files});
    }
    return this.save(Draft.parse({project_id:'prj_'+randomUUID().replaceAll('-',''),title,revisions:imported,mapping_decisions:[],last_report_id:null,dirty:true}));
  }
  manifest(projectId:string):InputManifest {
    const p=this.project(projectId);return {project_id:p.project_id,title:p.title,revisions:p.revisions.map(r=>({label:r.label,files:r.files.map(f=>join(this.root,'imports',f.blob))})),mapping_decisions:p.mapping_decisions};
  }
  async run(projectId:string,signal?:AbortSignal,onProgress?:(progress:AnalyzeProgress)=>void,persist=true) {
    const result=await analyze(this.manifest(projectId),this.root,this.store,signal,onProgress,{persist});
    // A committed report stays immutable. Only the project's latest pointer changes.
    if(persist){const p=this.project(projectId);this.save({...p,last_report_id:result.report.report_id,dirty:false});}return result;
  }
  commit(projectId:string,result:{report:ReportData;analysis_run_id:string}) {
    const report=Report.parse(result.report),p=this.project(projectId);
    const run=this.store.db.prepare('SELECT status FROM runs WHERE id=? AND project_id=?').get(result.analysis_run_id,projectId);
    if(report.project_id!==projectId||run?.status!=='running')throw new DocverError('INVALID_RUN','분석 실행을 저장할 수 없습니다.');
    this.store.finishRun(result.analysis_run_id,report,report.revisions.some(r=>r.status!=='success')?'partial':'success',()=>this.save({...p,last_report_id:report.report_id,dirty:false}));
    return report.report_id;
  }
  reorder(projectId:string,order:number[]) {
    const p=this.project(projectId);
    if(order.length!==p.revisions.length||new Set(order).size!==order.length||order.some(n=>!Number.isInteger(n)||n<0||n>=order.length))throw new DocverError('INVALID_ORDER','버전 순서를 확인하세요.');
    return this.save({...p,revisions:order.map(n=>p.revisions[n]),mapping_decisions:[],dirty:true});
  }
  mapping(projectId:string,reportId:string,decision:z.infer<typeof Decision>) {
    const p=this.project(projectId);if(p.dirty||p.last_report_id!==reportId)throw new DocverError('STALE_REPORT','최신 분석 결과에서 대응을 수정하세요.');
    const r=this.snapshot(projectId,reportId),d=Decision.parse(decision);
    const from=r.revisions.findIndex(v=>v.pages.some(page=>page.page_id===d.from_page_id)),to=r.revisions.findIndex(v=>v.pages.some(page=>page.page_id===d.to_page_id));
    if(from<0||to!==from+1)throw new DocverError('MAPPING_INTERVAL','인접 버전의 페이지를 선택하세요.');
    const next=p.mapping_decisions.filter(old=>!(old.from_page_id===d.from_page_id&&old.to_page_id===d.to_page_id));
    if(d.action==='link') {
      // Replacing a link explicitly unlinks competing inferred/manual pairs.
      for(const m of r.matches.filter(m=>(m.from_page_id===d.from_page_id||m.to_page_id===d.to_page_id)&&!(m.from_page_id===d.from_page_id&&m.to_page_id===d.to_page_id)))
        if(!next.some(n=>n.action==='unlink'&&n.from_page_id===m.from_page_id&&n.to_page_id===m.to_page_id))next.push({from_page_id:m.from_page_id,to_page_id:m.to_page_id,action:'unlink',reason:d.reason});
      for(let i=next.length-1;i>=0;i--)if(next[i].action==='link'&&(next[i].from_page_id===d.from_page_id||next[i].to_page_id===d.to_page_id))next.splice(i,1);
    }
    next.push(d);return this.save({...p,mapping_decisions:next,dirty:true});
  }
  queryService(projectId:string){this.project(projectId);return new QueryService(this.store,new Set([projectId]),(p,r)=>{const key=p+'|'+r;if(r!=='latest'&&this.snapshots.has(key))return this.snapshots.get(key)!;const report=this.store.report(p,r);if(this.snapshots.size>=2)this.snapshots.delete(this.snapshots.keys().next().value!);this.snapshots.set(p+'|'+report.report_id,report);return report;});}
  snapshot(projectId:string,reportId:string):ReportData{return this.queryService(projectId).snapshot(projectId,reportId);}
  reports(projectId:string){this.project(projectId);return this.store.reports(projectId);}
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
  async export(projectId:string,reportId:string,folder:string){return exportReport(this.queryService(projectId),projectId,reportId,folder);}
  close(){this.store.close();}
}
