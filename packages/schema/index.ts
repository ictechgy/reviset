import { z } from 'zod';
import { createHash } from 'node:crypto';
import {comparisonRegions,pageSimilarity} from './page-similarity.js';
export {normalize,comparisonRegions} from './page-similarity.js';

export const SCHEMA_VERSION = '0.4.0';
const StoredSchemaVersion=z.enum(['0.1.0','0.2.0','0.3.0','0.4.0']);
export const ENGINE_VERSION = '0.4.0-native.bundle.53';
export const MAX_INPUT_BYTES=512*1024*1024;
export const MAX_PPTX_EXPANDED_BYTES=512*1024*1024;
export const MAX_PPTX_PART_BYTES=64*1024*1024;
export const canonical = (value: unknown): string => JSON.stringify(value, (_, v) =>
  v && typeof v === 'object' && !Array.isArray(v)
    ? Object.fromEntries(Object.entries(v).sort(([a], [b]) => a.localeCompare(b, 'en'))) : v);
export const hash = (value: unknown): string => createHash('sha256').update(canonical(value)).digest('hex');
export const byteHash = (bytes: Uint8Array): string => createHash('sha256').update(bytes).digest('hex');
export const id = (prefix: string, value: unknown): string => `${prefix}_${hash(value)}`;
export const Availability = z.enum(['available', 'unavailable', 'unsupported', 'extraction_failed']);
export const Bbox = z.tuple([z.number().min(0).max(1), z.number().min(0).max(1), z.number().min(0).max(1), z.number().min(0).max(1)])
  .refine(([x,y,w,h]) => x+w <= 1.000001 && y+h <= 1.000001, 'bbox exceeds page');
export type Box = z.infer<typeof Bbox>;
const RoiCandidate=z.object({text:z.string().min(1).max(128),confidence:z.number().min(0).max(1)});
export const OcrReconsideration=z.object({
  status:z.enum(['available','budget_exceeded','unsupported_bitmap','unsupported_background','empty_ink','failed']),
  band_bbox:Bbox,ink_pixels:z.number().int().positive().max(4_000_000).optional(),threshold:z.number().int().min(0).max(240).optional(),
  primary_empty_characters:z.array(z.object({offset:z.number().int().min(0).max(127),text:z.string().min(1).max(128),bbox:Bbox,ink_pixels:z.literal(0),method:z.literal('uniform_white_pixels_with_1px_margin')})).max(128).optional(),
  contexts:z.array(z.object({languages:z.array(z.enum(['en-US','ko-KR'])).min(1).max(2),padding:z.union([z.literal(.25),z.literal(.75)]),scale:z.union([z.literal(1),z.literal(2)]),crop_bbox:Bbox,
    status:z.enum(['available','not_detected','contaminated','edge_cut','ambiguous','failed','budget_exceeded']),
    observations:z.array(RoiCandidate.extend({bbox:Bbox,token_bboxes:z.array(Bbox).max(32),alternatives:z.array(RoiCandidate).max(3),ink_coverage:z.number().min(0).max(1)})).max(8)
  })).max(8)
});
export type OcrReconsiderationData=z.infer<typeof OcrReconsideration>;
export const Capability = z.object({ text: Availability, notes: Availability, hidden_slides: Availability,
  animation: Availability, structure: Availability, preview: Availability });
