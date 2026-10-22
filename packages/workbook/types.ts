import { z } from 'zod';
import { hash } from '../schema/index.js';

export const WORKBOOK_SCHEMA_VERSION = 'workbook.1';
export const WORKBOOK_ENGINE_VERSION = 'workbook.1.1';
export const WorkbookFormat = z.enum(['xlsx', 'ods', 'csv']);
export type WorkbookFormatData = z.infer<typeof WorkbookFormat>;
export const CellValueType = z.enum(['blank', 'string', 'number', 'boolean', 'date', 'time', 'error']);
export const WorkbookGap = z.object({ feature: z.string(), reason: z.string(), sheet_id: z.string().optional(), address: z.string().optional() });
export const WorkbookCell = z.object({
  address: z.string(), row: z.number().int().positive(), column: z.number().int().positive(),
  value_type: CellValueType, value: z.string().nullable(), formula: z.string().nullable(),
  cached_result: z.enum(['present', 'missing', 'not_applicable']),
  cache_freshness: z.enum(['unknown', 'not_applicable']),
  formula_dialect: z.enum(['xlsx_a1', 'ods_openformula']).nullable(),
  formula_interpretation: z.enum(['explicit', 'not_formula', 'unresolved']).optional(),
  number_format: z.string().nullable(), style: z.record(z.string(), z.string()),
  style_ref: z.string().regex(/^wstyle_[a-f0-9]{64}$/).optional(),
  hidden_row: z.boolean(), hidden_column: z.boolean(),
  source_ref: z.string(),
  blank_style_only: z.literal(true).optional(),
  source_range: z.string().optional(),
});
// Optional in workbook.1 so immutable 1.0 reports retain their original identity.
// New reports use engine 1.1; these source rectangles never expand during ingestion.
export const WorkbookBlankStyleRange = z.object({
  row_start: z.number().int().min(1).max(1_048_576), row_end: z.number().int().min(1).max(1_048_576),
  column_start: z.number().int().min(1).max(16_384), column_end: z.number().int().min(1).max(16_384),
  number_format: z.string().nullable(), style: z.record(z.string(), z.string()),
  style_ref: z.string().regex(/^wstyle_[a-f0-9]{64}$/).optional(),
  hidden_row: z.boolean(), hidden_column: z.boolean(), source_ref: z.string(),
  formula_interpretation: z.literal('unresolved').optional(),
}).refine(r => r.row_start <= r.row_end && r.column_start <= r.column_end, 'Reversed blank formatting range');
export type WorkbookBlankStyleRangeData = z.infer<typeof WorkbookBlankStyleRange>;
export const WorkbookSheet = z.object({
  sheet_id: z.string(), name: z.string(), index: z.number().int().nonnegative(), hidden: z.boolean(),
  row_count: z.number().int().nonnegative(), column_count: z.number().int().nonnegative(),
  blank_style_ranges: z.array(WorkbookBlankStyleRange).max(100_000).optional(),
  cells: z.array(WorkbookCell), merges: z.array(z.string()), coverage_gaps: z.array(WorkbookGap), source_ref: z.string(),
  row_metadata: z.array(z.object({ start: z.number().int().positive(), end: z.number().int().positive(), hidden: z.boolean(), size: z.string().nullable() })),
  column_metadata: z.array(z.object({ start: z.number().int().positive(), end: z.number().int().positive(), hidden: z.boolean(), size: z.string().nullable() })),
  cell_extraction_complete: z.literal(true),
});
export const WorkbookObservation = z.object({
  style_definitions: z.record(z.string(), z.record(z.string(), z.string())).optional(),
  format: WorkbookFormat, sheets: z.array(WorkbookSheet), coverage_gaps: z.array(WorkbookGap),
  calculation: z.literal('stored_values_only_no_recalculation'),
  date_system: z.enum(['1900', '1904', 'iso8601', 'unknown']),
  calc_flags: z.record(z.string(), z.string()),
});
export type WorkbookCellData = z.infer<typeof WorkbookCell>;
export type WorkbookSheetData = z.infer<typeof WorkbookSheet>;
export type WorkbookObservationData = z.infer<typeof WorkbookObservation>;
export type WorkbookGapData = z.infer<typeof WorkbookGap>;
export const workbookID = (prefix: string, value: unknown) => `${prefix}_${hash(value)}`;
export function columnLabel(column: number): string {
  if (!Number.isInteger(column) || column < 1 || column > 16_384) throw new RangeError('Column is outside workbook bounds');
  let result = ''; for (let n = column; n > 0; n = Math.floor((n - 1) / 26)) result = String.fromCharCode(65 + (n - 1) % 26) + result; return result;
}
export function cellAddress(row: number, column: number): string {
  if (!Number.isInteger(row) || row < 1 || row > 1_048_576) throw new RangeError('Row is outside workbook bounds');
  return columnLabel(column) + row;
}
