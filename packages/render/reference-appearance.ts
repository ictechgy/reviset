import {comparisonText,unresolvedComparisonText,type PageData,type RevisionData,type ChangeData} from '../schema/index.js';

export const referenceAppearancePolicy='qualified-full-bundle-v1';
const compact=(text:string)=>text.normalize('NFC').replace(/\s/gu,'');
/** Qualification is association evidence, never proof of PowerPoint fidelity.
 * It does not mutate raw PDF/PPTX observations or create exact raster anchors. */
export function qualifyReferenceAppearance(source:PageData[],rendered:PageData[],mapping:RevisionData['bundle_mapping'],ambiguous:boolean,reusedWithOtherSource:boolean):{qualified:boolean;reason:string} {
  if(reusedWithOtherSource)return {qualified:false,reason:'reference_pdf_reused_for_different_pptx'};
  const visible=source.filter(p=>!p.hidden);
  if(ambiguous||!visible.length||mapping.length!==visible.length||mapping.length!==rendered.length||new Set(mapping.map(m=>m.source_page_id)).size!==mapping.length||new Set(mapping.map(m=>m.rendered_page_id)).size!==mapping.length)return {qualified:false,reason:'reference_mapping_incomplete_or_ambiguous'};
  const pdfPages=new Map(rendered.map(p=>[p.page_id,p]));
  for(const page of visible){
    const relation=mapping.find(m=>m.source_page_id===page.page_id),pdf=relation&&pdfPages.get(relation.rendered_page_id);
    if(!relation||!pdf||relation.score<.95)return {qualified:false,reason:'reference_mapping_low_score'};
    if(!compact(page.text)||compact(page.text)!==compact(comparisonText(pdf))||unresolvedComparisonText(pdf)||compact(pdf.text)!==compact(comparisonText(pdf)))return {qualified:false,reason:'reference_text_unresolved_or_different'};
    if(Math.abs((page.width/page.height)/(pdf.width/pdf.height)-1)>.001)return {qualified:false,reason:'reference_geometry_mismatch'};
    if(!pdf.raster||pdf.source_transform.length!==6||pdf.raster.renderer!=='PDFKit.thumbnail.cropBox'||!pdf.raster.environment||pdf.raster.page_box!=='cropBox'||pdf.raster.rotation===undefined||pdf.raster.render_policy!=='pdfkit-300dpi-max4096-source-color-profile-v1')return {qualified:false,reason:'reference_native_raster_unavailable'};
    if(pdf.raster.rotation!==0)return {qualified:false,reason:'reference_rotation_requires_review'};
  }
  return {qualified:true,reason:'qualified_reference_association_is_inferred'};
}

export function attachReferenceAppearance(source:PageData[],rendered:PageData[],mapping:RevisionData['bundle_mapping']):void{
  const pdfPages=new Map(rendered.map(p=>[p.page_id,p]));
  for(const page of source.filter(p=>!p.hidden)){
    const relation=mapping.find(m=>m.source_page_id===page.page_id)!,pdf=pdfPages.get(relation.rendered_page_id)!;
    page.appearance={kind:'reference_pdf',asset_id:pdf.asset_id,source_page_id:pdf.page_id,page:pdf.page,width:pdf.width,height:pdf.height,source_transform:[...pdf.source_transform],raster:{...pdf.raster!},association:'inferred',score:relation.score,policy:referenceAppearancePolicy};
    page.capabilities.preview='available';
    page.coverage_gaps=page.coverage_gaps.filter(g=>g.reason!=='pptx_conversion_not_run');
    page.coverage_gaps.push({feature:'render_fidelity',reason:'provided_pdf_association_inferred_not_powerpoint_equivalence'});
  }
}

/** A supplied PDF keeps its own source identity; its relation to the PPTX is
 * inferred. Text/structure comparison and exact matching use the source page. */
export function appearanceRaster(page:PageData){return page.appearance?.raster??page.raster;}
export function appearanceEnvironment(page:PageData):string|undefined{
  if(page.preview&&!page.appearance)return 'libreoffice:'+page.preview.environment;
  const raster=appearanceRaster(page);
  if(!raster||raster.renderer!=='PDFKit.thumbnail.cropBox'||raster.page_box!=='cropBox'||raster.rotation===undefined||raster.render_policy!=='pdfkit-300dpi-max4096-source-color-profile-v1'||!raster.environment)return undefined;
  return JSON.stringify([raster.renderer,raster.page_box,raster.render_policy,raster.rotation,raster.environment]);
}
export function appearanceEvidence(revision:RevisionData,page:PageData):ChangeData['evidence'][number]{
  const reference=page.appearance;
  return {revision_id:revision.revision_id,revision_occurrence_id:revision.revision_occurrence_id,asset_id:reference?.asset_id??page.asset_id,page_id:reference?.source_page_id??page.page_id,page:reference?.page??page.page,bbox:[0,0,1,1],quote:'',method:reference?'provided_pdf_native_raster':'native_raster',provenance:reference||page.preview?'inferred':'observed',render_sha256:appearanceRaster(page)?.sha256??page.ocr?.render_sha256};
}