export const GridStatus=z.enum(['available','not_detected','insufficient_text','unsupported_format','unsupported_dimensions','budget_exceeded','ambiguous_boundaries','partial']);
export const OfficeInputPreparation=z.object({policy:z.string().min(1).max(128),source_sha256:z.string().regex(/^[a-f0-9]{64}$/),input_sha256:z.string().regex(/^[a-f0-9]{64}$/),changed_properties:z.number().int().min(0).max(40000000),unsupported_parts:z.number().int().min(0).max(100000),skip_reason:z.enum(['signed_package','ambiguous_part_names','unsupported_package_metadata','derivation_budget_exceeded']).optional()});
export type OfficeInputPreparationData=z.infer<typeof OfficeInputPreparation>;
export const Gap = z.object({ feature: z.string(), reason: z.string(), revision_id: z.string().optional(), page_id: z.string().optional() });
export const Element = z.object({ observation_id: z.string(), kind: z.enum(['text', 'table_cell', 'image', 'shape', 'unsupported']),
  text: z.string(), normalized_text: z.string(), bbox: Bbox, reading_order: z.number().int().nonnegative(),
  availability: Availability, method: z.string(), source_ref: z.string(), provenance: z.enum(['observed','inferred']),
  comparison_role:z.enum(['selected','unresolved','shadowed','excluded']).optional(),comparison_reason:z.string().optional(),comparison_order:z.number().int().nonnegative().optional(),
  ocr:z.object({confidence:z.number().min(0).max(1),confidence_scope:z.literal('line'),strike_status:z.string().optional(),numeric_consensus:z.boolean(),ambiguous:z.boolean(),alternatives:z.array(z.object({text:z.string(),confidence:z.number().min(0).max(1),truncated:z.boolean()})).max(3),
    reconsideration_observation:OcrReconsideration.optional(),
    reconsideration:z.object({method:z.literal('vision_multicontext_roi'),primary_source_ref:z.string(),primary_text:z.string().max(128),primary_confidence:z.number().min(0).max(1),primary_bbox:Bbox,observation:OcrReconsideration}).optional()
  }).optional(),
  media_hash: z.string().optional(),
  visibility:z.enum(['visible','occluded','partially_occluded','struck_through','struck_inferred','partially_struck_through','hidden_render_mode','uncertain','unverified']).optional(),
  visibility_spans:z.array(z.object({text:z.string(),state:z.string(),bbox:Bbox,paint_index:z.number().int().nonnegative(),assessment:z.enum(['observed','inferred'])})).optional(),
  visibility_evidence:z.array(z.object({method:z.string(),bbox:Bbox,assessment:z.enum(['observed','inferred']),coverage:z.number().min(0).max(1)})).optional(),
  table:z.object({table_id:z.string(),row:z.number().int().nonnegative(),column:z.number().int().nonnegative(),row_span:z.number().int().positive().optional(),column_span:z.number().int().positive().optional(),origin:z.enum(['ooxml_table','pdf_grid_inferred','vision_table_inferred']),assessment:z.enum(['observed','inferred'])}).optional() });
export const NativeRaster=z.object({sha256:z.string().regex(/^[a-f0-9]{64}$/),width:z.number().int().positive(),height:z.number().int().positive(),renderer:z.string(),environment:z.string(),page_box:z.literal('cropBox').optional(),rotation:z.number().int().optional(),render_policy:z.literal('pdfkit-300dpi-max4096-source-color-profile-v1').optional()});
const ReferenceCoordinates={kind:z.literal('reference_pdf'),asset_id:z.string().regex(/^sha256:[a-f0-9]{64}$/),source_page_id:z.string(),page:z.number().int().positive(),width:z.number().positive(),height:z.number().positive(),source_transform:z.array(z.number()).length(6)};
export const ReferenceAppearance=z.discriminatedUnion('association',[
  z.object({...ReferenceCoordinates,raster:NativeRaster,association:z.literal('inferred'),score:z.number().min(.95).max(1),policy:z.literal('qualified-full-bundle-v1')}),
  z.object({...ReferenceCoordinates,raster:NativeRaster.optional(),association:z.literal('human_confirmed'),score:z.number().min(0).max(1),policy:z.literal('human-bundle-v1'),decision_id:z.string(),reason:z.string().max(2000).refine(v=>v.length<=2000&&v.trim().length>0)})
]);
export const Page = z.object({ page_id: z.string(), asset_id: z.string(), page: z.number().int().positive(),
  width: z.number().positive(), height: z.number().positive(), coordinate_system: z.string(),
  source_transform: z.array(z.number()), hidden: z.boolean().nullable(), text: z.string(), visible_text:z.string().optional(),unresolved_text:z.string().optional(),suppressed_text:z.string().optional(),
  ocr_text:z.string().optional(),ocr_unresolved_text:z.string().optional(),comparison_basis:z.enum(['text_layer','raster_ocr','hybrid_regions_v1']).optional(),
  raster:NativeRaster.optional(),appearance:ReferenceAppearance.optional(),
  ocr:z.object({status:z.enum(['available','no_text','unavailable','failed']),mode:z.enum(['scan','supplement','verification']).optional(),engine:z.string(),environment:z.string(),structure_status:z.string().optional(),grid_status:GridStatus.optional(),grid_reasons:z.array(z.string()).max(20).optional(),bitmap_format:z.number().int().nonnegative().optional(),bitmap_bits_per_sample:z.number().int().positive().optional(),bitmap_bits_per_pixel:z.number().int().positive().optional(),table_count:z.number().int().nonnegative().optional(),render_sha256:z.string().optional(),width:z.number().int().positive().optional(),height:z.number().int().positive().optional(),reason:z.string().optional()}).optional(),
  preview:z.object({asset_id:z.string().regex(/^sha256:[a-f0-9]{64}$/),page:z.number().int().positive(),width:z.number().positive(),height:z.number().positive(),source_transform:z.array(z.number()).length(6),renderer:z.string(),environment:z.string(),assessment:z.literal('inferred'),warnings:z.array(z.string()),input_preparation:OfficeInputPreparation.optional()}).optional(),
  elements: z.array(Element), notes: z.string().nullable(), capabilities: Capability, coverage_gaps: z.array(Gap) });
