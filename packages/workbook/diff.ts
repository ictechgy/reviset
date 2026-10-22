import { z } from 'zod';
import { canonical, hash, DocverError } from '../schema/index.js';
import { WorkbookCell, WorkbookObservation, WorkbookGap, workbookID, WORKBOOK_SCHEMA_VERSION, WORKBOOK_ENGINE_VERSION, type WorkbookCellData, type WorkbookSheetData } from './types.js';

export const WorkbookRevision = WorkbookObservation.extend({
  revision_occurrence_id: z.string(), label: z.string().max(200), index: z.number().int().nonnegative(), asset_id: z.string().regex(/^sha256:[a-f0-9]{64}$/),
});
export type WorkbookRevisionData = z.infer<typeof WorkbookRevision>;
export const WorkbookChange = z.object({
  change_id: z.string(), kind: z.enum(['formula', 'stored_value', 'cache_availability', 'calculation_settings', 'value_type', 'number_format', 'style', 'visibility', 'cell_observation', 'row_position', 'row_correspondence', 'sheet_name', 'sheet_position', 'sheet_visibility', 'sheet_dimensions', 'sheet_observation', 'merges', 'date_system']),
  from_revision_occurrence_id: z.string(), to_revision_occurrence_id: z.string(),
  from_sheet_id: z.string().nullable(), to_sheet_id: z.string().nullable(),
  before_address: z.string().nullable(), after_address: z.string().nullable(),
  before: WorkbookCell.nullable(), after: WorkbookCell.nullable(),
  association: z.enum(['exact', 'inferred', 'needs_review']), alignment_method: z.string(), description: z.string(),
});
export type WorkbookChangeData = z.infer<typeof WorkbookChange>;
export const WorkbookReport = z.object({
  schema_version: z.literal(WORKBOOK_SCHEMA_VERSION), engine_version: z.literal(WORKBOOK_ENGINE_VERSION),
  project_id: z.string().regex(/^wprj_[a-zA-Z0-9_-]+$/), report_id: z.string(), title: z.string().max(200),
  status: z.literal('complete'), comparison_coverage: z.literal('supported_cells_only'), calculation: z.literal('stored_values_only_no_recalculation'),
  revisions: z.array(WorkbookRevision).min(1).max(100), changes: z.array(WorkbookChange), coverage_gaps: z.array(WorkbookGap.extend({ revision_occurrence_id: z.string().optional() })),
});
export type WorkbookReportData = z.infer<typeof WorkbookReport>;

type Pair = { before?: WorkbookSheetData; after?: WorkbookSheetData; association: WorkbookChangeData['association']; method: string };
function uniqueGroups<T>(values: T[], key: (v: T) => string): Map<string, T[]> {
  const map = new Map<string, T[]>(); for (const v of values) { const k = key(v); const group = map.get(k); if (group) group.push(v); else map.set(k, [v]); } return map;
}
function resolvedStyle(c:WorkbookCellData,revision:WorkbookRevisionData){if(!c.style_ref)return c.style;const value=revision.style_definitions?.[c.style_ref];if(!value)throw new DocverError('WORKBOOK_STYLE_SCOPE','Cell style definition is missing in its source occurrence');return value;}
const cellContent = (c: WorkbookCellData,revision:WorkbookRevisionData) => [c.column, c.value_type, c.value, c.formula, c.formula_interpretation, c.number_format, resolvedStyle(c,revision), c.hidden_column, c.hidden_row];
function sheetContent(s: WorkbookSheetData,revision:WorkbookRevisionData) { return hash(s.cells.map(c=>cellContent(c,revision))); }
function sheetPairs(before: WorkbookSheetData[], after: WorkbookSheetData[],beforeRevision:WorkbookRevisionData,afterRevision:WorkbookRevisionData): Pair[] {
  const left = new Set(before), right = new Set(after), pairs: Pair[] = [];
  function match(key: (s: WorkbookSheetData,revision:WorkbookRevisionData) => string, method: string) {
    const a = uniqueGroups([...left], s=>key(s,beforeRevision)), b = uniqueGroups([...right], s=>key(s,afterRevision));
    for (const [k, values] of a) if (values.length === 1 && b.get(k)?.length === 1) {
      const x = values[0], y = b.get(k)![0]; pairs.push({ before: x, after: y, association: 'inferred', method }); left.delete(x); right.delete(y);
    }
  }
  match(s => s.name, 'unique_exact_sheet_name');
  // Empty sheets do not establish rename identity. No fuzzy name/index guess.
  match((s,revision) => s.cells.length ? sheetContent(s,revision) : 'empty:' + s.sheet_id, 'unique_exact_sheet_content');
  for (const s of left) pairs.push({ before: s, association: 'needs_review', method: 'unmatched_sheet_observation' });
  for (const s of right) pairs.push({ after: s, association: 'needs_review', method: 'unmatched_sheet_observation' });
  return pairs;
}

