import { z } from 'zod';
import { canonical, hash, DocverError } from '../schema/index.js';
import { WorkbookService } from './service.js';
import { diffWorkbooks, WorkbookChange, type WorkbookChangeData, type WorkbookReportData } from './diff.js';
import { workbookID,type WorkbookCellData, type WorkbookSheetData } from './types.js';

const key = z.string().regex(/^[a-zA-Z0-9_-]{1,160}$/), scope = { project_id: key, report_id: key };
const paging = { limit: z.number().int().min(1).max(200).default(50), cursor: z.string().max(2048).optional(), max_output_tokens: z.number().int().min(256).max(8000).default(4000) };
const text = { text_offset: z.number().int().min(0).max(2_000_000).default(0), text_length: z.number().int().min(1).max(4096).default(1024) };
const version = { ...scope, revision_occurrence_id: key };
const sheet = { ...version, sheet_id: key };
export const workbookQuerySchemas = {
  list_workbook_projects: z.object({ ...paging }),
  list_workbook_reports: z.object({ project_id: key, ...paging }),
  get_workbook_report: z.object({ ...scope, ...paging }),
  list_workbook_revisions: z.object({ ...scope, ...paging }),
  list_workbook_sheets: z.object({ ...version, sheet_id: key.optional(), metadata_offset: z.number().int().min(0).max(500_000).default(0), metadata_limit: z.number().int().min(1).max(100).default(20), ...paging }),
  get_workbook_range: z.object({ ...sheet, row_start: z.number().int().min(1).max(1_048_576), row_limit: z.number().int().min(1).max(200).default(50), column_start: z.number().int().min(1).max(16_384), column_limit: z.number().int().min(1).max(200).default(50), ...paging, ...text }),
  get_workbook_cell: z.object({ ...sheet, row: z.number().int().min(1).max(1_048_576), column: z.number().int().min(1).max(16_384), component: z.enum(['cell','style']).default('cell'), ...text, ...paging }),
  list_workbook_changes: z.object({ ...scope, from_revision_occurrence_id: key, to_revision_occurrence_id: key, mode: z.enum(['history', 'range_net']).default('history'), sheet_id: key.optional(), kind: WorkbookChange.shape.kind.optional(), ...text, ...paging }),
  get_workbook_change: z.object({ ...scope, change_id: key, from_revision_occurrence_id: key.optional(), to_revision_occurrence_id: key.optional(), mode: z.enum(['history', 'range_net']).default('history'), component:z.enum(['summary','before','after']).default('summary'), ...text, ...paging }),
  search_workbook_cells: z.object({ ...version, sheet_id: key.optional(), query: z.string().min(1).max(256), case_sensitive: z.boolean().default(false), ...text, ...paging }),
  get_workbook_cell_history: z.object({ ...sheet, row: z.number().int().min(1).max(1_048_576), column: z.number().int().min(1).max(16_384), ...text, ...paging }),
  list_workbook_coverage_gaps: z.object({ ...scope, revision_occurrence_id: key.optional(), sheet_id: key.optional(), ...paging }),
};
export type WorkbookQueryName = keyof typeof workbookQuerySchemas;

