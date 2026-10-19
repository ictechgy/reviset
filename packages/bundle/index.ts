import {BundleSelection,BundleDecision,bundleDirectiveState,validBundleDecisionLog,canonical,id,DocverError,comparisonText,unresolvedComparisonText,type BundleSelectionData,type BundleDecisionData,type ReportData,type RevisionData,type PageData} from '../schema/index.js';
import {similarity} from '../matching/index.js';

/** Same-revision source/PDF decisions are deliberately separate from timeline relations. */
export function bundleContext(revisions:RevisionData[],selection:BundleSelectionData){
  const revision=revisions.find(r=>r.revision_occurrence_id===selection.revision_occurrence_id);
  if(!revision||revision.assets.length!==2||!revision.assets.some(a=>a.asset_id===selection.source_asset_id&&a.format==='pptx')||!revision.assets.some(a=>a.asset_id===selection.rendered_asset_id&&a.format==='pdf'))throw new DocverError('BUNDLE_SCOPE','같은 버전의 PPTX와 PDF를 선택하세요.');
  const source=revision.pages.find(p=>p.page_id===selection.source_page_id&&p.asset_id===selection.source_asset_id),target=selection.rendered_page_id===null?undefined:revision.pages.find(p=>p.page_id===selection.rendered_page_id&&p.asset_id===selection.rendered_asset_id);
  if(!source||selection.rendered_page_id!==null&&!target||selection.action==='link'&&!target)throw new DocverError('BUNDLE_PAGE_SCOPE','선택한 버전과 원본에 속한 페이지를 선택하세요.');
  return {revision,source,target};
}
export function createBundleDecision(report:ReportData,history:BundleDecisionData[],raw:BundleSelectionData):BundleDecisionData {
  const selection=BundleSelection.parse(raw),{revision,source,target}=bundleContext(report.revisions,selection);
  const replayRevisions=report.revisions.map(r=>r.bundle_mapping_basis||history.some(d=>d.revision_occurrence_id===r.revision_occurrence_id)?r:{...r,bundle_mapping_basis:r.bundle_mapping.map(({source_page_id,rendered_page_id,score})=>({source_page_id,rendered_page_id,score}))});
  if(history.length>=10000)throw new DocverError('BUNDLE_DECISION_LIMIT','한 프로젝트의 페이지 연결 이력이10000개에 도달했습니다.');
  if(!validBundleDecisionLog(replayRevisions,history)||canonical(history)!==canonical(report.bundle_decisions??[]))throw new DocverError('BUNDLE_HISTORY','현재 보고서와 페이지 연결 이력이 다릅니다. 다시 불러오세요.');
  if(new Set(revision.bundle_mapping.map(m=>m.source_page_id)).size!==revision.bundle_mapping.length||new Set(revision.bundle_mapping.map(m=>m.rendered_page_id)).size!==revision.bundle_mapping.length)throw new DocverError('BUNDLE_MAPPING_CONFLICT','이 묶음의 일대일 대응을 확인하세요.');
  if(selection.action==='unlink'&&selection.rendered_page_id!==null&&!revision.bundle_mapping.some(m=>m.source_page_id===selection.source_page_id&&m.rendered_page_id===selection.rendered_page_id))throw new DocverError('BUNDLE_UNLINK_SCOPE','연결 해제는 현재 연결된 PDF 또는 원문 없음에 적용하세요.');
  const displaced=revision.bundle_mapping.filter(m=>m.source_page_id===selection.source_page_id||selection.action==='link'&&m.rendered_page_id===selection.rendered_page_id).map(m=>({source_page_id:m.source_page_id,rendered_page_id:m.rendered_page_id,score:m.score,association:m.association??'inferred' as const,...(m.decision_id?{decision_id:m.decision_id}:{})})).sort((a,b)=>a.source_page_id.localeCompare(b.source_page_id,'en')||a.rendered_page_id.localeCompare(b.rendered_page_id,'en'));
  const payload={...selection,score:selection.action==='link'?similarity(source,target!):null,basis_report_id:report.report_id,ordinal:history.length,previous_decision_id:history.at(-1)?.decision_id??null,displaced},decision=BundleDecision.parse({...payload,decision_id:id('bdec',payload)});
  if(!validBundleDecisionLog(replayRevisions,[...history,decision]))throw new DocverError('BUNDLE_HISTORY','연결 이력과 대체되는 기존 대응을 확인하세요.');return decision;
}
const compact=(v:string)=>v.normalize('NFC').replace(/\s/gu,'');
function clearReference(page:PageData){
  if(!page.appearance)return;page.appearance=undefined;page.capabilities.preview=page.preview?'available':'unavailable';
  page.coverage_gaps=page.coverage_gaps.filter(g=>!['provided_pdf_association_inferred_not_powerpoint_equivalence','manual_reference_not_powerpoint_equivalence'].includes(g.reason));
  if(!page.preview&&!page.coverage_gaps.some(g=>g.reason==='pptx_conversion_not_run'))page.coverage_gaps.push({feature:'preview',reason:'pptx_conversion_not_run'});
}
/** Preserve qualified raw pairs only while unchanged; partial bundles do not gain automatic qualification. */
export function applyBundleDecisions(revision:RevisionData,history:BundleDecisionData[],reusedPdf:boolean):void {
  if(!revision.bundle_mapping_basis){
    if(history.some(d=>d.revision_occurrence_id===revision.revision_occurrence_id))throw new DocverError('BUNDLE_HISTORY','자동 연결의 최초 상태가 없는 이력은 적용하지 않습니다.');
    revision.bundle_mapping_basis=revision.bundle_mapping.map(({source_page_id,rendered_page_id,score})=>({source_page_id,rendered_page_id,score}));
  }
  const state=bundleDirectiveState(history),sources=revision.pages.filter(p=>revision.assets.some(a=>a.asset_id===p.asset_id&&a.format==='pptx')),sourceIDs=new Set(sources.map(p=>p.page_id));
  const directives=[...state.values()].filter(d=>sourceIDs.has(d.source_page_id)),links=directives.filter(d=>d.action==='link'),targets=new Set(links.map(d=>d.rendered_page_id));
  for(const page of sources)page.coverage_gaps=page.coverage_gaps.filter(g=>!g.reason.startsWith('manual_reference_'));
  const retained=revision.bundle_mapping.filter(m=>!state.has(m.source_page_id)&&!targets.has(m.rendered_page_id));
  const retainedPairs=new Set(retained.map(m=>m.source_page_id+'|'+m.rendered_page_id));
  for(const source of sources)if(source.appearance&&!retainedPairs.has(source.page_id+'|'+source.appearance.source_page_id))clearReference(source);
  for(const directive of directives){
    const {decision}=directive,{source,target}=bundleContext([revision],{...decision,source_page_id:directive.source_page_id,rendered_page_id:directive.rendered_page_id,action:directive.action});
    if(directive.action==='unlink'){clearReference(source);source.coverage_gaps.push({feature:'reference_appearance',reason:directive.displaced?'manual_reference_displaced_by_another_source':'manual_reference_explicitly_unlinked'});continue;}
    if(!target)throw new DocverError('BUNDLE_PAGE_SCOPE','연결할 제공 PDF 페이지를 찾지 못했습니다.');
    const score=similarity(source,target);
    if(decision.score!==score)throw new DocverError('BUNDLE_SCORE','연결 점수가 원본 페이지의 관측과 다릅니다. 원본과 연결 이력을 확인하세요.');
    clearReference(source);source.preview=undefined;source.raster=undefined;
    retained.push({source_page_id:source.page_id,rendered_page_id:target.page_id,score,association:'human_confirmed',decision_id:decision.decision_id});
    if(target.source_transform.length!==6){source.coverage_gaps.push({feature:'reference_appearance',reason:'manual_reference_transform_unavailable'});continue;}
    source.appearance={kind:'reference_pdf',asset_id:target.asset_id,source_page_id:target.page_id,page:target.page,width:target.width,height:target.height,source_transform:[...target.source_transform],...(target.raster?{raster:{...target.raster}}:{}),association:'human_confirmed',score,policy:'human-bundle-v1',decision_id:decision.decision_id,reason:decision.reason};
    source.capabilities.preview='available';source.coverage_gaps=source.coverage_gaps.filter(g=>g.reason!=='pptx_conversion_not_run');source.coverage_gaps.push({feature:'render_fidelity',reason:'manual_reference_not_powerpoint_equivalence'});
    if(compact(source.text)!==compact(comparisonText(target))||unresolvedComparisonText(target))source.coverage_gaps.push({feature:'bundle',reason:'manual_reference_text_unresolved_or_different'});
    if(Math.abs((source.width/source.height)/(target.width/target.height)-1)>.001)source.coverage_gaps.push({feature:'bundle',reason:'manual_reference_geometry_mismatch'});
    if(reusedPdf)source.coverage_gaps.push({feature:'bundle',reason:'manual_reference_pdf_reused_for_different_pptx'});
    if(source.hidden)source.coverage_gaps.push({feature:'bundle',reason:'manual_reference_linked_hidden_source_slide'});
    if(!target.raster)source.coverage_gaps.push({feature:'visual_comparison',reason:'manual_reference_native_raster_unavailable'});

  }
  revision.bundle_mapping=retained.sort((a,b)=>a.source_page_id.localeCompare(b.source_page_id,'en'));
}