type Row = { row: number; cells: WorkbookCellData[] };
function rows(s: WorkbookSheetData): Row[] {
  const map = new Map<number, WorkbookCellData[]>(); for (const c of s.cells) { const list = map.get(c.row); if (list) list.push(c); else map.set(c.row, [c]); }
  return [...map].sort((a, b) => a[0] - b[0]).map(([row, cells]) => ({ row, cells: cells.sort((a, b) => a.column - b.column) }));
}
const firstKey = (r: Row) => { const c = r.cells.find(c => c.column === 1); return c && c.value !== null && c.value !== '' && c.formula === null && c.formula_interpretation!=='unresolved' ? canonical([c.value_type, c.value]) : ''; };
const rowContent = (r: Row,revision:WorkbookRevisionData) => hash(r.cells.map(c=>cellContent(c,revision)));
function dateLike(cell:WorkbookCellData){if(cell.value_type==='date'||cell.value_type==='time')return true;if(cell.value_type!=='number'||cell.number_format===null)return false;const format=cell.number_format.replace(/"(?:[^"]|"")*"/g,'').replace(/\\./g,'').replace(/\[(?![hms]+\])[^\]]+\]/gi,'');return /[ymdhs]/i.test(format);}

// Exact decimal normalization avoids IEEE-754 rounding and preserves original lexical values.
function normalizedNumber(value: string | null) {
  if (value === null) return null;
  const match = /^([+-]?)(\d*)(?:\.(\d*))?(?:[eE]([+-]?\d+))?$/.exec(value); if (!match || !(match[2] || match[3])) return value;
  if ((match[4] ?? '').length > 12) return value;
  const exponent = BigInt(match[4] ?? '0') - BigInt((match[3] ?? '').length); let digits = ((match[2] ?? '') + (match[3] ?? '')).replace(/^0+/, '');
  if (!digits) return '0'; const trailing = /0+$/.exec(digits)?.[0].length ?? 0; digits = digits.slice(0, digits.length - trailing); return `${match[1] === '-' ? '-' : ''}${digits}e${exponent + BigInt(trailing)}`;
}
function rowPairs(a: Row[], b: Row[],beforeRevision:WorkbookRevisionData,afterRevision:WorkbookRevisionData) {
  const left = new Set(a), right = new Set(b), pairs: { before?: Row; after?: Row; association: WorkbookChangeData['association']; method: string }[] = [];
  const anchor = (key: (r: Row,revision:WorkbookRevisionData) => string, method: string) => {
    const x = uniqueGroups([...left], r=>key(r,beforeRevision)), y = uniqueGroups([...right], r=>key(r,afterRevision));
    for (const [k, values] of x) if (k && values.length === 1 && y.get(k)?.length === 1) { const before = values[0], after = y.get(k)![0]; pairs.push({ before, after, association: 'inferred', method }); left.delete(before); right.delete(after); }
  };
  // A shared nonempty first column is an explicitly inferred key, not user-confirmed identity.
  anchor(firstKey, 'unique_nonempty_first_column_key');
  anchor(rowContent, 'unique_exact_row_content');
  const byRow = new Map([...right].map(r => [r.row, r]));
  for (const before of [...left]) { const after = byRow.get(before.row); if (after) { pairs.push({ before, after, association: 'needs_review', method: 'physical_row_fallback' }); left.delete(before); right.delete(after); } }
  for (const before of left) pairs.push({ before, association: 'needs_review', method: 'unmatched_row_observation' });
  for (const after of right) pairs.push({ after, association: 'needs_review', method: 'unmatched_row_observation' });
  return pairs;
}

