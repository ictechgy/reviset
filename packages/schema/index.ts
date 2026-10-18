import { z } from 'zod';
import { createHash } from 'node:crypto';

export const SCHEMA_VERSION = '0.1.0';
export const ENGINE_VERSION = '0.2.0-native.ocr-render.1';
export const MAX_INPUT_BYTES=512*1024*1024;
export const MAX_PPTX_EXPANDED_BYTES=512*1024*1024;
export const MAX_PPTX_PART_BYTES=64*1024*1024;
export const canonical = (value: unknown): string => JSON.stringify(value, (_, v) =>
  v && typeof v === 'object' && !Array.isArray(v)
    ? Object.fromEntries(Object.entries(v).sort(([a], [b]) => a.localeCompare(b, 'en'))) : v);
export const hash = (value: unknown): string => createHash('sha256').update(canonical(value)).digest('hex');
export const byteHash = (bytes: Uint8Array): string => createHash('sha256').update(bytes).digest('hex');
export const id = (prefix: string, value: unknown): string => `${prefix}_${hash(value)}`;
export const normalize = (text: string): string => text.normalize('NFC').replace(/\s+/gu, ' ').trim();
export const Availability = z.enum(['available', 'unavailable', 'unsupported', 'extraction_failed']);
export const Bbox = z.tuple([z.number().min(0).max(1), z.number().min(0).max(1), z.number().min(0).max(1), z.number().min(0).max(1)])
  .refine(([x,y,w,h]) => x+w <= 1.000001 && y+h <= 1.000001, 'bbox exceeds page');
export type Box = z.infer<typeof Bbox>;
export const Capability = z.object({ text: Availability, notes: Availability, hidden_slides: Availability,
  animation: Availability, structure: Availability, preview: Availability });
export const Gap = z.object({ feature: z.string(), reason: z.string(), revision_id: z.string().optional(), page_id: z.string().optional() });
export const Element = z.object({ observation_id: z.string(), kind: z.enum(['text', 'table_cell', 'image', 'shape', 'unsupported']),
  text: z.string(), normalized_text: z.string(), bbox: Bbox, reading_order: z.number().int().nonnegative(),
  availability: Availability, method: z.string(), source_ref: z.string(), provenance: z.enum(['observed','inferred']),
  ocr:z.object({confidence:z.number().min(0).max(1),confidence_scope:z.literal('line'),numeric_consensus:z.boolean(),ambiguous:z.boolean(),alternatives:z.array(z.object({text:z.string(),confidence:z.number().min(0).max(1),truncated:z.boolean()})).max(3)}).optional(),
  media_hash: z.string().optional(),
  visibility:z.enum(['visible','occluded','partially_occluded','struck_through','struck_inferred','partially_struck_through','hidden_render_mode','uncertain','unverified']).optional(),
  visibility_spans:z.array(z.object({text:z.string(),state:z.string(),bbox:Bbox,paint_index:z.number().int().nonnegative(),assessment:z.enum(['observed','inferred'])})).optional(),
  visibility_evidence:z.array(z.object({method:z.string(),bbox:Bbox,assessment:z.enum(['observed','inferred']),coverage:z.number().min(0).max(1)})).optional(),
  table:z.object({table_id:z.string(),row:z.number().int().nonnegative(),column:z.number().int().nonnegative(),row_span:z.number().int().positive().optional(),column_span:z.number().int().positive().optional(),origin:z.enum(['ooxml_table','pdf_grid_inferred','vision_table_inferred']),assessment:z.enum(['observed','inferred'])}).optional() });
export const Page = z.object({ page_id: z.string(), asset_id: z.string(), page: z.number().int().positive(),
  width: z.number().positive(), height: z.number().positive(), coordinate_system: z.string(),
  source_transform: z.array(z.number()), hidden: z.boolean().nullable(), text: z.string(), visible_text:z.string().optional(),unresolved_text:z.string().optional(),suppressed_text:z.string().optional(),
  ocr_text:z.string().optional(),ocr_unresolved_text:z.string().optional(),comparison_basis:z.enum(['text_layer','raster_ocr']).optional(),
  raster:z.object({sha256:z.string().regex(/^[a-f0-9]{64}$/),width:z.number().int().positive(),height:z.number().int().positive(),renderer:z.string(),environment:z.string()}).optional(),
  ocr:z.object({status:z.enum(['available','no_text','unavailable','failed']),mode:z.enum(['scan','supplement','verification']).optional(),engine:z.string(),environment:z.string(),structure_status:z.string().optional(),table_count:z.number().int().nonnegative().optional(),render_sha256:z.string().optional(),width:z.number().int().positive().optional(),height:z.number().int().positive().optional(),reason:z.string().optional()}).optional(),
  preview:z.object({asset_id:z.string().regex(/^sha256:[a-f0-9]{64}$/),page:z.number().int().positive(),width:z.number().positive(),height:z.number().positive(),source_transform:z.array(z.number()).length(6),renderer:z.string(),environment:z.string(),assessment:z.literal('inferred'),warnings:z.array(z.string())}).optional(),
  elements: z.array(Element), notes: z.string().nullable(), capabilities: Capability, coverage_gaps: z.array(Gap) });
export const Asset = z.object({ asset_id: z.string(), format: z.enum(['pptx','pdf']), bytes: z.number().int().nonnegative() });
export const Revision = z.object({ revision_id: z.string(), revision_occurrence_id: z.string(), label: z.string(),
  assets: z.array(Asset), status: z.enum(['success','partial','failed']), pages: z.array(Page),
  coverage_gaps: z.array(Gap), errors: z.array(z.object({ code: z.string(), message: z.string() })),
  bundle_mapping: z.array(z.object({ source_page_id: z.string(), rendered_page_id: z.string(), score: z.number() })) });