export const Asset = z.object({ asset_id: z.string(), format: z.enum(['pptx','pdf']), bytes: z.number().int().nonnegative() });
const BundleMapping=z.object({source_page_id:z.string(),rendered_page_id:z.string(),score:z.number(),association:z.enum(['inferred','human_confirmed']).optional(),decision_id:z.string().optional()});
export const Revision = z.object({ revision_id: z.string(), revision_occurrence_id: z.string(), label: z.string(),
  assets: z.array(Asset), status: z.enum(['success','partial','failed']), pages: z.array(Page),
  reference_appearance_policy:z.enum(['qualified-full-bundle-v1','bundle-reference-v2']).optional(),
  coverage_gaps: z.array(Gap), errors: z.array(z.object({ code: z.string(), message: z.string() })),
  bundle_mapping_basis:z.array(z.object({source_page_id:z.string(),rendered_page_id:z.string(),score:z.number().min(0).max(1)})).optional(),
  bundle_mapping:z.array(BundleMapping) });
export const Evidence = z.object({ revision_id: z.string(), revision_occurrence_id: z.string(), asset_id: z.string(),
  page_id: z.string(), page: z.number().int().positive(), observation_id: z.string().optional(),
  bbox: Bbox, quote: z.string(), method: z.string(),provenance:z.enum(['observed','inferred']).optional(),render_sha256:z.string().regex(/^[a-f0-9]{64}$/).optional() });
export const Match = z.object({ from_page_id: z.string(), to_page_id: z.string(), score: z.number().min(0).max(1),
  status: z.enum(['inferred','human_confirmed','needs_review']), reasons: z.array(z.string()),relation_id:z.string().optional(),relation_kind:z.enum(['continuation','split','merge']).optional() });