export function diffWorkbooks(before: WorkbookRevisionData, after: WorkbookRevisionData, signal?: AbortSignal): WorkbookChangeData[] {
  const result: WorkbookChangeData[] = [];
  const add = (pair: Pair, kind: WorkbookChangeData['kind'], description: string, x: WorkbookCellData | null = null, y: WorkbookCellData | null = null, association = pair.association, method = pair.method) => {
    if (result.length >= 100_000) throw new DocverError('WORKBOOK_DIFF_LIMIT', 'Workbook exceeds 100,000 change observations; no partial report is committed');
    const data = { kind, from_revision_occurrence_id: before.revision_occurrence_id, to_revision_occurrence_id: after.revision_occurrence_id, from_sheet_id: pair.before?.sheet_id ?? null, to_sheet_id: pair.after?.sheet_id ?? null, before_address: x?.address ?? null, after_address: y?.address ?? null, before: x, after: y, association, alignment_method: method, description };
    result.push({ change_id: workbookID('wchg', data), ...data });
  };
  if (before.date_system !== after.date_system) add({ association: 'needs_review', method: 'different_date_systems' }, 'date_system', `Date system changed from ${before.date_system} to ${after.date_system}; stored numeric dates are not converted or equated`);
  if (before.format === after.format && canonical(before.calc_flags) !== canonical(after.calc_flags)) add({association:'exact',method:'observed_calculation_settings'},'calculation_settings','Supported stored calculation flags changed; this neither executes recalculation nor certifies cached-result freshness');
  for (const pair of sheetPairs(before.sheets, after.sheets,before,after)) {
    signal?.throwIfAborted(); const a = pair.before, b = pair.after;
    if (!a || !b) { add(pair, 'sheet_observation', 'Sheet observed only on one endpoint; correspondence requires review, not confirmed addition/deletion'); continue; }
    const sheetStructureComparable=before.format!=='csv'&&after.format!=='csv';
    if (sheetStructureComparable&&a.name !== b.name) add(pair, 'sheet_name', `Sheet name: ${a.name} → ${b.name}`);
    if (sheetStructureComparable&&a.index !== b.index) add(pair, 'sheet_position', `Sheet index: ${a.index} → ${b.index}`);
    if (sheetStructureComparable&&a.hidden !== b.hidden) add(pair, 'sheet_visibility', `Sheet hidden: ${a.hidden} → ${b.hidden}`);
    if (before.format===after.format&&(canonical(a.row_metadata) !== canonical(b.row_metadata) || canonical(a.column_metadata) !== canonical(b.column_metadata))) add(pair, 'sheet_dimensions', 'Supported row/column dimensions or hidden ranges changed, including unmaterialized blank cells');
    if (sheetStructureComparable&&canonical([...a.merges].sort()) !== canonical([...b.merges].sort())) add(pair, 'merges', 'Merged range observations changed');
    for (const row of rowPairs(rows(a), rows(b),before,after)) {
      signal?.throwIfAborted(); const x = row.before, y = row.after;
      if (!x || !y) { for (const c of x?.cells ?? y!.cells) add(pair, 'row_correspondence', 'Cell observed on an unmatched row; no confirmed semantic deletion/addition', x ? c : null, y ? c : null, 'needs_review', row.method); continue; }
      if (x.row !== y.row) add(pair, 'row_position', `Inferred corresponding row moved from ${x.row} to ${y.row}`, x.cells[0] ?? null, y.cells[0] ?? null, row.association, row.method);
      const ca = new Map(x.cells.map(c => [c.column, c])), cb = new Map(y.cells.map(c => [c.column, c]));
      for (const col of [...new Set([...ca.keys(), ...cb.keys()])].sort((a, b) => a - b)) {
        const l = ca.get(col), r = cb.get(col);
        if (!l || !r) { add(pair, 'cell_observation', 'Materialized cell present on one endpoint; missing observation is distinct from explicit blank/zero', l ?? null, r ?? null, row.association, row.method); continue; }
        const untyped = before.format === 'csv' || after.format === 'csv', crossDialect = l.formula_dialect !== r.formula_dialect && l.formula !== null && r.formula !== null;
        const unresolvedFormula = l.formula_interpretation==='unresolved'||r.formula_interpretation==='unresolved';
        const uncertainDateRepresentation=before.format!==after.format&&(dateLike(l)||dateLike(r));
        if(uncertainDateRepresentation&&canonical([l.value,l.value_type])!==canonical([r.value,r.value_type]))add(pair,'cell_observation','Numeric date/time serial and ISO/date/time source representations are not normalized across formats; equivalence is unavailable and this is not an asserted value/type edit.',l,r,'needs_review','cross_format_date_representation');
        if(unresolvedFormula&&canonical([l.formula,l.value,l.value_type,l.cached_result,l.formula_interpretation])!==canonical([r.formula,r.value,r.value_type,r.cached_result,r.formula_interpretation]))add(pair,'cell_observation','Raw cell/formula/cache observations changed; shared/array/spill formula role is unresolved. This is not an asserted formula removal, direct-input edit or recalculated result.',l,r,'needs_review','unresolved_formula_interpretation');
        const comparableNumber = l.value_type === 'number' && r.value_type === 'number', comparableBoolean = l.value_type === 'boolean' && r.value_type === 'boolean';
        const observedValue = (c:WorkbookCellData) => comparableNumber ? normalizedNumber(c.value) : comparableBoolean && c.value !== null ? (c.value==='true'||c.value==='1'?'true':'false') : c.value;
        const missingFormulaCache = (l.formula!==null&&l.cached_result==='missing')||(r.formula!==null&&r.cached_result==='missing');
        const fields: [WorkbookChangeData['kind'], unknown, unknown, string][] = [
          ...(!missingFormulaCache&&!unresolvedFormula&&!uncertainDateRepresentation ? [['stored_value', observedValue(l), observedValue(r), 'Stored value changed; formula results may be stale']] as [WorkbookChangeData['kind'],unknown,unknown,string][]:[]),
          ...(!untyped && !crossDialect && !unresolvedFormula ? [['formula', l.formula, r.formula, 'Formula source changed; formulas were not recalculated']] as [WorkbookChangeData['kind'], unknown, unknown, string][] : []),
          ...(!untyped ? [
          ...(!unresolvedFormula&&!uncertainDateRepresentation ? [['value_type', l.value_type, r.value_type, 'Stored value type changed']] as [WorkbookChangeData['kind'],unknown,unknown,string][]:[]),
          ...(!unresolvedFormula ? [['cache_availability', l.cached_result, r.cached_result, 'Saved formula result availability changed; a missing cache is not a deleted cell']] as [WorkbookChangeData['kind'],unknown,unknown,string][] : []),
          ...(before.format===after.format ? [ ['number_format', l.number_format, r.number_format, 'Number format changed'],['style', resolvedStyle(l,before), resolvedStyle(r,after), 'Supported basic style changed'] ] as [WorkbookChangeData['kind'],unknown,unknown,string][] : []),
          ['visibility', [l.hidden_row, l.hidden_column], [r.hidden_row, r.hidden_column], 'Hidden row/column observation changed'],
          ] as [WorkbookChangeData['kind'], unknown, unknown, string][] : []),
        ];
        for (const [kind, oldValue, newValue, description] of fields) if (canonical(oldValue) !== canonical(newValue)) add(pair, kind, description, l, r, row.association, row.method);
      }
    }
  }
  return result;
}