type TextState = { offset: number; next_offset: number | null; total_length: number; state: 'missing' | 'empty' | 'complete' | 'truncated' };
function chunk(value: string | null, offset: number, length: number): { value: string | null; continuation: TextState } {
  if (value === null) return { value: null, continuation: { offset, next_offset: null, total_length: 0, state: 'missing' } };
  // UTF-16 offsets are explicit and stable; never cut a surrogate pair.
  let start = Math.min(offset, value.length), end = Math.min(value.length, start + length);
  if (start > 0 && /[\uDC00-\uDFFF]/.test(value[start] ?? '') && /[\uD800-\uDBFF]/.test(value[start - 1])) start--;
  if (end < value.length && /[\uD800-\uDBFF]/.test(value[end - 1] ?? '')) end--;
  if (end === start && start < value.length) end = Math.min(value.length, start + 2);
  return { value: value.slice(start, end), continuation: { offset: start, next_offset: end < value.length ? end : null, total_length: value.length, state: value.length === 0 ? 'empty' : end < value.length || start > 0 ? 'truncated' : 'complete' } };
}
export function boundedWorkbookCell(cell: WorkbookCellData | null, offset: number, length: number) {
  if (!cell) return null;
  const value = chunk(cell.value, offset, length), formula = chunk(cell.formula, offset, length), format = chunk(cell.number_format, offset, length);
  const style = Object.fromEntries(Object.entries(cell.style).slice(0, 4).map(([k, v]) => [k, v.slice(0, 64)]));
  const styleTruncated = Object.entries(cell.style).length > 4 || Object.values(cell.style).some(v => v.length > 64);
  return { ...cell, value: value.value, formula: formula.value, number_format: format.value, style, source_ref: cell.source_ref, text_continuations: { value: value.continuation, formula: formula.continuation, number_format: format.continuation }, ...(styleTruncated ? {style_truncated:true,full_style_query:'get_workbook_cell component=style'}:{}) };
}
const boundedCell = boundedWorkbookCell;
function summary(sheet: WorkbookSheetData, offset: number, limit: number) { return { sheet_id: sheet.sheet_id, name: sheet.name, index: sheet.index, hidden: sheet.hidden, row_count: sheet.row_count, column_count: sheet.column_count, cell_count: (sheet as any).cell_count ?? sheet.cells.length, merges: sheet.merges.slice(offset, offset + limit), merge_count: sheet.merges.length, row_metadata: sheet.row_metadata.slice(offset, offset + limit), row_metadata_count: sheet.row_metadata.length, column_metadata: sheet.column_metadata.slice(offset, offset + limit), column_metadata_count: sheet.column_metadata.length, coverage_gap_count: sheet.coverage_gaps.length, metadata_offset: offset, next_metadata_offset: Math.max(sheet.merges.length, sheet.row_metadata.length, sheet.column_metadata.length) > offset + limit ? offset + limit : null }; }
const pause = () => new Promise<void>(resolve => setImmediate(resolve));