export const StoredDecision = z.object({ from_page_id: z.string(), to_page_id: z.string(), action: z.enum(['link','unlink']), reason:z.string().min(1) });
export const Decision = z.object({ from_page_id: z.string(), to_page_id: z.string(), action: z.enum(['link','unlink']), reason: z.string().max(2000).refine(s=>s.length<=2000,'Reason exceeds2000UTF16 units').refine(s=>s.trim().length>0,'Reason cannot be blank') });
export type MappingDecision = z.infer<typeof Decision>;
export const RelationSelection=z.object({kind:z.enum(['continuation','split','merge']),from_occurrence:z.string().min(1).max(160),to_occurrence:z.string().min(1).max(160),from_page_ids:z.array(z.string().min(1).max(160)).min(1).max(32),to_page_ids:z.array(z.string().min(1).max(160)).min(1).max(32),reason:z.string().max(2000).refine(s=>s.length<=2000,'Reason exceeds2000UTF16 units').refine(s=>s.trim().length>0,'Reason cannot be blank')});
export const MappingRelation=RelationSelection.extend({relation_id:z.string()});
export type RelationSelectionData=z.infer<typeof RelationSelection>;
export type MappingRelationData=z.infer<typeof MappingRelation>;
const BundleID=z.string().regex(/^[a-zA-Z0-9_-]{1,160}$/),BundleAsset=z.string().regex(/^sha256:[a-f0-9]{64}$/);
const BundleReason=z.string().max(2000).refine(v=>v.length<=2000&&v.trim().length>0,'A nonblank reason of at most2000UTF16 units is required');
const BundleSelectionFields={revision_occurrence_id:BundleID,source_asset_id:BundleAsset,rendered_asset_id:BundleAsset,source_page_id:BundleID,rendered_page_id:BundleID.nullable(),action:z.enum(['link','unlink']),reason:BundleReason};
export const BundleSelection=z.object(BundleSelectionFields).refine(v=>v.action!=='link'||v.rendered_page_id!==null,'Link requires a PDF page');
export const BundlePriorPair=z.object({source_page_id:BundleID,rendered_page_id:BundleID,score:z.number().min(0).max(1),association:z.enum(['inferred','human_confirmed']),decision_id:BundleID.optional()}).refine(v=>v.association!=='human_confirmed'||!!v.decision_id,'A prior human pair requires its decision ID');
export const BundleDecision=z.object({...BundleSelectionFields,score:z.number().min(0).max(1).nullable(),decision_id:BundleID,basis_report_id:BundleID,ordinal:z.number().int().nonnegative(),previous_decision_id:BundleID.nullable(),displaced:z.array(BundlePriorPair).max(2)}).refine(v=>v.action==='link'?v.rendered_page_id!==null&&v.score!==null:v.score===null,'Link requires a PDF page and score; unlink has no score');
export type BundleSelectionData=z.infer<typeof BundleSelection>;
export type BundleDecisionData=z.infer<typeof BundleDecision>;
export interface BundleDirective {decision:BundleDecisionData;source_page_id:string;rendered_page_id:string|null;action:'link'|'unlink';displaced:boolean}
function advanceBundleDirective(state:Map<string,BundleDirective>,owners:Map<string,string>,decision:BundleDecisionData):void {
  const remove=(source:string)=>{const prior=state.get(source);if(prior?.action==='link'&&prior.rendered_page_id&&owners.get(prior.rendered_page_id)===source)owners.delete(prior.rendered_page_id);};
  for(const pair of decision.displaced)if(pair.source_page_id!==decision.source_page_id){remove(pair.source_page_id);state.set(pair.source_page_id,{decision,source_page_id:pair.source_page_id,rendered_page_id:pair.rendered_page_id,action:'unlink',displaced:true});}
  remove(decision.source_page_id);
  if(decision.action==='link'&&decision.rendered_page_id){const conflict=owners.get(decision.rendered_page_id);if(conflict&&conflict!==decision.source_page_id){remove(conflict);state.set(conflict,{decision,source_page_id:conflict,rendered_page_id:decision.rendered_page_id,action:'unlink',displaced:true});}owners.set(decision.rendered_page_id,decision.source_page_id);}
  state.set(decision.source_page_id,{decision,source_page_id:decision.source_page_id,rendered_page_id:decision.rendered_page_id,action:decision.action,displaced:false});
}
export function bundleDirectiveState(entries:BundleDecisionData[]):Map<string,BundleDirective>{
  const state=new Map<string,BundleDirective>(),owners=new Map<string,string>();for(const decision of entries)advanceBundleDirective(state,owners,decision);return state;
}
/** Full replay starts at raw automatic pairs, never at an already edited mapping. */
export function replayBundleMappings(revisions:z.infer<typeof Revision>[],entries:BundleDecisionData[]):Map<string,z.infer<typeof BundlePriorPair>>|undefined {
  // Pages stay fixed during a replay. Repeated confirmations must recheck the
  // same derived score, without re-tokenizing long pages for every log entry.
  // Keep this cache local: the caller may change observations between replays.
  const scoreCache=new Map<PageData,Map<PageData,number>>();
  const cachedSimilarity=(a:PageData,b:PageData):number=>{let row=scoreCache.get(a);if(!row){row=new Map();scoreCache.set(a,row);}const found=row.get(b);if(found!==undefined)return found;const score=pageSimilarity(a,b);row.set(b,score);return score;};
  const locations=new Map(revisions.flatMap(revision=>revision.pages.map(page=>[page.page_id,{revision,page}] as const))),known=new Map<string,BundleDecisionData>(),pairs=new Map<string,z.infer<typeof BundlePriorPair>>(),owners=new Map<string,string>(),affected=new Set(entries.map(d=>d.revision_occurrence_id));
  for(const revision of revisions.filter(r=>affected.has(r.revision_occurrence_id))){
    if(!revision.bundle_mapping_basis||revision.assets.length!==2)return undefined;
    const targets=new Set<string>();
    for(const pair of revision.bundle_mapping_basis){
      const source=locations.get(pair.source_page_id),target=locations.get(pair.rendered_page_id);
      if(!source||!target||source.revision!==revision||target.revision!==revision||!revision.assets.some(a=>a.asset_id===source.page.asset_id&&a.format==='pptx')||!revision.assets.some(a=>a.asset_id===target.page.asset_id&&a.format==='pdf')||pairs.has(pair.source_page_id)||targets.has(pair.rendered_page_id))return undefined;
      pairs.set(pair.source_page_id,{...pair,association:'inferred'});owners.set(pair.rendered_page_id,pair.source_page_id);targets.add(pair.rendered_page_id);
    }
  }
  for(const [index,entry]of entries.entries()){
    const {decision_id,...payload}=entry;
    if(entry.ordinal!==index||entry.previous_decision_id!==(entries[index-1]?.decision_id??null)||decision_id!==id('bdec',payload)||known.has(decision_id))return undefined;
    const source=locations.get(entry.source_page_id),target=entry.rendered_page_id?locations.get(entry.rendered_page_id):undefined;
    if(!source||source.revision.revision_occurrence_id!==entry.revision_occurrence_id||source.page.asset_id!==entry.source_asset_id||!source.revision.assets.some(a=>a.asset_id===entry.source_asset_id&&a.format==='pptx')||!source.revision.assets.some(a=>a.asset_id===entry.rendered_asset_id&&a.format==='pdf'))return undefined;
    if(entry.rendered_page_id&&(!target||target.revision!==source.revision||target.page.asset_id!==entry.rendered_asset_id))return undefined;
    if(entry.action==='link'&&(!target||entry.score===null)||entry.action==='unlink'&&entry.score!==null)return undefined;
    if(entry.action==='link'&&entry.score!==cachedSimilarity(source.page,target!.page))return undefined;
    const conflictSources=new Set([entry.source_page_id,...(entry.action==='link'&&entry.rendered_page_id?[owners.get(entry.rendered_page_id)??'']:[])]),conflicts=[...conflictSources].map(source=>pairs.get(source)).filter((p):p is z.infer<typeof BundlePriorPair>=>!!p),sort=(a:z.infer<typeof BundlePriorPair>,b:z.infer<typeof BundlePriorPair>)=>a.source_page_id.localeCompare(b.source_page_id,'en')||a.rendered_page_id.localeCompare(b.rendered_page_id,'en');
    if(canonical(conflicts.sort(sort))!==canonical([...entry.displaced].sort(sort)))return undefined;
    if(entry.action==='unlink'&&entry.rendered_page_id!==null&&!conflicts.some(p=>p.source_page_id===entry.source_page_id&&p.rendered_page_id===entry.rendered_page_id))return undefined;
    for(const prior of conflicts){pairs.delete(prior.source_page_id);owners.delete(prior.rendered_page_id);}
    if(entry.action==='link'){pairs.set(entry.source_page_id,{source_page_id:entry.source_page_id,rendered_page_id:entry.rendered_page_id!,score:entry.score!,association:'human_confirmed',decision_id});owners.set(entry.rendered_page_id!,entry.source_page_id);}
    known.set(decision_id,entry);
  }
  return pairs;
}
export const validBundleDecisionLog=(revisions:z.infer<typeof Revision>[],entries:BundleDecisionData[]):boolean=>!!replayBundleMappings(revisions,entries);

