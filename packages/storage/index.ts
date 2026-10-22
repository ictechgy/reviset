import { DatabaseSync } from 'node:sqlite';
import { mkdirSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { randomUUID } from 'node:crypto';
import { Report,Page,Asset, canonical, byteHash, DocverError, type ReportData,type RevisionData,type PageData } from '../schema/index.js';
import { z } from 'zod';
import {canonicalJson} from '../runtime/canonical-json.js';
import {publishContentSync} from '../runtime/atomic-content.js';
const NativePage=z.object({page:Page,asset:Asset,reference:Page.pick({asset_id:true,page:true,width:true,height:true,source_transform:true}).optional()});
function pagePayload(report:ReportData,pageId:string):z.infer<typeof NativePage>{
  const revision=report.revisions.find(v=>v.pages.some(p=>p.page_id===pageId)),page=revision?.pages.find(p=>p.page_id===pageId);
  if(!revision||!page)throw new DocverError('PAGE_NOT_FOUND','Page is outside this report');
  return indexedPagePayload(revision,page);
}
function indexedPagePayload(revision:RevisionData,page:PageData,pages=new Map(revision.pages.map(p=>[p.page_id,p])),mapping=new Map(revision.bundle_mapping.map(m=>[m.source_page_id,m.rendered_page_id]))):z.infer<typeof NativePage>{
  const asset=revision.assets.find(a=>a.asset_id===page.asset_id)!;
  const reference=revision.reference_appearance_policy?pages.get(page.appearance?.source_page_id??''):!revision.coverage_gaps.some(g=>g.reason==='bundle_inconsistent')?pages.get(mapping.get(page.page_id)??''):undefined;
  return NativePage.parse({page,asset,reference:reference?{asset_id:reference.asset_id,page:reference.page,width:reference.width,height:reference.height,source_transform:reference.source_transform}:undefined});
}

export class Store {
  readonly db:DatabaseSync;
  readonly root:string;
  constructor(root:string,readonly readOnly=false) {
    this.root=resolve(root);
    const dbPath=join(this.root,'docver.sqlite');
    if(!readOnly) mkdirSync(dirname(dbPath),{recursive:true});
    this.db=new DatabaseSync(dbPath,{readOnly});
    this.db.exec('PRAGMA busy_timeout=5000;');
    if(readOnly) this.db.exec('PRAGMA query_only=ON;');
    else this.db.exec(`PRAGMA foreign_keys=ON;
      CREATE TABLE IF NOT EXISTS projects (id TEXT PRIMARY KEY,title TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS reports (id TEXT PRIMARY KEY,project_id TEXT NOT NULL REFERENCES projects(id),created_at TEXT NOT NULL,body TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS runs (id TEXT PRIMARY KEY,project_id TEXT NOT NULL REFERENCES projects(id),report_id TEXT REFERENCES reports(id),started_at TEXT NOT NULL,finished_at TEXT,status TEXT NOT NULL,error TEXT);
      CREATE TABLE IF NOT EXISTS native_pages (report_id TEXT NOT NULL REFERENCES reports(id),page_id TEXT NOT NULL,body TEXT NOT NULL,PRIMARY KEY(report_id,page_id));`);
  }
  beginRun(projectId:string,title:string):string {
    this.db.prepare('INSERT INTO projects VALUES (?,?) ON CONFLICT(id) DO UPDATE SET title=excluded.title').run(projectId,title);
    const runId='run_'+randomUUID();
    this.db.prepare('INSERT INTO runs VALUES (?,?,NULL,?,NULL,?,NULL)').run(runId,projectId,new Date().toISOString(),'running');return runId;
  }
  finishRun(runId:string,report:ReportData,status='success',onCommit?:()=>void) {
    report=Report.parse(report);
    const body=canonicalJson(report);
    this.db.exec('BEGIN IMMEDIATE');
    try {
      const run=this.db.prepare('SELECT project_id,status FROM runs WHERE id=?').get(runId);
      if(run?.project_id!==report.project_id||run.status!=='running')throw new DocverError('INVALID_RUN','Only an active run in this project may commit');
      const existing=this.db.prepare('SELECT body FROM reports WHERE id=?').get(report.report_id);
      if(existing&&existing.body!==body) throw new DocverError('SNAPSHOT_CONFLICT','Immutable report ID already has different content');
      this.db.prepare('INSERT OR IGNORE INTO reports VALUES (?,?,?,?)').run(report.report_id,report.project_id,new Date().toISOString(),body);
      const insert=this.db.prepare('INSERT OR IGNORE INTO native_pages VALUES (?,?,?)');
      for(const revision of report.revisions){const pages=new Map(revision.pages.map(p=>[p.page_id,p])),mapping=new Map(revision.bundle_mapping.map(m=>[m.source_page_id,m.rendered_page_id]));for(const page of revision.pages)insert.run(report.report_id,page.page_id,canonical(indexedPagePayload(revision,page,pages,mapping)));}
      this.db.prepare('UPDATE runs SET report_id=?,finished_at=?,status=? WHERE id=?').run(report.report_id,new Date().toISOString(),status,runId);
      onCommit?.();
      this.db.exec('COMMIT');
    } catch(e) {
      // SQLite can already have rolled back after a full disk or an I/O error.
      // Preserve that original failure instead of hiding it with ROLLBACK.
      if(this.db.isTransaction){
        try{this.db.exec('ROLLBACK');}
        catch(rollbackError){throw new AggregateError([e,rollbackError],'Storage operation failed and rollback also failed',{cause:e});}
      }
      throw e;
    }
  }
  failRun(runId:string,code:string) {this.db.prepare('UPDATE runs SET finished_at=?,status=?,error=? WHERE id=?').run(new Date().toISOString(),'failed',code,runId);}
  putAsset(assetId:string,bytes:Uint8Array) {
    if(this.readOnly) throw new DocverError('READ_ONLY','Store is read-only');
    if(assetId!=='sha256:'+byteHash(bytes)) throw new DocverError('ASSET_HASH','Asset does not match bytes');
    const folder=join(this.root,'assets');mkdirSync(folder,{recursive:true});
    const path=join(folder,assetId.slice(7));
    publishContentSync(path,bytes,assetId.slice(7));
  }
  report(projectId:string,reportId:string):ReportData {
    return this.reportWithSize(projectId,reportId).report;
  }
  reportWithSize(projectId:string,reportId:string):{report:ReportData;serializedBytes:number} {
    const row=reportId==='latest'?this.db.prepare('SELECT reports.body FROM reports JOIN runs ON runs.report_id=reports.id WHERE reports.project_id=? ORDER BY runs.rowid DESC LIMIT 1').get(projectId):this.db.prepare('SELECT body FROM reports WHERE project_id=? AND id=?').get(projectId,reportId);
    if(!row) throw new DocverError('REPORT_NOT_FOUND','No report in this project scope');
    const body=String(row.body),parsed=Report.safeParse(JSON.parse(body));
    if(!parsed.success)throw new DocverError('SCHEMA_INCOMPATIBLE','Stored snapshot does not match the supported schema; migration is not implemented');
    return {report:parsed.data,serializedBytes:Buffer.byteLength(body)};
  }
  resolveReportId(projectId:string,alias:string):string {
    const row=alias==='latest'?this.db.prepare('SELECT reports.id FROM reports JOIN runs ON runs.report_id=reports.id WHERE reports.project_id=? ORDER BY runs.rowid DESC LIMIT 1').get(projectId):this.db.prepare('SELECT id FROM reports WHERE project_id=? AND id=?').get(projectId,alias);
    if(!row)throw new DocverError('REPORT_NOT_FOUND','No report in this project scope');return String(row.id);
  }
  nativePage(projectId:string,reportId:string,pageId:string):z.infer<typeof NativePage>{
    const indexed=this.db.prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name='native_pages'").get();
    if(indexed){const row=this.db.prepare('SELECT p.body FROM native_pages p JOIN reports r ON r.id=p.report_id WHERE r.project_id=? AND r.id=? AND p.page_id=?').get(projectId,reportId,pageId);if(row)return NativePage.parse(JSON.parse(String(row.body)));}
    return pagePayload(this.report(projectId,reportId),pageId);
  }
  projects():{project_id:string,title:string}[] {return this.db.prepare('SELECT id AS project_id,title FROM projects ORDER BY id').all() as any;}
  reports(projectId:string) {return this.db.prepare('SELECT id AS report_id,created_at FROM reports WHERE project_id=? ORDER BY rowid').all(projectId);}
  close(){this.db.close();}
}