export class WorkbookQueryService {
  private readonly netCache=new Map<string,{changes:WorkbookChangeData[];bytes:number}>();
  private netBytes=0;
  constructor(readonly service: WorkbookService, readonly allowedProjects: Set<string>) {}
  private permit(projectId: string) { if (!this.allowedProjects.has(projectId)) throw new DocverError('PROJECT_SCOPE', 'Workbook project is not configured in this reader scope'); }
  async query(name: WorkbookQueryName | string, input: unknown, measure?: (result: Record<string, any>) => number): Promise<Record<string, any>> {
    if (!(name in workbookQuerySchemas)) throw new DocverError('UNKNOWN_QUERY', 'Unknown read-only workbook query');
    const args: any = workbookQuerySchemas[name as WorkbookQueryName].parse(input); let report: WorkbookReportData | undefined, items: any[] = [], extra: Record<string, any> = {};
    if (name === 'list_workbook_projects') items = this.service.projects().filter(p => this.allowedProjects.has(p.project_id)).map(({ revisions: _revisions, ...p }) => p);
    else {
      this.permit(args.project_id);
      if (name === 'list_workbook_reports') items = this.service.reports(args.project_id);
      else {
        report = this.service.metadata(args.project_id, args.report_id); args.report_id = report.report_id;
        const revision = () => { const found = report!.revisions.find(r => r.revision_occurrence_id === args.revision_occurrence_id); if (!found) throw new DocverError('WORKBOOK_REVISION_SCOPE', 'Workbook occurrence is outside this fixed report'); return found; };
        const selectedSheet = () => { const found = revision().sheets.find(s => s.sheet_id === args.sheet_id); if (!found) throw new DocverError('WORKBOOK_SHEET_SCOPE', 'Workbook sheet is outside the selected occurrence'); return found; };
        switch (name) {
          case 'get_workbook_report': {
            items = [{ project_id: report.project_id, report_id: report.report_id, title: report.title, schema_version: report.schema_version, engine_version: report.engine_version, status: report.status, comparison_coverage:report.comparison_coverage,calculation: report.calculation, revision_count: report.revisions.length, change_count: (report as any).change_count ?? report.changes.length, coverage_gap_count: report.coverage_gaps.length, association_policy: 'inferred_unique_sheet_name_or_content_and_first_column_or_row_content; ambiguous_not_semantic_deletion' }]; break;
          }
          case 'list_workbook_revisions': items = report.revisions.map(({ sheets, coverage_gaps,style_definitions:_styles, ...r }) => ({ ...r, sheet_count: sheets.length, coverage_gap_count: coverage_gaps.length })); break;
          case 'list_workbook_sheets': if (args.sheet_id) selectedSheet(); items = revision().sheets.filter(s => !args.sheet_id || s.sheet_id === args.sheet_id).map(s => summary(s,args.metadata_offset,args.metadata_limit)); break;
          case 'get_workbook_range': {
            const s = selectedSheet(), rowEnd = Math.min(1_048_577, args.row_start + args.row_limit), columnEnd = Math.min(16_385, args.column_start + args.column_limit);
            items = this.service.indexedCells(args.project_id, report.report_id, args.revision_occurrence_id, s.sheet_id, args.row_start, rowEnd, args.column_start, columnEnd,report).map(c => boundedCell(c, args.text_offset, args.text_length));
            extra = { revision_occurrence_id: revision().revision_occurrence_id, sheet_id: s.sheet_id, row_start: args.row_start, row_limit: rowEnd - args.row_start, column_start: args.column_start, column_limit: columnEnd - args.column_start, sparse: true, missing_cell_meaning: 'not_materialized_not_confirmed_blank', metadata_query: 'list_workbook_sheets' }; break;
          }
          case 'get_workbook_cell': {
            const s = selectedSheet(), raw = this.service.indexedCells(args.project_id, report.report_id, args.revision_occurrence_id, s.sheet_id, args.row, args.row + 1, args.column, args.column + 1,report)[0] ?? null, cell = boundedCell(raw, args.text_offset, args.text_length);
            items = cell ? [cell] : []; extra = { text_offset_unit:'utf16_code_units', availability: raw ? 'available' : 'not_materialized', revision_occurrence_id: args.revision_occurrence_id, sheet_id: args.sheet_id };
            if (args.component === 'style') { items = Object.entries(raw?.style ?? {}).map(([key,value]) => { const part = chunk(value,args.text_offset,args.text_length); return { key,value:part.value,text_continuations:{value:part.continuation},text_offset_unit:'utf16_code_units' }; }); extra = { availability: raw ? 'available' : 'not_materialized', component:'style', revision_occurrence_id:args.revision_occurrence_id,sheet_id:args.sheet_id }; }
            break;
          }
          case 'list_workbook_changes': items = this.changes(report, args).filter(c => !args.kind || c.kind === args.kind).filter(c => !args.sheet_id || c.from_sheet_id === args.sheet_id || c.to_sheet_id === args.sheet_id).map(c => this.boundedChange(c, args)); extra = { mode: args.mode, from_revision_occurrence_id: args.from_revision_occurrence_id, to_revision_occurrence_id: args.to_revision_occurrence_id, interval_semantics: args.mode === 'history' ? 'adjacent_events_in_interval' : 'endpoint_comparison_not_intermediate_events' }; if (args.sheet_id && !report.revisions.some(r => r.sheets.some(s => s.sheet_id === args.sheet_id))) throw new DocverError('WORKBOOK_SHEET_SCOPE', 'Sheet filter is outside this report'); break;
          case 'get_workbook_change': {
            let candidates = args.mode==='range_net'?[]:this.service.indexedChanges(args.project_id, report.report_id, report.revisions.map(r => r.revision_occurrence_id),args.change_id);
            if (args.mode === 'range_net') { if (!args.from_revision_occurrence_id || !args.to_revision_occurrence_id) throw new DocverError('WORKBOOK_RANGE_REQUIRED', 'A net change requires fixed endpoint occurrence IDs'); candidates = this.changes(report, args); }
            else if(args.from_revision_occurrence_id||args.to_revision_occurrence_id){if(!args.from_revision_occurrence_id||!args.to_revision_occurrence_id)throw new DocverError('WORKBOOK_RANGE_REQUIRED','A history interval requires both fixed endpoint occurrence IDs');candidates=this.changes(report,args);}
            const change = candidates.find(c => c.change_id === args.change_id); if (!change) throw new DocverError('WORKBOOK_CHANGE_SCOPE', 'Change is outside the requested fixed report/range'); items = [this.boundedChange(change, args,args.component,report)]; break;
          }
          case 'search_workbook_cells': {
            const r = revision(), sheets = args.sheet_id ? [selectedSheet()] : r.sheets, needle = args.case_sensitive ? args.query : args.query.toLocaleLowerCase('en-US');
            for (const s of sheets) for (const cell of this.service.indexedCells(args.project_id,report.report_id,r.revision_occurrence_id,s.sheet_id,1,1_048_577,1,16_385,report)) { const found = [cell.value, cell.formula].some(v => v !== null && (args.case_sensitive ? v : v.toLocaleLowerCase('en-US')).includes(needle)); if (found) items.push({ ...boundedCell(cell, args.text_offset, args.text_length), sheet_id: s.sheet_id, revision_occurrence_id: r.revision_occurrence_id }); }
            extra = { matching: 'literal_stored_value_or_formula_source_no_execution' }; break;
          }
          case 'get_workbook_cell_history': {
            const s = selectedSheet(), selected = revision(),readCell=(r:typeof selected,sheet:WorkbookSheetData,row:number,column:number)=>this.service.indexedCells(report!.project_id,report!.report_id,r.revision_occurrence_id,sheet.sheet_id,row,row+1,column,column+1,report,false)[0]??null;
            const startCell=readCell(selected,s,args.row,args.column),columns=new Map<string,{byRow:Map<number,string>;byKey:Map<string,{count:number;row:number}>}>();
            const keyIndex=(r:typeof selected,sheet:WorkbookSheetData)=>{const key=r.revision_occurrence_id+'|'+sheet.sheet_id,existing=columns.get(key);if(existing)return existing;const byRow=new Map<number,string>(),byKey=new Map<string,{count:number;row:number}>();for(const cell of this.service.indexedCells(report!.project_id,report!.report_id,r.revision_occurrence_id,sheet.sheet_id,1,1_048_577,1,2,report,false)){if(cell.value===null||cell.value===''||cell.formula!==null||cell.formula_interpretation==='unresolved')continue;const value=canonical([cell.value_type,cell.value]);byRow.set(cell.row,value);const previous=byKey.get(value);if(previous)previous.count++;else byKey.set(value,{count:1,row:cell.row});}const index={byRow,byKey};columns.set(key,index);return index;};
            // Every row is grounded in a physical location. Follow only unique inferred anchors;
            // uncertain links stop, rather than silently hopping to another occupant of A1.
            const located = new Map<number, { sheet: WorkbookSheetData; cell: WorkbookCellData | null; association: string; method: string }>(); located.set(selected.index, { sheet: s, cell: startCell, association: 'exact', method: 'selected_physical_cell' });
            for (const direction of [-1, 1]) { let current = selected.index; while (located.has(current)) {
              const next = current + direction; if (next < 0 || next >= report.revisions.length) break;
              const at = located.get(current)!, target = report.revisions[next], sheetCandidates = target.sheets.filter(v => v.name === at.sheet.name);
              if (sheetCandidates.length !== 1 || !at.cell) break; const targetSheet = sheetCandidates[0];
              const oldIndex=keyIndex(report.revisions[current],at.sheet),key=oldIndex.byRow.get(at.cell.row);
              let row = at.cell.row, method = 'physical_row_fallback', association = 'needs_review';
              if (key) {const oldMatch=oldIndex.byKey.get(key),match=keyIndex(target,targetSheet).byKey.get(key);if(oldMatch?.count===1&&match?.count===1){row=match.row;method='unique_nonempty_first_column_key';association='inferred';}}
              if (association === 'needs_review') break;
              located.set(next, { sheet: targetSheet, cell: readCell(target,targetSheet,row,at.cell.column), association, method }); current = next;
            } }
            items = report.revisions.map(r => { const at = located.get(r.index); return { revision_occurrence_id: r.revision_occurrence_id, label: r.label, sheet_id: at?.sheet.sheet_id ?? null, cell: at ? boundedCell(this.cellStyle(report!,r.revision_occurrence_id,at.cell), args.text_offset, args.text_length) : null, availability: at ? at.cell ? 'available' : 'not_materialized' : 'correspondence_unresolved', association: at?.association ?? 'needs_review', alignment_method: at?.method ?? 'no_unambiguous_cell_lineage' }; }); extra = { inference_warning: 'Unique first-column keys infer lineage; no true edit author/time is inferred' }; break;
          }
          case 'list_workbook_coverage_gaps': {
            if (args.revision_occurrence_id) revision(); if (args.sheet_id && !report.revisions.some(r => (!args.revision_occurrence_id || r.revision_occurrence_id === args.revision_occurrence_id) && r.sheets.some(s => s.sheet_id === args.sheet_id))) throw new DocverError('WORKBOOK_SHEET_SCOPE', 'Coverage sheet is outside the selected scope');
            items = report.coverage_gaps.filter(g => (!args.revision_occurrence_id || g.revision_occurrence_id === args.revision_occurrence_id) && (!args.sheet_id || g.sheet_id === args.sheet_id)).map(g => ({ ...g, feature: g.feature.slice(0, 256), reason: g.reason.slice(0, 2048), text_truncated: g.feature.length > 256 || g.reason.length > 2048 })); break;
          }
        }
      }
    }
    await pause(); return this.paginate(name, args, items, extra, measure);
  }
  private changes(report: WorkbookReportData, args: any) {
    const from = report.revisions.findIndex(r => r.revision_occurrence_id === args.from_revision_occurrence_id), to = report.revisions.findIndex(r => r.revision_occurrence_id === args.to_revision_occurrence_id);
    if (from < 0 || to < 0 || to < from) throw new DocverError('WORKBOOK_RANGE_SCOPE', 'Workbook interval must be ordered fixed occurrence IDs in this report');
    if (from === to) return [];
    if (args.mode === 'range_net') {
      if(to===from+1)return this.service.indexedChanges(report.project_id,report.report_id,[report.revisions[to].revision_occurrence_id],args.change_id);
      const key=hash({project_id:report.project_id,report_id:report.report_id,from:args.from_revision_occurrence_id,to:args.to_revision_occurrence_id}),cached=this.netCache.get(key);
      if(cached){this.netCache.delete(key);this.netCache.set(key,cached);return cached.changes;}
      const endpoint=(index:number)=>{const revision=report.revisions[index];return {...revision,sheets:revision.sheets.map(sheet=>({...sheet,cells:this.service.indexedCells(report.project_id,report.report_id,revision.revision_occurrence_id,sheet.sheet_id,1,1_048_577,1,16_385,report,false)}))};};
      const changes=diffWorkbooks(endpoint(from),endpoint(to)),bytes=Buffer.byteLength(JSON.stringify(changes));
      if(bytes<=16*1024*1024){while(this.netCache.size>=2||this.netBytes+bytes>16*1024*1024){const oldest=this.netCache.keys().next().value;if(oldest===undefined)break;this.netBytes-=this.netCache.get(oldest)!.bytes;this.netCache.delete(oldest);}this.netCache.set(key,{changes,bytes});this.netBytes+=bytes;}
      return changes;
    }
    const allowed = report.revisions.slice(from + 1, to + 1).map(r => r.revision_occurrence_id); return this.service.indexedChanges(report.project_id,report.report_id,allowed,args.change_id);
  }
  private cellStyle(report:WorkbookReportData,occurrence:string,cell:WorkbookCellData|null){if(!cell?.style_ref)return cell;const style=report.revisions.find(r=>r.revision_occurrence_id===occurrence)?.style_definitions?.[cell.style_ref];if(!style||workbookID('wstyle',style)!==cell.style_ref)throw new DocverError('WORKBOOK_STYLE_SCOPE','Cell style definition is outside this source occurrence or damaged');return {...cell,style};}
  private boundedChange(c: WorkbookChangeData, args: any, component:'summary'|'before'|'after'='summary',report?:WorkbookReportData) {
    const {before,after,...metadata}=c;
    return {...metadata,description:c.description.slice(0,2048),component,before_observation:before?'available':'not_materialized',after_observation:after?'available':'not_materialized',raw_detail_query:'get_workbook_change',raw_detail_components:['before','after'],...(component==='before'?{before:boundedCell(report?this.cellStyle(report,c.from_revision_occurrence_id,before):before,args.text_offset,args.text_length)}:component==='after'?{after:boundedCell(report?this.cellStyle(report,c.to_revision_occurrence_id,after):after,args.text_offset,args.text_length)}:{})};
  }
  private paginate(name: string, args: any, all: any[], extra: Record<string, any>, measure?: (result: Record<string, any>) => number) {
    const { cursor, limit, max_output_tokens,text_offset:_textOffset,text_length:_textLength, ...selectors } = args, binding = hash({ name, selectors }); let index = 0;
    if (cursor) {
      try { const parsed = JSON.parse(Buffer.from(cursor, 'base64url').toString('utf8')); if (parsed.scope !== binding || parsed.checksum !== hash({ scope: parsed.scope, index: parsed.index }) || !Number.isSafeInteger(parsed.index) || parsed.index < 0 || parsed.index > all.length) throw new Error('cursor'); index = parsed.index; }
      catch { throw new DocverError('WORKBOOK_CURSOR_SCOPE', 'Cursor is invalid or belongs to another report/query/selector'); }
    }
    const encode = (offset: number) => Buffer.from(JSON.stringify({ scope: binding, index: offset, checksum: hash({ scope: binding, index: offset }) })).toString('base64url');
    const base: Record<string,any> = { schema_version: 'workbook.1', project_id: args.project_id ?? null, report_id: args.report_id ?? null, ...extra, items: [] as any[], total: all.length, next_cursor: null as string | null };
    // Match the existing reader's conservative byte budget, including duplicated MCP wire copies when measured by its adapter.
    const budget = max_output_tokens, size = measure ?? ((value: Record<string,any>) => Buffer.byteLength(JSON.stringify(value))), selected: any[] = []; let outputLimited = false;
    for (let i = index; i < Math.min(all.length, index + limit); i++) {
      const next = i + 1 < all.length ? encode(i + 1) : null, candidate = { ...base, items: [...selected, all[i]], next_cursor: next };
      if (size(candidate) > budget) { if (!selected.length) {
        // Long strings use explicit text offsets; shrink a single cell/change until it fits.
        let shrunk: any, fitted = false;
        for (const textLimit of [256,64,16,2]) {
          shrunk = JSON.parse(JSON.stringify(all[i]));
          const truncate = (v: any) => { if (!v || typeof v !== 'object') return; if (v.text_continuations) for (const field of ['value', 'formula', 'number_format']) { const s = v[field]; if (typeof s === 'string' && s.length > textLimit) { const part = chunk(s, 0, textLimit); v[field] = part.value; const info = v.text_continuations[field]; if (info) { info.next_offset = info.offset + String(part.value).length; info.state = 'truncated'; } } } if (textLimit <= 16 && v.style && Object.keys(v.style).length) { v.style = {}; v.style_truncated = true; } for (const [key, value] of Object.entries(v)) if (key !== 'text_continuations') truncate(value); }; truncate(shrunk);
          const short = { ...base, items: [shrunk], next_cursor: next, output_limited: true };
          if (size(short) <= budget) { fitted = true; break; }
        }
        if (!fitted) throw new DocverError('OUTPUT_BUDGET_TOO_SMALL', 'Output budget cannot fit one structured workbook item; increase max_output_tokens');
        selected.push(shrunk); outputLimited = true;
      } break; }
      selected.push(all[i]);
    }
    const next = index + selected.length < all.length ? encode(index + selected.length) : null;
    const result = { ...base, items: selected, next_cursor: next, ...(outputLimited ? { output_limited:true } : {}) }; if (size(result) > budget) throw new DocverError('OUTPUT_BUDGET_TOO_SMALL', 'Workbook output metadata exceeds the requested budget; increase max_output_tokens'); return result;
  }
}
