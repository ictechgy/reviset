import { DatabaseSync } from 'node:sqlite';
import { mkdirSync, writeFileSync, readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { randomUUID } from 'node:crypto';
import { Report, canonical, byteHash, DocverError, type ReportData } from '../schema/index.js';
export class Store {
  readonly db:DatabaseSync;
  readonly root:string;
  constructor(root:string,readonly readOnly=false) {
    this.root=resolve(root);
    const dbPath=join(this.root,'docver.sqlite');
    if(!readOnly) mkdirSync(dirname(dbPath),{recursive:true});
    this.db=new DatabaseSync(dbPath,{readOnly});
    if(readOnly) this.db.exec('PRAGMA query_only=ON;');
    else this.db.exec(`PRAGMA foreign_keys=ON;
      CREATE TABLE IF NOT EXISTS projects (id TEXT PRIMARY KEY,title TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS reports (id TEXT PRIMARY KEY,project_id TEXT NOT NULL REFERENCES projects(id),created_at TEXT NOT NULL,body TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS runs (id TEXT PRIMARY KEY,project_id TEXT NOT NULL REFERENCES projects(id),report_id TEXT REFERENCES reports(id),started_at TEXT NOT NULL,finished_at TEXT,status TEXT NOT NULL,error TEXT);`);
  }
  beginRun(projectId:string,title:string):string {
    this.db.prepare('INSERT INTO projects VALUES (?,?) ON CONFLICT(id) DO UPDATE SET title=excluded.title').run(projectId,title);
    const runId='run_'+randomUUID();
    this.db.prepare('INSERT INTO runs VALUES (?,?,NULL,?,NULL,?,NULL)').run(runId,projectId,new Date().toISOString(),'running');return runId;
  }
  finishRun(runId:string,report:ReportData,status='success') {
    const body=canonical(Report.parse(report));
    this.db.exec('BEGIN IMMEDIATE');
    try {
      const existing=this.db.prepare('SELECT body FROM reports WHERE id=?').get(report.report_id);
      if(existing&&existing.body!==body) throw new DocverError('SNAPSHOT_CONFLICT','Immutable report ID already has different content');
      this.db.prepare('INSERT OR IGNORE INTO reports VALUES (?,?,?,?)').run(report.report_id,report.project_id,new Date().toISOString(),body);
      this.db.prepare('UPDATE runs SET report_id=?,finished_at=?,status=? WHERE id=?').run(report.report_id,new Date().toISOString(),status,runId);
      this.db.exec('COMMIT');
    } catch(e) {this.db.exec('ROLLBACK');throw e;}
  }
  failRun(runId:string,code:string) {this.db.prepare('UPDATE runs SET finished_at=?,status=?,error=? WHERE id=?').run(new Date().toISOString(),'failed',code,runId);}
  putAsset(assetId:string,bytes:Uint8Array) {
    if(this.readOnly) throw new DocverError('READ_ONLY','Store is read-only');
    if(assetId!=='sha256:'+byteHash(bytes)) throw new DocverError('ASSET_HASH','Asset does not match bytes');
    const folder=join(this.root,'assets');mkdirSync(folder,{recursive:true});
    const path=join(folder,assetId.slice(7));
    try { writeFileSync(path,bytes,{flag:'wx'}); } catch(e) {if((e as NodeJS.ErrnoException).code!=='EEXIST') throw e; if(byteHash(readFileSync(path))!==assetId.slice(7)) throw new DocverError('ASSET_CORRUPT','Stored asset hash mismatch');}
  }
  report(projectId:string,reportId:string):ReportData {
    const row=reportId==='latest'?this.db.prepare('SELECT reports.body FROM reports JOIN runs ON runs.report_id=reports.id WHERE reports.project_id=? ORDER BY runs.rowid DESC LIMIT 1').get(projectId):this.db.prepare('SELECT body FROM reports WHERE project_id=? AND id=?').get(projectId,reportId);
    if(!row) throw new DocverError('REPORT_NOT_FOUND','No report in this project scope');
    const parsed=Report.safeParse(JSON.parse(String(row.body)));
    if(!parsed.success)throw new DocverError('SCHEMA_INCOMPATIBLE','Stored snapshot does not match the supported schema; migration is not implemented');
    return parsed.data;
  }
  projects():{project_id:string,title:string}[] {return this.db.prepare('SELECT id AS project_id,title FROM projects ORDER BY id').all() as any;}
  reports(projectId:string) {return this.db.prepare('SELECT id AS report_id,created_at FROM reports WHERE project_id=? ORDER BY rowid').all(projectId);}
  close(){this.db.close();}
}
