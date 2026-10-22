import { randomUUID, createHash } from 'node:crypto';
import { constants, mkdirSync } from 'node:fs';
import { open, writeFile, mkdir, rm, readdir } from 'node:fs/promises';
import { basename, extname, join, resolve } from 'node:path';
import { z } from 'zod';
import { Store } from '../storage/index.js';
import { canonical, byteHash, hash, DocverError } from '../schema/index.js';
import { publishContent } from '../runtime/atomic-content.js';
import { WorkbookFormat, WorkbookObservation, WorkbookCell, workbookID, WORKBOOK_SCHEMA_VERSION, WORKBOOK_ENGINE_VERSION } from './types.js';
import { blankCellsInViewport, validateBlankRangeLayout } from './sparse.js';
import { extractWorkbook } from './ingest.js';
import { diffWorkbooks, WorkbookReport, WorkbookChange, type WorkbookReportData, type WorkbookRevisionData } from './diff.js';

const key = z.string().regex(/^[a-zA-Z0-9_-]{1,160}$/);
const sha = z.string().regex(/^[a-f0-9]{64}$/);
const revisionInput = z.object({ label: z.string().trim().min(1).max(200), path: z.string().min(1).max(4096), expected_sha256: sha.optional() });
const Draft = z.object({ project_id: z.string().regex(/^wprj_[a-zA-Z0-9_-]+$/), title: z.string().trim().min(1).max(200), created_at: z.string(), revisions: z.array(z.object({ label: z.string().min(1).max(200), asset_id: z.string().regex(/^sha256:[a-f0-9]{64}$/), format: WorkbookFormat, source_name: z.string().max(255) })).min(1).max(100) });
export const WorkbookStage = z.object({ project_id: key, analysis_run_id: z.string().regex(/^wrun_[a-f0-9-]+$/), report_id: z.string().regex(/^wreport_[a-f0-9]{64}$/), staged_name: z.string().regex(/^wrun_[a-f0-9-]+\.json$/), sha256: sha, draft_hash: sha, schema_version: z.literal(WORKBOOK_SCHEMA_VERSION), engine_version: z.literal(WORKBOOK_ENGINE_VERSION) });
type WorkbookStageData = z.infer<typeof WorkbookStage>;
export const MAX_WORKBOOK_INPUT_BYTES = 64 * 1024 * 1024;
export const MAX_WORKBOOK_REPORT_BYTES = 256 * 1024 * 1024;
const NOT_FOUND = () => new DocverError('WORKBOOK_PROJECT_NOT_FOUND', 'Workbook project is outside this library or scope');
const reportLimit = () => new DocverError('WORKBOOK_REPORT_LIMIT', 'Serialized workbook report exceeds 256 MiB; no partial result is committed');
function reportSerialization<T>(serialize:()=>T):T {
  try{return serialize();}catch(error){if(error instanceof RangeError)throw reportLimit();throw error;}
}

async function regularFile(path: string, expected?: string, maxBytes=MAX_WORKBOOK_INPUT_BYTES): Promise<Buffer> {
  let handle; try {
    // A FIFO must not block open before we can reject its descriptor type.
    handle = await open(path, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK); const stat = await handle.stat();
    if (!stat.isFile() || stat.size > maxBytes) throw new DocverError('WORKBOOK_INPUT_LIMIT', `Workbook source/stage must be a regular file of at most ${maxBytes/(1024*1024)} MiB`);
    const chunks: Buffer[] = []; let size = 0; const digest = createHash('sha256');
    for await (const chunk of handle.createReadStream({ autoClose: false, highWaterMark: 1024 * 1024 })) { size += chunk.length; if (size > maxBytes) throw new DocverError('WORKBOOK_INPUT_LIMIT', `Workbook source/stage grew beyond ${maxBytes/(1024*1024)} MiB`); chunks.push(chunk); digest.update(chunk); }
    if (expected && digest.digest('hex') !== expected) throw new DocverError('ASSET_CORRUPT', 'Workbook source SHA-256 does not match; original is not analyzed');
    return Buffer.concat(chunks);
  } finally { await handle?.close(); }
}