export const Evidence = z.object({ revision_id: z.string(), revision_occurrence_id: z.string(), asset_id: z.string(),
  page_id: z.string(), page: z.number().int().positive(), observation_id: z.string().optional(),
  bbox: Bbox, quote: z.string(), method: z.string(),provenance:z.enum(['observed','inferred']).optional(),render_sha256:z.string().regex(/^[a-f0-9]{64}$/).optional() });
export const Match = z.object({ from_page_id: z.string(), to_page_id: z.string(), score: z.number().min(0).max(1),
  status: z.enum(['inferred','human_confirmed','needs_review']), reasons: z.array(z.string()) });
export const Decision = z.object({ from_page_id: z.string(), to_page_id: z.string(), action: z.enum(['link','unlink']), reason: z.string().min(1) });
export type MappingDecision = z.infer<typeof Decision>;
export const Change = z.object({ schema_version: z.literal(SCHEMA_VERSION), report_id: z.string(), change_id: z.string(), entity_id: z.string(),
  from_revision: z.string(), to_revision: z.string(), from_occurrence: z.string(), to_occurrence: z.string(),
  kind: z.enum(['page_added','page_deleted','page_moved','text_modified','text_struck_through','text_occluded','text_revealed','visual_region_changed','coverage_gap']),
  before: z.string().nullable(), after: z.string().nullable(), appearance_assessment:z.enum(['observed','inferred']).optional(),text_assessment:z.enum(['observed','inferred']).optional(),text_scope:z.enum(['page','region']).optional(), evidence: z.array(Evidence),
  lineage: z.object({ status: z.enum(['inferred','human_confirmed','needs_review']), score: z.number(), reasons: z.array(z.string()) }),
  coverage_gaps: z.array(Gap), evidence_uri: z.string() });
export const Lineage = z.object({ entity_id: z.string(), page_ids: z.array(z.string()), status: z.enum(['inferred','needs_review','human_confirmed']) });
export const Report = z.object({ schema_version: z.literal(SCHEMA_VERSION), engine_version: z.string(), report_id: z.string(), project_id: z.string(),
  timeline_revision_id: z.string(), mapping_revision_id: z.string(), schema_hash: z.string(), observation_environment: z.record(z.string(), z.string()),
  revisions: z.array(Revision), matches: z.array(Match), candidates: z.array(Match), mapping_decisions: z.array(Decision),
  lineages: z.array(Lineage), changes: z.array(Change), coverage_gaps: z.array(Gap) });
export const SCHEMA_HASH=hash(z.toJSONSchema(Report));
export type ReportData = z.infer<typeof Report>;
export type PageData = z.infer<typeof Page>;
export type RevisionData = z.infer<typeof Revision>;
export type ElementData = z.infer<typeof Element>;
export type ChangeData = z.infer<typeof Change>;
export type MatchData = z.infer<typeof Match>;
export const comparisonText=(p:PageData):string=>p.comparison_basis==='raster_ocr'?p.ocr_text??'':p.visible_text??p.text;
export const unresolvedComparisonText=(p:PageData):string=>p.comparison_basis==='raster_ocr'?p.ocr_unresolved_text??'':p.unresolved_text??'';
export const Manifest = z.object({ project_id: z.string().regex(/^[a-zA-Z0-9_-]{1,100}$/), title: z.string(),
  revisions: z.array(z.object({ label: z.string(), files: z.array(z.string().min(1)).min(1).max(2) })).min(1),
  mapping_decisions: z.array(Decision).default([]) });
export const FixtureMetadata=z.object({seed:z.number().int(),generator_version:z.string(),generators:z.record(z.string(),z.string()),
  assets:z.record(z.string(),z.string().regex(/^sha256:[a-f0-9]{64}$/)),
  expected:z.object({revenue:z.array(z.string()),temporary:z.object({added:z.number().int(),deleted:z.number().int()}).optional(),ambiguity:z.boolean().optional(),hidden:z.boolean().optional(),scan:z.boolean().optional(),inconsistent:z.boolean().optional()}),
  mapping:z.array(z.object({version:z.number().int().positive(),pages:z.array(z.object({key:z.string(),source_page:z.number().int().positive(),hidden:z.boolean()}))})),
  allowed_loss:z.array(z.string()),reference:z.string()});
export type InputManifest = z.infer<typeof Manifest>;
export class DocverError extends Error {
  constructor(public code: string, message: string) { super(message); }
}
// Offsets are UTF-16 code units, with boundaries kept on complete Unicode scalars.
export function textChunk(text:string,offset:number,length:number):string{
  const high=(v:number)=>v>=0xd800&&v<=0xdbff,low=(v:number)=>v>=0xdc00&&v<=0xdfff;
  if(offset>0&&low(text.charCodeAt(offset))&&high(text.charCodeAt(offset-1)))throw new DocverError('TEXT_OFFSET','Text offset splits a Unicode scalar; use the returned next offset');
  let end=Math.min(text.length,offset+length);
  if(end<text.length&&end>offset&&high(text.charCodeAt(end-1))&&low(text.charCodeAt(end)))end=end-1===offset?end+1:end-1;
  return text.slice(offset,end);
}
export function box(x: number,y: number,w: number,h: number): Box {
  const left=Math.min(1,Math.max(0,x)), top=Math.min(1,Math.max(0,y));
  return [left,top,Math.min(1-left,Math.max(0,w)),Math.min(1-top,Math.max(0,h))];
}
