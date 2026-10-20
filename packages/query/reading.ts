import { byteHash, comparisonRegions, comparisonText, DocverError, textChunk, type ChangeData, type PageData, type ReportData, type RevisionData } from '../schema/index.js';

export const readingSections=['comparison','source','visible','unresolved','suppressed','ocr','ocr_unresolved','notes'] as const;
type Section=typeof readingSections[number];
type TextArgs={text_offset:number;text_length:number};
type PageReadArgs=TextArgs&{revision_id:string;page_id:string;section:Section};
type SearchArgs={revision_id?:string;format?:'pptx'|'pdf';section:Section;text:string;case_sensitive:boolean;text_length:number};
type ChangeArgs=TextArgs&{component:'summary'|'before'|'after'|'evidence'|'coverage_gaps'|'coverage_features'|'lineage_reasons'|'topology';component_index?:number};
type CoverageArgs=TextArgs&{revision_id?:string;page_id?:string;feature?:string;gap_index?:number;component:'reason'|'feature'};
export function resolveReadingRevision(report:ReportData,key:string):RevisionData {
  const exact=report.revisions.find(v=>v.revision_occurrence_id===key);
  const aliases=report.revisions.filter(v=>v.revision_id===key);
  if(exact&&aliases.some(v=>v!==exact))throw new DocverError('AMBIGUOUS_REVISION','The key collides with a different source revision; use an unambiguous occurrence ID');
  if(exact)return exact;
  if(aliases.length>1)throw new DocverError('AMBIGUOUS_REVISION','Use revision_occurrence_id: this source appears more than once in the report');
  if(!aliases.length)throw new DocverError('REVISION_NOT_FOUND','Revision is outside this report');
  return aliases[0];
}
const pageResource=(r:ReportData,v:RevisionData,p:PageData)=>`docver://projects/${r.project_id}/reports/${r.report_id}/revisions/${v.revision_occurrence_id}/pages/${p.page_id}`;
function pageIdentity(r:ReportData,v:RevisionData,p:PageData,includeResource=true){
  const format=v.assets.find(a=>a.asset_id===p.asset_id)?.format,hasPptx=v.assets.some(a=>a.format==='pptx');
  return {revision_id:v.revision_id,revision_occurrence_id:v.revision_occurrence_id,revision_label_excerpt:textChunk(v.label,0,24),page_id:p.page_id,page:p.page,asset_id:p.asset_id,format,
    asset_role:format==='pptx'?'pptx_source':hasPptx?'provided_pdf':'pdf_source',comparison_authority:format==='pdf'&&hasPptx?'secondary':'primary',
    hidden:p.hidden,appearance_association:p.appearance?.association??null,appearance_decision_id:p.appearance?.association==='human_confirmed'?p.appearance.decision_id:undefined,...(includeResource?{resource_uri:pageResource(r,v,p)}:{})};
}
export function readingText(page:PageData,section:Section):string|null {
  if(section==='comparison')return comparisonText(page);
  return ({source:page.text,notes:page.notes,visible:page.visible_text,unresolved:page.unresolved_text,suppressed:page.suppressed_text,ocr:page.ocr_text,ocr_unresolved:page.ocr_unresolved_text})[section]??null;
}
function readingState(page:PageData,section:Section){
  const basis=page.comparison_basis??'text_layer';
  const value=readingText(page,section),isOcr=section==='ocr'||section==='ocr_unresolved'||section==='comparison'&&basis==='raster_ocr';
  const selected=section==='comparison'&&basis==='hybrid_regions_v1'?comparisonRegions(page).filter(e=>e.comparison_role==='selected'):[];
  const assessment=isOcr?'inferred':selected.some(e=>e.provenance==='inferred')?(selected.some(e=>e.provenance==='observed')?'mixed':'inferred'):'observed';
  const availability=value===null?'unavailable':section==='notes'?page.capabilities.notes:isOcr?(page.ocr?.status==='available'?'available':'unavailable'):page.capabilities.text;
  return {section,field_state:value===null?(section==='notes'?'unavailable':'not_recorded'):value.length?'present':availability==='available'?'empty':'empty_unverified',text_assessment:assessment,availability,
    interpretation:section==='source'?'raw_may_include_hidden_struck_occluded':section==='notes'?'separate_speaker_notes':section==='comparison'?'selected_not_verified_truth':'separate_observation_not_active',
    comparison_basis:basis,ocr_status:page.ocr?.status??'not_requested',coverage_gap_count:page.coverage_gaps.length};
}
export function textPart(value:string|null,offset:number,length:number){
  const text=value===null?null:textChunk(value,offset,length);
  return {text,text_offset:offset,text_length:value?.length??null,text_sha256:value===null?null:byteHash(Buffer.from(value)),next_text_offset:value!==null&&offset+(text?.length??0)<value.length?offset+(text?.length??0):null,offset_unit:'utf16_code_units'};
}
export function pageContentRows(r:ReportData,args:PageReadArgs):Record<string,unknown>[] {
  const v=resolveReadingRevision(r,args.revision_id),p=v.pages.find(p=>p.page_id===args.page_id);
  if(!p)throw new DocverError('PAGE_NOT_FOUND','Page is outside this revision');
  return [{...pageIdentity(r,v,p),...readingState(p,args.section),...textPart(readingText(p,args.section),args.text_offset,args.text_length)}];
}
function hitAttribution(page:PageData,section:Section,value:string,start:number,length:number){
  const source=page.elements.some(e=>e.method==='pdf_text')?page.elements.filter(e=>e.method==='pdf_text'):page.elements.filter(e=>e.kind==='text'||e.kind==='table_cell').filter(e=>e.method!=='vision_ocr'&&e.provenance==='observed');
  const visible=source.filter(e=>['visible','struck_through'].includes(e.visibility??''));
  const primaryOcr=page.elements.filter(e=>e.method==='vision_ocr'&&!e.ocr?.reconsideration);
  let elements:typeof page.elements|undefined;
  if(section==='source')elements=source;
  else if(section==='visible')elements=visible;
  else if(section==='suppressed')elements=source.filter(e=>['occluded','hidden_render_mode'].includes(e.visibility??''));
  else if(section==='unresolved')elements=source.filter(e=>!['visible','occluded','struck_through'].includes(e.visibility??'unverified'));
  else if(section==='ocr'||section==='ocr_unresolved')elements=primaryOcr.filter(e=>(e.visibility==='visible')===(section==='ocr'));
  else if(section==='comparison')elements=page.comparison_basis==='hybrid_regions_v1'?comparisonRegions(page).filter(e=>e.comparison_role==='selected'):page.comparison_basis==='raster_ocr'?primaryOcr.filter(e=>e.visibility==='visible'):page.visible_text===undefined?source:visible;
  // A substring's coincidental presence in an element is not a coordinate map.
  if(!elements||elements.map(e=>e.text).join('\n')!==value)return {element_attribution:'not_mapped',spans_elements:null};
  const ordering=(e:typeof page.elements[number])=>section==='comparison'&&page.comparison_basis==='hybrid_regions_v1'?e.comparison_order??e.reading_order:e.reading_order;
  if(elements.some((e,i)=>i>0&&ordering(elements![i-1])>ordering(e)))return {element_attribution:'ambiguous',spans_elements:null};
  let offset=0;const containing=elements.filter(e=>{const left=offset;offset+=e.text.length+1;return start>=left&&start+length<=left+e.text.length;});
  if(containing.length!==1)return {element_attribution:'exact_field_join',spans_elements:true};
  const e=containing[0];
  if(elements.some(other=>other!==e&&other.text.includes(e.text)))return {element_attribution:'ambiguous',spans_elements:null};
  return {element_attribution:'exact_field_join',spans_elements:false,observation_id:e.observation_id,provenance:e.provenance,visibility:e.visibility??'not_recorded',comparison_role:e.comparison_role??'not_recorded',table_origin:e.table?.origin,table_assessment:e.table?.assessment};
}
export function searchContentRows(r:ReportData,args:SearchArgs):Record<string,unknown>[] {
  const revisions=args.revision_id?[resolveReadingRevision(r,args.revision_id)]:r.revisions;
  // Escaped literal text only: no caller-controlled regex syntax or locale-dependent offset rewriting.
  const pattern=new RegExp(args.text.replace(/[.*+?^${}()|[\]\\]/g,'\\$&'),args.case_sensitive?'u':'iu');
  const rows:Record<string,unknown>[]=[];
  for(const v of revisions)for(const p of v.pages){
    if(args.format&&v.assets.find(a=>a.asset_id===p.asset_id)?.format!==args.format)continue;
    const value=readingText(p,args.section);if(value===null)continue;
    const match=pattern.exec(value);if(!match)continue;
    rows.push({...pageIdentity(r,v,p,false),content_tool:'get_page_content',...readingState(p,args.section),...hitAttribution(p,args.section,value,match.index,match[0].length),match_offset:match.index,match_length:match[0].length,matches_on_page:'first_match_only',normalization:'none',case_sensitive:args.case_sensitive,...textPart(value,match.index,args.text_length)});
  }
  return rows;
}
export function changeContentRows(r:ReportData,c:ChangeData,args:ChangeArgs,computed:boolean):Record<string,unknown>[] {
  const select=(rows:Record<string,unknown>[])=>{
    const indexed=rows.map((row,index)=>({...row,component_index:index,component_count:rows.length}));
    if(args.component_index===undefined)return indexed;
    if(!indexed[args.component_index])throw new DocverError('COMPONENT_NOT_FOUND','Component index is outside this change');
    return [indexed[args.component_index]];
  };
  if(args.component_index!==undefined&&['summary','before','after'].includes(args.component))throw new DocverError('INVALID_COMPONENT','component_index is only for a multi-row change component');
  const identity={change_id:c.change_id,entity_id:c.entity_id,kind:c.kind,from_revision:c.from_revision,to_revision:c.to_revision,from_occurrence:c.from_occurrence,to_occurrence:c.to_occurrence,
    text_assessment:c.text_assessment??'unspecified',appearance_assessment:c.appearance_assessment??'unspecified',text_scope:c.text_scope??'unspecified',region_pairing_assessment:c.region_pairing_assessment,
    lineage_status:c.lineage.status,lineage_score:c.lineage.score,computed_range:computed,component:args.component};
  if(args.component==='before'||args.component==='after')return [{...identity,...textPart(c[args.component as 'before'|'after'],args.text_offset,args.text_length)}];
  if(args.component==='evidence')return select(c.evidence.map((e,index)=>{
    const {quote,...metadata}=e;return {...identity,...metadata,evidence_index:index,...textPart(quote,args.text_offset,args.text_length)};
  }));
  if(args.component==='coverage_gaps'||args.component==='coverage_features')return select(c.coverage_gaps.map((g,index)=>({...identity,gap_index:index,feature_excerpt:textChunk(g.feature,0,120),feature_length:g.feature.length,revision_id:g.revision_id,page_id:g.page_id,...textPart(args.component==='coverage_features'?g.feature:g.reason,args.text_offset,args.text_length)})));
  if(args.component==='lineage_reasons')return select(c.lineage.reasons.map((reason,index)=>({...identity,reason_index:index,...textPart(reason,args.text_offset,args.text_length)})));
  if(args.component==='topology')return select((['from','to'] as const).flatMap(side=>(c.topology?.[`${side}_page_ids`]??[]).map((page_id,index)=>({...identity,side,index,page_id,relation_id:c.topology!.relation_id,relation_kind:c.topology!.kind,semantics:c.topology!.semantics}))));
  return [{...identity,before_length:c.before?.length??null,after_length:c.after?.length??null,evidence_count:c.evidence.length,coverage_gap_count:c.coverage_gaps.length,lineage_reason_count:c.lineage.reasons.length,
    topology_kind:c.topology?.kind??null,from_page_count:c.topology?.from_page_ids.length??0,to_page_count:c.topology?.to_page_ids.length??0,
    ...(!computed?{resource_uri:`docver://projects/${r.project_id}/reports/${r.report_id}/changes/${c.change_id}/detail`}:{})}];
}
export function coverageRows(r:ReportData,args:CoverageArgs):Record<string,unknown>[] {
  const v=args.revision_id?resolveReadingRevision(r,args.revision_id):undefined,p=args.page_id?v?.pages.find(p=>p.page_id===args.page_id):undefined;
  if(args.page_id&&!p)throw new DocverError('PAGE_NOT_FOUND','Page is outside this revision');
  const gaps=p?p.coverage_gaps:v?v.coverage_gaps:r.coverage_gaps;
  const locations=new Map(r.revisions.flatMap(revision=>revision.pages.map(page=>[page.page_id,{revision,page}] as const)));
  const bySource=new Map<string,RevisionData[]>();
  for(const revision of r.revisions){const aliases=bySource.get(revision.revision_id)??[];aliases.push(revision);bySource.set(revision.revision_id,aliases);}
  if(args.gap_index!==undefined&&!gaps[args.gap_index])throw new DocverError('GAP_NOT_FOUND','Gap index is outside this scope');
  return gaps.flatMap((g,index)=>{
    if(args.gap_index!==undefined&&args.gap_index!==index)return [];
    if(args.feature&&g.feature!==args.feature)return [];
    const located=g.page_id?locations.get(g.page_id):undefined;
    const aliases=g.revision_id?bySource.get(g.revision_id)??[]:[];
    const occurrence=v?.revision_occurrence_id??located?.revision.revision_occurrence_id??(aliases.length===1?aliases[0].revision_occurrence_id:null);
    return [{gap_index:index,scope:p?'page':v?'revision':'report',revision_id:v?.revision_id??g.revision_id??null,revision_occurrence_id:occurrence,page_id:p?.page_id??g.page_id??null,
      occurrence_context:occurrence?'resolved':aliases.length>1?'ambiguous':'report',feature_excerpt:textChunk(g.feature,0,120),feature_length:g.feature.length,component:args.component,
      ...textPart(args.component==='feature'?g.feature:g.reason,args.text_offset,args.text_length)}];
  });
}