export class WorkbookService {
  constructor(readonly store: Store) {
    if (!store.readOnly) store.db.exec(`
      CREATE TABLE IF NOT EXISTS workbook_projects_v1 (id TEXT PRIMARY KEY,title TEXT NOT NULL,created_at TEXT NOT NULL,body TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS workbook_reports_v1 (id TEXT PRIMARY KEY,project_id TEXT NOT NULL REFERENCES workbook_projects_v1(id),created_at TEXT NOT NULL,body TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS workbook_runs_v1 (id TEXT PRIMARY KEY,project_id TEXT NOT NULL REFERENCES workbook_projects_v1(id),report_id TEXT,started_at TEXT NOT NULL,finished_at TEXT,status TEXT NOT NULL,error TEXT,draft_hash TEXT NOT NULL,staged_sha TEXT);
      CREATE TABLE IF NOT EXISTS workbook_releases_v1 (id TEXT PRIMARY KEY,project_id TEXT NOT NULL REFERENCES workbook_projects_v1(id),report_id TEXT NOT NULL REFERENCES workbook_reports_v1(id),recorded_at TEXT NOT NULL,body TEXT NOT NULL);
      CREATE INDEX IF NOT EXISTS workbook_reports_project_v1 ON workbook_reports_v1(project_id);
      CREATE INDEX IF NOT EXISTS workbook_runs_project_v1 ON workbook_runs_v1(project_id);
      CREATE TABLE IF NOT EXISTS workbook_metadata_v1 (report_id TEXT PRIMARY KEY REFERENCES workbook_reports_v1(id),project_id TEXT NOT NULL,body TEXT NOT NULL,body_sha TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS workbook_cells_v1 (report_id TEXT NOT NULL REFERENCES workbook_reports_v1(id),revision_occurrence_id TEXT NOT NULL,sheet_id TEXT NOT NULL,row INTEGER NOT NULL,col INTEGER NOT NULL,body TEXT NOT NULL,body_sha TEXT NOT NULL,PRIMARY KEY(report_id,revision_occurrence_id,sheet_id,row,col));
      CREATE TABLE IF NOT EXISTS workbook_changes_v1 (report_id TEXT NOT NULL REFERENCES workbook_reports_v1(id),change_id TEXT NOT NULL,from_revision TEXT NOT NULL,to_revision TEXT NOT NULL,position INTEGER NOT NULL,body TEXT NOT NULL,body_sha TEXT NOT NULL,PRIMARY KEY(report_id,change_id));
      CREATE INDEX IF NOT EXISTS workbook_changes_interval_v1 ON workbook_changes_v1(report_id,to_revision,position);
    `);
  }
  private writable() { if (this.store.readOnly) throw new DocverError('READ_ONLY', 'Workbook mutations require the application library writer'); }
  private present() { return !!this.store.db.prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name='workbook_projects_v1'").get(); }
  project(projectId: string) {
    if (!/^wprj_[a-zA-Z0-9_-]+$/.test(projectId) || !this.present()) throw NOT_FOUND();
    const row = this.store.db.prepare('SELECT body FROM workbook_projects_v1 WHERE id=?').get(projectId); if (!row) throw NOT_FOUND();
    try { const draft = Draft.parse(JSON.parse(String(row.body))); if (draft.project_id !== projectId) throw new Error('scope'); return draft; }
    catch { throw new DocverError('WORKBOOK_DRAFT_UNREADABLE', 'Workbook input record is damaged; existing fixed reports remain available'); }
  }
  projects() {
    if (!this.present()) return [];
    return this.store.db.prepare('SELECT id,title,created_at,body FROM workbook_projects_v1 ORDER BY rowid DESC').all().map(row => {
      let revisions: z.infer<typeof Draft>['revisions'] = [], unreadable = false; try { revisions = Draft.parse(JSON.parse(String(row.body))).revisions; } catch { unreadable = true; }
      const last = this.store.db.prepare("SELECT report_id FROM workbook_runs_v1 WHERE project_id=? AND status='success' ORDER BY rowid DESC LIMIT 1").get(row.id);
      return { project_id: String(row.id), title: String(row.title), created_at: String(row.created_at), revision_count: revisions.length, revisions: revisions.map(({ source_name: _source, ...v }) => v), last_report_id: last?.report_id ?? null, unreadable };
    });
  }
  async create(title: string, inputs: unknown) {
    this.writable(); const revisions = z.array(revisionInput).min(1).max(100).parse(inputs); title = z.string().trim().min(1).max(200).parse(title);
    const loaded: z.infer<typeof Draft>['revisions'] = [];
    for (const input of revisions) {
      const format = WorkbookFormat.safeParse(extname(input.path).slice(1).toLowerCase()); if (!format.success) throw new DocverError('WORKBOOK_FORMAT', 'Only XLSX, ODS and UTF-8 comma-delimited CSV are supported');
      const bytes = await regularFile(resolve(input.path), input.expected_sha256), asset_id = 'sha256:' + byteHash(bytes); this.store.putAsset(asset_id, bytes);
      loaded.push({ label: input.label, asset_id, format: format.data, source_name: basename(input.path).slice(0, 255) });
    }
    const draft = Draft.parse({ project_id: 'wprj_' + randomUUID(), title, created_at: new Date().toISOString(), revisions: loaded });
    this.store.db.prepare('INSERT INTO workbook_projects_v1 VALUES (?,?,?,?)').run(draft.project_id, title, draft.created_at, canonical(draft));
    return { ...draft, revision_count: loaded.length, last_report_id: null };
  }
  reports(projectId: string) {
    this.requireProject(projectId);
    return this.store.db.prepare('SELECT r.id,r.created_at,m.body,m.body_sha FROM workbook_reports_v1 r JOIN workbook_metadata_v1 m ON m.report_id=r.id AND m.project_id=r.project_id WHERE r.project_id=? ORDER BY r.rowid DESC').all(projectId).map(row => {const body=String(row.body);if(hash({project_id:projectId,report_id:String(row.id),body})!==row.body_sha)throw new DocverError('WORKBOOK_INDEX_CORRUPT','Workbook report count metadata is damaged');const metadata=JSON.parse(body);return { report_id: String(row.id), created_at: String(row.created_at), revision_count: metadata.revisions.length, change_count: metadata.change_count };});
  }
  requireProject(projectId: string) { if (!this.present() || !/^wprj_[a-zA-Z0-9_-]+$/.test(projectId) || !this.store.db.prepare('SELECT 1 FROM workbook_projects_v1 WHERE id=?').get(projectId)) throw NOT_FOUND(); }
  resolveReportId(projectId: string, reportId: string) {
    this.requireProject(projectId); const row = reportId === 'latest'
      ? this.store.db.prepare("SELECT report_id AS id FROM workbook_runs_v1 WHERE project_id=? AND status='success' ORDER BY rowid DESC LIMIT 1").get(projectId)
      : this.store.db.prepare('SELECT id FROM workbook_reports_v1 WHERE id=? AND project_id=?').get(reportId, projectId);
    if (!row) throw new DocverError('WORKBOOK_REPORT_NOT_FOUND', 'No fixed workbook report exists in this project'); return String(row.id);
  }
  report(projectId: string, reportId: string): WorkbookReportData {
    const fixed = this.resolveReportId(projectId, reportId), row = this.store.db.prepare('SELECT body FROM workbook_reports_v1 WHERE id=? AND project_id=?').get(fixed, projectId)!;
    try {
      const text = String(row.body); if (Buffer.byteLength(text) > MAX_WORKBOOK_REPORT_BYTES) throw new Error('budget');
      const report = WorkbookReport.parse(JSON.parse(text)); validateIdentity(report); if (report.project_id !== projectId || report.report_id !== fixed) throw new Error('scope'); return report;
    } catch { throw new DocverError('WORKBOOK_REPORT_CORRUPT', 'Stored workbook report failed schema, identity or scope validation'); }
  }
  metadata(projectId: string, reportId: string): WorkbookReportData & { change_count: number } {
    const fixed = this.resolveReportId(projectId, reportId), row = this.store.db.prepare('SELECT body,body_sha FROM workbook_metadata_v1 WHERE report_id=? AND project_id=?').get(fixed, projectId);
    if (!row) { const full = this.report(projectId, fixed); return { ...full, change_count: full.changes.length }; }
    try { if(hash({project_id:projectId,report_id:fixed,body:String(row.body)})!==row.body_sha)throw new Error('hash');const raw = JSON.parse(String(row.body)), data = WorkbookReport.parse(raw); if (data.project_id !== projectId || data.report_id !== fixed || !Number.isSafeInteger(raw.change_count)) throw new Error('scope');
      for (const [i,r] of data.revisions.entries()) for (const [j,s] of r.sheets.entries()) { const n = raw.revisions[i].sheets[j].cell_count; if (!Number.isSafeInteger(n) || n < 0 || n > 500_000) throw new Error('count'); Object.assign(s, { cell_count: n }); }
      return { ...data, change_count: raw.change_count }; }
    catch { throw new DocverError('WORKBOOK_INDEX_CORRUPT', 'Workbook sparse index metadata is damaged'); }
  }
  indexedCells(projectId: string, reportId: string, occurrence: string, sheetId: string, rowStart: number, rowEnd: number, columnStart: number, columnEnd: number,source?:WorkbookReportData,expandStyles=true,includeBlankRanges=true) {
    this.resolveReportId(projectId, reportId);
    const metadata=source??this.metadata(projectId,reportId),revision=metadata.revisions.find(r=>r.revision_occurrence_id===occurrence);if(metadata.project_id!==projectId||metadata.report_id!==reportId||!revision?.sheets.some(s=>s.sheet_id===sheetId))throw new DocverError('WORKBOOK_SHEET_SCOPE','Cell index is outside this fixed report/occurrence');const styles=new Map<string,Record<string,string>>();
    const cells = this.store.db.prepare('SELECT row,col,body,body_sha FROM workbook_cells_v1 WHERE report_id=? AND revision_occurrence_id=? AND sheet_id=? AND row>=? AND row<? AND col>=? AND col<? ORDER BY row,col').all(reportId, occurrence, sheetId, rowStart, rowEnd, columnStart, columnEnd).map(row => { const body=String(row.body);if(hash({report_id:reportId,occurrence,sheet_id:sheetId,row:row.row,column:row.col,body})!==row.body_sha)throw new DocverError('WORKBOOK_INDEX_CORRUPT','Sparse cell index hash is damaged');const c = WorkbookCell.parse(JSON.parse(body)); if (c.row !== row.row || c.column !== row.col) throw new DocverError('WORKBOOK_INDEX_CORRUPT', 'Sparse cell index coordinates do not match their source observation');if(c.style_ref){let style=styles.get(c.style_ref);if(!style){style=revision.style_definitions?.[c.style_ref];if(!style||workbookID('wstyle',style)!==c.style_ref)throw new DocverError('WORKBOOK_STYLE_SCOPE','Sparse cell style definition is missing or damaged');styles.set(c.style_ref,style);}return expandStyles?{...c,style}:c;} return c; });
    if(includeBlankRanges){const sheet=revision.sheets.find(s=>s.sheet_id===sheetId)!;for(const cell of blankCellsInViewport(sheet,rowStart,rowEnd,columnStart,columnEnd)){if(cell.style_ref){let style=styles.get(cell.style_ref);if(!style){style=revision.style_definitions?.[cell.style_ref];if(!style||workbookID('wstyle',style)!==cell.style_ref)throw new DocverError('WORKBOOK_STYLE_SCOPE','Blank range style definition is missing or damaged');styles.set(cell.style_ref,style);}if(expandStyles)cell.style=style;}cells.push(cell);}cells.sort((a,b)=>a.row-b.row||a.column-b.column);}
    return cells;
  }
  indexedChanges(projectId: string, reportId: string, toOccurrences: string[],changeId?:string) {
    this.resolveReportId(projectId, reportId);if(!toOccurrences.length)return[];if(toOccurrences.length>100)throw new DocverError('WORKBOOK_RANGE_SCOPE','Too many interval occurrences');
    const sql='SELECT change_id,from_revision,to_revision,position,body,body_sha FROM workbook_changes_v1 WHERE report_id=? AND to_revision IN ('+toOccurrences.map(()=>'?').join(',')+')'+(changeId?' AND change_id=?':'')+' ORDER BY position';
    return this.store.db.prepare(sql).all(reportId,...toOccurrences,...(changeId?[changeId]:[])).map(row => {const body=String(row.body);if(hash({report_id:reportId,position:row.position,body})!==row.body_sha)throw new DocverError('WORKBOOK_INDEX_CORRUPT','Change index hash is damaged');const c=WorkbookChange.parse(JSON.parse(body));if(c.change_id!==row.change_id||c.from_revision_occurrence_id!==row.from_revision||c.to_revision_occurrence_id!==row.to_revision)throw new DocverError('WORKBOOK_INDEX_CORRUPT','Change index scope is damaged');return c;});
  }
  view(projectId: string, reportId: string) {
    const report = this.metadata(projectId, reportId); const { changes: _changes, revisions, change_count, ...rest } = report;
    const created = this.store.db.prepare('SELECT created_at FROM workbook_reports_v1 WHERE id=?').get(report.report_id);
    return { ...rest, coverage_gaps:rest.coverage_gaps.slice(0,50),coverage_gap_count:rest.coverage_gaps.length,coverage_truncated:rest.coverage_gaps.length>50,coverage_query:'list_workbook_coverage_gaps', created_at: created?.created_at, change_count, revisions: revisions.map(({ sheets, coverage_gaps,style_definitions:_styleDefinitions, ...r }) => ({ ...r, coverage_gaps: coverage_gaps.slice(0, 10), coverage_gap_count: coverage_gaps.length, sheets: sheets.map(({ cells, blank_style_ranges, ...s }) => ({ ...s, blank_style_range_count:blank_style_ranges?.length??0,blank_style_range_query:"list_workbook_formatting_ranges", merges:s.merges.slice(0,10),merge_count:s.merges.length,row_metadata:s.row_metadata.slice(0,10),row_metadata_count:s.row_metadata.length,column_metadata:s.column_metadata.slice(0,10),column_metadata_count:s.column_metadata.length,coverage_gaps:s.coverage_gaps.slice(0,10),coverage_gap_count:s.coverage_gaps.length,metadata_truncated:Math.max(s.merges.length,s.row_metadata.length,s.column_metadata.length)>10,metadata_query:'list_workbook_sheets',cell_count: (s as any).cell_count ?? cells.length })) })), change_counts: this.store.db.prepare("SELECT json_extract(body,'$.kind') AS kind,count(*) AS total FROM workbook_changes_v1 WHERE report_id=? GROUP BY kind").all(report.report_id).reduce<Record<string, number>>((all, c) => { all[String(c.kind)] = Number(c.total); return all; }, {}) };
  }
  async run(projectId: string, signal?: AbortSignal): Promise<WorkbookStageData> {
    this.writable(); signal?.throwIfAborted(); const draft = this.project(projectId), draftHash = hash(draft), runId = 'wrun_' + randomUUID();
    // Invalidate server-backed work before removing only its exact owned stage;
    // a failed cleanup can never make a cancelled descriptor committable again.
    const superseded=this.store.db.prepare("SELECT id FROM workbook_runs_v1 WHERE project_id=? AND status IN ('running','staged')").all(projectId);
    for(const old of superseded)await this.discardOwned(projectId,String(old.id),'SUPERSEDED');
    this.store.db.prepare('INSERT INTO workbook_runs_v1 VALUES (?,?,NULL,?,NULL,?,NULL,?,NULL)').run(runId, projectId, new Date().toISOString(), 'running', draftHash);
    const folder = join(this.store.root, 'workbook-staging-v1'), stagedName = runId + '.json', path = join(folder, stagedName);
    try {
      const revisions: WorkbookRevisionData[] = []; let materialized = 0, blankRanges = 0, serializedLowerBound = 0;
      // Count JSON bytes without first allocating an entire revision string: a
      // short source format can be shared by hundreds of thousands of cells.
      // Values are plain schema-validated JSON. Omitted outer report fields make
      // this cumulative count a lower bound; the final encoded report is checked too.
      const addBytes=(bytes:number)=>{serializedLowerBound+=bytes;if(serializedLowerBound>MAX_WORKBOOK_REPORT_BYTES)throw reportLimit();};
      const chargeString=(text:string)=>{
        addBytes(Buffer.byteLength(text)+2);
        const escapes=/["\\\u0000-\u001f\ud800-\udfff]/g;let match:RegExpExecArray|null;
        while((match=escapes.exec(text))!==null){
          const code=text.charCodeAt(match.index);
          if(code>=0xd800&&code<=0xdbff){const next=text.charCodeAt(match.index+1);if(next>=0xdc00&&next<=0xdfff){escapes.lastIndex++;continue;}}
          // UTF-8 replaces a lone surrogate with three bytes; JSON escapes it
          // using six ASCII bytes. A valid pair already contributes four bytes.
          addBytes(code>=0xd800&&code<=0xdfff?3:code===34||code===92||[8,9,10,12,13].includes(code)?1:5);
        }
      };
      const charge=(value:unknown):void=>{
        if(typeof value==='string'){chargeString(value);return;}
        if(Array.isArray(value)){addBytes(2+Math.max(0,value.length-1));for(const item of value)charge(item===undefined?null:item);return;}
        if(value!==null&&typeof value==='object'){
          addBytes(2);let count=0;
          for(const [name,item]of Object.entries(value)){if(item===undefined)continue;if(count++)addBytes(1);chargeString(name);addBytes(1);charge(item);}
          return;
        }
        addBytes(JSON.stringify(value).length);
      };
      for (const [index, source] of draft.revisions.entries()) {
        signal?.throwIfAborted(); const bytes = await regularFile(join(this.store.root, 'assets', source.asset_id.slice(7)), source.asset_id.slice(7)); signal?.throwIfAborted();
        const observation = WorkbookObservation.parse(await extractWorkbook(bytes, source.format, { signal })); signal?.throwIfAborted();
        materialized += observation.sheets.reduce((n, s) => n + s.cells.length, 0); if (materialized > 500_000) throw new DocverError('WORKBOOK_REPORT_LIMIT', 'This report exceeds the 500,000 materialized-cell aggregate limit');
        blankRanges += observation.sheets.reduce((n,s)=>n+(s.blank_style_ranges?.length??0),0); if(blankRanges>100_000)throw new DocverError('WORKBOOK_REPORT_LIMIT','This report exceeds the 100000 explicit blank formatting-range aggregate limit');
        const occurrence = workbookID('wrev', { project_id: projectId, index, asset_id: source.asset_id, label: source.label });
        const sheets = observation.sheets.map((sheet, i) => { const sheetId = workbookID('wsheet', { occurrence, index: i, source_ref: sheet.source_ref }); return { ...sheet, sheet_id: sheetId, coverage_gaps: sheet.coverage_gaps.map(g => ({ ...g, sheet_id: sheetId })) }; });
        const revision = { ...observation, sheets, revision_occurrence_id: occurrence, label: source.label, index, asset_id: source.asset_id };charge(revision);revisions.push(revision);
      }
      const changes: WorkbookReportData['changes'] = [];
      for (let i = 1; i < revisions.length; i++) { signal?.throwIfAborted(); for(const change of diffWorkbooks(revisions[i - 1], revisions[i], signal)){if(changes.length>=100_000)throw new DocverError('WORKBOOK_DIFF_LIMIT', 'This report exceeds the 100,000 change-observation limit');charge(change);changes.push(change);} await new Promise<void>(r => setImmediate(r)); }
      const crossGaps = revisions.flatMap((r,i) => i === 0 || r.format === revisions[i - 1].format ? [] : [{ feature: 'cross_format_capabilities', reason: `Comparing ${revisions[i - 1].format} to ${r.format}: unsupported styles/types/visibility in CSV, differing XLSX/ODS formula dialects, style/number-format vocabularies and row/column dimension units are not interpreted as edits or deletions. Raw observations remain separately readable; cross-format semantic equivalence is not certified.`, revision_occurrence_id: r.revision_occurrence_id },{feature:'cross_format_date_representation',reason:'Numeric date/time serials, workbook date epochs and ISO date/time source values are retained without cross-format normalization. Different lexical/type representations are reviewable source observations, not asserted date/time value edits.',revision_occurrence_id:r.revision_occurrence_id}]);
      const data = { schema_version: WORKBOOK_SCHEMA_VERSION, engine_version: WORKBOOK_ENGINE_VERSION, project_id: projectId, title: draft.title, status: 'complete' as const, comparison_coverage:'supported_cells_only' as const, calculation: 'stored_values_only_no_recalculation' as const, revisions, changes, coverage_gaps: [...revisions.flatMap(v => [...v.coverage_gaps, ...v.sheets.flatMap(s => s.coverage_gaps)].map(g => ({ ...g, revision_occurrence_id: v.revision_occurrence_id }))), ...crossGaps,{feature:'inferred_correspondence',reason:'Supported cell extraction completed; sheet/row associations remain inferred from unique names, row contents or first-column keys. Physical fallback and unmatched observations require review; advanced objects and true editing attribution are outside this model.'}] };
      const {report,encoded}=reportSerialization(()=>{const report=WorkbookReport.parse({...data,report_id:workbookID('wreport',data)});validateIdentity(report);return {report,encoded:Buffer.from(canonical(report))};});
      if (encoded.length > MAX_WORKBOOK_REPORT_BYTES) throw reportLimit();
      signal?.throwIfAborted(); if (hash(this.project(projectId)) !== draftHash) throw new DocverError('STALE_RUN', 'Workbook input changed during analysis');
      await mkdir(folder, { recursive: true, mode: 0o700 }); await writeFile(path, encoded, { flag: 'wx', mode: 0o600 }); signal?.throwIfAborted();
      const digest = byteHash(encoded); const updated = this.store.db.prepare("UPDATE workbook_runs_v1 SET status='staged',staged_sha=? WHERE id=? AND status='running'").run(digest, runId);
      if (Number(updated.changes) !== 1) throw new DocverError('STALE_RUN', 'Analysis run is no longer active');
      return WorkbookStage.parse({ project_id: projectId, analysis_run_id: runId, report_id: report.report_id, staged_name: stagedName, sha256: digest, draft_hash: draftHash, schema_version: WORKBOOK_SCHEMA_VERSION, engine_version: WORKBOOK_ENGINE_VERSION });
    } catch (error) {
      this.store.db.prepare("UPDATE workbook_runs_v1 SET status='failed',finished_at=?,error=? WHERE id=? AND status IN ('running','staged')").run(new Date().toISOString(), signal?.aborted ? 'CANCELLED' : error instanceof DocverError ? error.code : 'WORKBOOK_ANALYSIS_FAILED', runId);
      await rm(path, { force: true }); throw error;
    }
  }
  async commit(projectId: string, result: unknown) {
    this.writable(); const data = WorkbookStage.parse(result); if (data.project_id !== projectId || data.staged_name !== data.analysis_run_id + '.json' || data.draft_hash !== hash(this.project(projectId))) throw new DocverError('STALE_RUN', 'Staged workbook result does not match the current project input');
    const active = this.store.db.prepare('SELECT status,draft_hash,staged_sha FROM workbook_runs_v1 WHERE id=? AND project_id=?').get(data.analysis_run_id,projectId);
    if (!active || active.status !== 'staged' || active.draft_hash !== data.draft_hash || active.staged_sha !== data.sha256) throw new DocverError('STALE_RUN','Only a current server-backed staged result may commit');
    const path = join(this.store.root, 'workbook-staging-v1', data.staged_name), bytes = await regularFile(path, data.sha256,MAX_WORKBOOK_REPORT_BYTES); let report: WorkbookReportData;
    try { report = WorkbookReport.parse(JSON.parse(bytes.toString('utf8'))); validateIdentity(report); } catch { throw new DocverError('WORKBOOK_REPORT_CORRUPT', 'Staged workbook result failed schema or identity validation'); }
    if (report.project_id !== projectId || report.report_id !== data.report_id) throw new DocverError('STAGED_ID', 'Staged workbook report does not match this project/result');
    this.store.db.exec('BEGIN IMMEDIATE');
    try {
      const run = this.store.db.prepare('SELECT * FROM workbook_runs_v1 WHERE id=? AND project_id=?').get(data.analysis_run_id, projectId);
      if (!run || run.status !== 'staged' || run.draft_hash !== data.draft_hash || run.staged_sha !== data.sha256 || hash(this.project(projectId)) !== data.draft_hash) throw new DocverError('STALE_RUN', 'Only the current staged workbook run may commit');
      const body = canonical(report), prior = this.store.db.prepare('SELECT body,project_id FROM workbook_reports_v1 WHERE id=?').get(report.report_id);
      if (prior && (prior.body !== body || prior.project_id !== projectId)) throw new DocverError('SNAPSHOT_CONFLICT', 'Immutable workbook report ID already contains different content');
      this.store.db.prepare('INSERT OR IGNORE INTO workbook_reports_v1 VALUES (?,?,?,?)').run(report.report_id, projectId, new Date().toISOString(), body);
      if (!prior) {
        const metadata = { ...report, changes: [], change_count: report.changes.length, revisions: report.revisions.map(r => ({ ...r, sheets: r.sheets.map(s => ({ ...s, cells: [], cell_count: s.cells.length })) })) };
        const metadataBody=canonical(metadata);this.store.db.prepare('INSERT INTO workbook_metadata_v1 VALUES (?,?,?,?)').run(report.report_id, projectId, metadataBody,hash({project_id:projectId,report_id:report.report_id,body:metadataBody}));
        const insertCell = this.store.db.prepare('INSERT INTO workbook_cells_v1 VALUES (?,?,?,?,?,?,?)');
        for (const r of report.revisions) for (const s of r.sheets) for (const c of s.cells) {const cellBody=canonical(c);insertCell.run(report.report_id, r.revision_occurrence_id, s.sheet_id, c.row, c.column,cellBody,hash({report_id:report.report_id,occurrence:r.revision_occurrence_id,sheet_id:s.sheet_id,row:c.row,column:c.column,body:cellBody}));}
        const insertChange = this.store.db.prepare('INSERT INTO workbook_changes_v1 VALUES (?,?,?,?,?,?,?)');
        for (const [i, c] of report.changes.entries()) {const changeBody=canonical(c);insertChange.run(report.report_id, c.change_id, c.from_revision_occurrence_id, c.to_revision_occurrence_id, i,changeBody,hash({report_id:report.report_id,position:i,body:changeBody}));}
      }
      this.store.db.prepare("UPDATE workbook_runs_v1 SET report_id=?,status='success',finished_at=? WHERE id=?").run(report.report_id, new Date().toISOString(), data.analysis_run_id);
      this.store.db.exec('COMMIT');
    } catch (error) { this.store.db.exec('ROLLBACK'); throw error; }
    // COMMIT is the outcome boundary. A leftover private stage does not undo
    // the durable report and must not turn a completed analysis into a failure.
    let cleanupPending=false;try{await rm(path,{force:true});}catch{cleanupPending=true;}
    return { project_id: projectId, report_id: report.report_id, status: 'complete',cleanup_pending:cleanupPending };
  }
  runStatus(projectId:string,runId:string){
    this.requireProject(projectId);if(!/^wrun_[a-f0-9-]+$/.test(runId))throw new DocverError('WORKBOOK_RUN_SCOPE','Invalid workbook run ID');
    const run=this.store.db.prepare('SELECT status,report_id,started_at,finished_at,error FROM workbook_runs_v1 WHERE id=? AND project_id=?').get(runId,projectId);if(!run)throw new DocverError('WORKBOOK_RUN_SCOPE','Workbook run is outside this project');
    const status=String(run.status);if(!['running','staged','success','failed'].includes(status))throw new DocverError('WORKBOOK_RUN_CORRUPT','Workbook run status is damaged');
    let reportId:string|null=null;
    if(status==='success'){
      if(typeof run.report_id!=='string'||!/^wreport_[a-f0-9]{64}$/.test(run.report_id))throw new DocverError('WORKBOOK_RUN_CORRUPT','Successful workbook run has no valid fixed report');
      try{reportId=this.resolveReportId(projectId,run.report_id);}catch{throw new DocverError('WORKBOOK_RUN_CORRUPT','Successful workbook run report is outside its project or missing');}
    }
    return {project_id:projectId,analysis_run_id:runId,status,report_id:reportId,started_at:String(run.started_at),finished_at:run.finished_at===null?null:String(run.finished_at),error:run.error===null?null:String(run.error)};
  }
  async recover(projectId?: string) {
    this.writable(); if (projectId) this.requireProject(projectId); const pending = this.store.db.prepare("SELECT id,project_id FROM workbook_runs_v1 WHERE status IN ('running','staged')" + (projectId ? ' AND project_id=?' : '')).all(...(projectId ? [projectId] : []));
    for (const run of pending) { this.store.db.prepare("UPDATE workbook_runs_v1 SET status='failed',finished_at=?,error='INTERRUPTED' WHERE id=? AND status IN ('running','staged')").run(new Date().toISOString(), run.id); if (/^wrun_[a-f0-9-]+$/.test(String(run.id))) await rm(join(this.store.root, 'workbook-staging-v1', String(run.id) + '.json'), { force: true }); }
    // Only our exact staged basenames are candidates; recovery never traverses user paths.
    if (!projectId) { try { for (const name of await readdir(join(this.store.root, 'workbook-staging-v1'))) if (/^wrun_[a-f0-9-]+\.json$/.test(name)) await rm(join(this.store.root, 'workbook-staging-v1', name), { force: true }); } catch (e) { if ((e as NodeJS.ErrnoException).code !== 'ENOENT') throw e; } }
    return { recovered_runs: pending.length };
  }
  async discard(projectId:string,runId:string){return this.discardOwned(projectId,runId,'CANCELLED');}
  private async discardOwned(projectId:string,runId:string,reason:'CANCELLED'|'SUPERSEDED'){
    this.writable();this.requireProject(projectId);if(!/^wrun_[a-f0-9-]+$/.test(runId))throw new DocverError('WORKBOOK_RUN_SCOPE','Invalid workbook run ID');
    const run=this.store.db.prepare('SELECT status FROM workbook_runs_v1 WHERE id=? AND project_id=?').get(runId,projectId);if(!run)throw new DocverError('WORKBOOK_RUN_SCOPE','Workbook run is outside this project');
    if(!['running','staged'].includes(String(run.status)))throw new DocverError('STALE_RUN','Only an active workbook run may be discarded');
    const updated=this.store.db.prepare("UPDATE workbook_runs_v1 SET status='failed',finished_at=?,error=? WHERE id=? AND project_id=? AND status IN ('running','staged')").run(new Date().toISOString(),reason,runId,projectId);
    if(Number(updated.changes)!==1)throw new DocverError('STALE_RUN','Workbook run is no longer active');
    await rm(join(this.store.root,'workbook-staging-v1',runId+'.json'),{force:true});
    return {project_id:projectId,analysis_run_id:runId,discarded:true};
  }
  publish(projectId: string, reportId: string, label: string, reason: string) {
    this.writable(); const report = this.report(projectId, reportId); label = z.string().trim().min(1).max(200).parse(label); reason = z.string().trim().min(1).max(2000).parse(reason);
    const data = { release_id: 'wrelease_' + randomUUID(), project_id: projectId, report_id: report.report_id, schema_version: report.schema_version, engine_version: report.engine_version, label, reason, recorded_at: new Date().toISOString(), provenance: 'local_user_input_no_editor_authentication' as const };
    this.store.db.prepare('INSERT INTO workbook_releases_v1 VALUES (?,?,?,?,?)').run(data.release_id, projectId, report.report_id, data.recorded_at, canonical(data)); return data;
  }
  releases(projectId: string) { this.requireProject(projectId); return this.store.db.prepare('SELECT body FROM workbook_releases_v1 WHERE project_id=? ORDER BY rowid DESC').all(projectId).map(row => JSON.parse(String(row.body))); }
  async export(projectId: string, reportId: string, folder: string) {
    this.writable(); const report = this.report(projectId, reportId), releases = this.releases(projectId).filter(v => v.report_id === report.report_id), exportId = workbookID('wexport', { export_schema_version:'workbook-export.1',report_id: report.report_id, release_ids: releases.map(v => v.release_id) });
    folder = resolve(folder); mkdirSync(folder, { recursive: true }); const quoted = (v: unknown) => { const value = String(v).replace(/\r\n?/g, '\n');let longest=2;for(const match of value.matchAll(/`+/g))longest=Math.max(longest,match[0].length);const fence = '`'.repeat(longest + 1); return '> ' + [fence + 'text', value, fence].join('\n').replace(/\n/g, '\n> '); };
    const json = Buffer.from(canonical({ export_schema_version:'workbook-export.1',export_id: exportId, report, releases, provenance: 'Stored source observations; user labels/reasons and recorded timestamps do not authenticate actual editing authorship' }));
    const lines = [ '# Workbook version comparison', '', quoted(report.title), '', `Report: \`${report.report_id}\``, '', '> Formulas were not executed or recalculated. Saved values may be missing or stale. Associations are inferred; ambiguous correspondence is not confirmed deletion.', '', '## Local release records', ...releases.flatMap(v => ['', quoted(v.label), quoted(v.reason), quoted(v.recorded_at + ' · local recorded time, not true edit time')]), '', '## Source revisions' ];
    for (const r of report.revisions) { const source = await regularFile(join(this.store.root, 'assets', r.asset_id.slice(7)), r.asset_id.slice(7)); const file = `${r.asset_id.slice(7)}.${r.format}`; await publishContent(join(folder, file), source, r.asset_id.slice(7)); lines.push('', quoted(r.label), `- Occurrence: \`${r.revision_occurrence_id}\``, `- Original: [${r.format.toUpperCase()} source](${file})`); }
    lines.push('',`Style references resolve in the source revision's style_definitions in [the paired JSON report](${exportId}.json). Inline legacy styles remain in each cell.`, '','## Change observations'); for (const c of report.changes) lines.push('', `### ${c.kind} · ${c.change_id}`, quoted(c.description), quoted(`${c.association} · ${c.alignment_method}`), quoted(`${c.before_address ?? '(no cell observation)'} → ${c.after_address ?? '(no cell observation)'}`), quoted('Before: ' + canonical(c.before)), quoted('After: ' + canonical(c.after)));
    lines.push('', '## Coverage gaps'); for (const g of report.coverage_gaps) lines.push('', quoted(g.feature + ': ' + g.reason));
    const manifest=canonical({record_type:'workbook_manifest',export_schema_version:'workbook-export.1',export_id:exportId,project_id:projectId,report_id:report.report_id,schema_version:report.schema_version,engine_version:report.engine_version,revisions:report.revisions.map(r=>({revision_occurrence_id:r.revision_occurrence_id,style_definitions:r.style_definitions??{},...(report.engine_version==='workbook.1.1'?{sheets:r.sheets.map(s=>({sheet_id:s.sheet_id,blank_style_ranges:s.blank_style_ranges??[]}))}:{})}))});
    if(Buffer.byteLength(manifest)>MAX_WORKBOOK_REPORT_BYTES)throw new DocverError('WORKBOOK_EXPORT_LIMIT','Workbook style manifest exceeds the bounded report size');
    const markdown = Buffer.from(lines.join('\n') + '\n'), jsonl = Buffer.from(manifest+'\n'+report.changes.map(c => canonical({ record_type:'workbook_change',project_id: projectId, report_id: report.report_id, ...c })).join('\n') + (report.changes.length ? '\n' : ''));
    for (const [ext, bytes] of [['json', json], ['md', markdown], ['jsonl', jsonl]] as const) await publishContent(join(folder, exportId + '.' + ext), bytes, byteHash(bytes));
    return { project_id: projectId, report_id: report.report_id, export_id: exportId, files: ['json', 'md', 'jsonl'].map(ext => join(folder, exportId + '.' + ext)), release_count: releases.length };
  }
}

export function validateIdentity(report: WorkbookReportData) {
  const { report_id, ...body } = report; if (workbookID('wreport', body) !== report_id) throw new DocverError('WORKBOOK_IDENTITY', 'Workbook report identity does not match its complete content');
  const revisions = new Set<string>(), sheets = new Set<string>(); let rangeCount=0;
  for (const r of report.revisions) { if (revisions.has(r.revision_occurrence_id)) throw new Error('Duplicate occurrence'); revisions.add(r.revision_occurrence_id);for(const [key,style]of Object.entries(r.style_definitions??{}))if(workbookID('wstyle',style)!==key)throw new DocverError('WORKBOOK_STYLE_SCOPE','Workbook style definition key does not match its content'); for (const s of r.sheets) { if (sheets.has(s.sheet_id)) throw new Error('Duplicate sheet'); sheets.add(s.sheet_id); validateBlankRangeLayout(s); rangeCount+=s.blank_style_ranges?.length??0;if(rangeCount>100_000)throw new DocverError('WORKBOOK_REPORT_LIMIT','Report blank formatting-range count exceeds limit');for(const range of s.blank_style_ranges??[])if(range.style_ref&&!r.style_definitions?.[range.style_ref])throw new DocverError('WORKBOOK_STYLE_SCOPE','Blank formatting range style reference is outside its source occurrence'); const cells = new Set<string>(); for (const c of s.cells) { if (cells.has(c.address)) throw new Error('Duplicate address'); cells.add(c.address);if(c.style_ref&&!r.style_definitions?.[c.style_ref])throw new DocverError('WORKBOOK_STYLE_SCOPE','Cell style reference is outside its source occurrence'); } } }
  for (const change of report.changes) {if (!revisions.has(change.from_revision_occurrence_id) || !revisions.has(change.to_revision_occurrence_id) || (change.from_sheet_id && !sheets.has(change.from_sheet_id)) || (change.to_sheet_id && !sheets.has(change.to_sheet_id))) throw new Error('Change scope');for(const [occurrence,cell]of [[change.from_revision_occurrence_id,change.before],[change.to_revision_occurrence_id,change.after]]as const)if(cell?.style_ref&&!report.revisions.find(r=>r.revision_occurrence_id===occurrence)?.style_definitions?.[cell.style_ref])throw new DocverError('WORKBOOK_STYLE_SCOPE','Change cell style reference is outside its source occurrence');}
}