export const Change = z.object({ schema_version: StoredSchemaVersion, report_id: z.string(), change_id: z.string(), entity_id: z.string(),
  from_revision: z.string(), to_revision: z.string(), from_occurrence: z.string(), to_occurrence: z.string(),
  kind: z.enum(['page_added','page_deleted','page_moved','text_modified','text_struck_through','text_occluded','text_revealed','visual_region_changed','coverage_gap','page_split','page_merged','page_lineage_changed']),
  topology:z.object({relation_id:z.string(),kind:z.enum(['split','merge','range_lineage']),from_page_ids:z.array(z.string()).min(1),to_page_ids:z.array(z.string()).min(1),semantics:z.enum(['direct_edges','directed_reachability'])}).optional(),before: z.string().nullable(), after: z.string().nullable(), appearance_assessment:z.enum(['observed','inferred']).optional(),text_assessment:z.enum(['observed','inferred']).optional(),text_scope:z.enum(['page','region']).optional(),region_pairing_assessment:z.literal('inferred').optional(), evidence: z.array(Evidence),
  lineage: z.object({ status: z.enum(['inferred','human_confirmed','needs_review']), score: z.number(), reasons: z.array(z.string()) }),
  coverage_gaps: z.array(Gap), evidence_uri: z.string() });
export const Lineage = z.object({ entity_id: z.string(), page_ids: z.array(z.string()), status: z.enum(['inferred','needs_review','human_confirmed']) });
export const Report = z.object({ schema_version: StoredSchemaVersion, engine_version: z.string(), report_id: z.string(), project_id: z.string(),
  timeline_revision_id: z.string(), mapping_revision_id: z.string(), schema_hash: z.string(), observation_environment: z.record(z.string(), z.string()),
  revisions: z.array(Revision), matches: z.array(Match), candidates: z.array(Match), mapping_decisions: z.array(StoredDecision),mapping_relations:z.array(MappingRelation).optional(),bundle_decisions:z.array(BundleDecision).max(10000).optional(),
  lineages: z.array(Lineage), changes: z.array(Change), coverage_gaps: z.array(Gap) }).refine(r=>r.changes.every(c=>c.schema_version===r.schema_version),'Change schema version differs from report').refine(r=>{const directives=bundleDirectiveState(r.bundle_decisions??[]);return r.revisions.every(revision=>{
    const pages=new Map(revision.pages.map(p=>[p.page_id,p])),formats=new Map(revision.assets.map(a=>[a.asset_id,a.format]));
    return revision.pages.every(page=>{
      const appearance=page.appearance;if(!appearance)return true;
      const reference=pages.get(appearance.source_page_id);
      const basic=formats.get(page.asset_id)==='pptx'&&!page.preview&&!page.raster&&!!reference&&formats.get(reference.asset_id)==='pdf'&&reference.asset_id===appearance.asset_id&&reference.page===appearance.page&&reference.width===appearance.width&&reference.height===appearance.height&&canonical(reference.source_transform)===canonical(appearance.source_transform)&&canonical(reference.raster)===canonical(appearance.raster)&&revision.bundle_mapping.some(m=>m.source_page_id===page.page_id&&m.rendered_page_id===reference.page_id&&m.score===appearance.score);
      if(!basic)return false;
      if(appearance.association==='inferred')return !directives.has(page.page_id)&&revision.bundle_mapping.some(m=>m.source_page_id===page.page_id&&m.rendered_page_id===reference!.page_id&&m.association!=='human_confirmed'&&!m.decision_id)&&!page.hidden&&['qualified-full-bundle-v1','bundle-reference-v2'].includes(revision.reference_appearance_policy??'');
      const active=directives.get(page.page_id),decision=active?.decision;
      return revision.bundle_mapping.some(m=>m.source_page_id===page.page_id&&m.rendered_page_id===reference!.page_id&&m.association==='human_confirmed'&&m.decision_id===appearance.decision_id)&&r.schema_version==='0.4.0'&&r.engine_version==='0.4.0-native.bundle.53'&&revision.reference_appearance_policy==='bundle-reference-v2'&&active?.action==='link'&&active.rendered_page_id===reference!.page_id&&decision?.decision_id===appearance.decision_id&&decision.reason===appearance.reason&&decision.source_asset_id===page.asset_id&&decision.rendered_asset_id===appearance.asset_id&&decision.revision_occurrence_id===revision.revision_occurrence_id;
    });
  });},'Reference appearance must preserve a qualified PDF observation in the same revision').refine(r=>{
    const sources=new Map<string,string>();
    for(const revision of r.revisions)for(const page of revision.pages){const appearance=page.appearance;if(!appearance||appearance.association==='human_confirmed')continue;const source=sources.get(appearance.asset_id);if(source&&source!==page.asset_id)return false;sources.set(appearance.asset_id,page.asset_id);}
    return true;
  },'A reference PDF cannot qualify against different PPTX source assets').refine(r=>!(r.bundle_decisions?.length)||r.schema_version==='0.4.0'&&r.engine_version==='0.4.0-native.bundle.53'&&validBundleDecisionLog(r.revisions,r.bundle_decisions),'Bundle decision history must preserve source scope, identity, order and displaced human provenance').refine(r=>{
    const state=bundleDirectiveState(r.bundle_decisions??[]),replayed=replayBundleMappings(r.revisions,r.bundle_decisions??[]),affected=new Set((r.bundle_decisions??[]).map(d=>d.revision_occurrence_id));
    if(!replayed)return false;
    const sourceRevision=new Map(r.revisions.flatMap(revision=>revision.pages.map(page=>[page.page_id,revision.revision_occurrence_id] as const))),expectedByRevision=new Map<string,z.infer<typeof BundlePriorPair>[]>();
    for(const pair of replayed.values()){const occurrence=sourceRevision.get(pair.source_page_id)!;let rows=expectedByRevision.get(occurrence);if(!rows){rows=[];expectedByRevision.set(occurrence,rows);}rows.push(pair);}
    return r.revisions.every(revision=>{
      if(affected.has(revision.revision_occurrence_id)){
        const expected=expectedByRevision.get(revision.revision_occurrence_id)??[],actual=revision.bundle_mapping.map(p=>({...p,association:p.association??'inferred'})),sort=(a:z.infer<typeof BundleMapping>,b:z.infer<typeof BundleMapping>)=>a.source_page_id.localeCompare(b.source_page_id,'en');
        if(canonical(expected.sort(sort))!==canonical(actual.sort(sort)))return false;
      }
      return revision.bundle_mapping.every(pair=>{
      if(pair.association!=='human_confirmed')return !pair.decision_id;
      const active=state.get(pair.source_page_id);
      const source=revision.pages.find(p=>p.page_id===pair.source_page_id),target=revision.pages.find(p=>p.page_id===pair.rendered_page_id),display=source?.appearance;
      const displayValid=display?.association==='human_confirmed'&&display.decision_id===pair.decision_id||!display&&target?.source_transform.length!==6&&source?.coverage_gaps.some(g=>g.reason==='manual_reference_transform_unavailable');
      return !!displayValid&&r.schema_version==='0.4.0'&&r.engine_version==='0.4.0-native.bundle.53'&&active?.action==='link'&&active.rendered_page_id===pair.rendered_page_id&&active.decision.decision_id===pair.decision_id&&active.decision.revision_occurrence_id===revision.revision_occurrence_id;
      });
    });
  },'Human bundle mappings require their active same-revision decision');
export const SCHEMA_HASH=hash(z.toJSONSchema(Report));
export type ReportData = z.infer<typeof Report>;
export type PageData = z.infer<typeof Page>;
export type RevisionData = z.infer<typeof Revision>;
export type ElementData = z.infer<typeof Element>;
export type ChangeData = z.infer<typeof Change>;
export type MatchData = z.infer<typeof Match>;
export const comparisonText=(p:PageData):string=>p.comparison_basis==='hybrid_regions_v1'?comparisonRegions(p).filter(e=>e.comparison_role==='selected').map(e=>e.text).join('\n'):p.comparison_basis==='raster_ocr'?p.ocr_text??'':p.visible_text??p.text;
export const unresolvedComparisonText=(p:PageData):string=>p.comparison_basis==='hybrid_regions_v1'?comparisonRegions(p).filter(e=>e.comparison_role==='unresolved').map(e=>e.text).join('\n'):p.comparison_basis==='raster_ocr'?p.ocr_unresolved_text??'':p.unresolved_text??'';
export const Manifest = z.object({ project_id: z.string().regex(/^[a-zA-Z0-9_-]{1,100}$/), title: z.string(),
  revisions: z.array(z.object({ label: z.string(), files: z.array(z.string().min(1)).min(1).max(2) })).min(1).max(100),
  mapping_decisions: z.array(StoredDecision).default([]),mapping_relations:z.array(RelationSelection).optional(),bundle_decisions:z.array(BundleDecision).max(10000).optional() });
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
