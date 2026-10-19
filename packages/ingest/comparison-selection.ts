import {admitReconsideration,matchesReconsiderationPrimary} from './ocr-reconsideration.js';
import {annotationBlocksRegion} from './pdf-annotation-regions.js';
import {normalize,type PageData,type ElementData,type Box} from '../schema/index.js';
import {rowOrderedRegions} from './reading-order.js';
import {hasUnverifiedPdfGeometry} from './pdf-text-geometry.js';

const appearanceBlocked=new Set(['occluded','partially_occluded','struck_through','struck_inferred','partially_struck_through']);
const readable=(e:ElementData)=>!hasUnverifiedPdfGeometry(e)&&e.provenance==='observed'&&e.availability==='available'&&['visible','struck_through'].includes(e.visibility??'')&&!(e.visibility_spans??[]).some(s=>['occluded','partially_occluded','struck_inferred','partially_struck_through'].includes(s.state))&&(e.visibility!=='struck_through'||!!e.visibility_spans?.length&&e.visibility_spans.every(s=>s.state==='struck_through'&&s.assessment==='observed'));
export function sourceAppearanceBlocks(e:ElementData,region:Box):boolean{
  if(e.visibility==='hidden_render_mode')return false;
  return appearanceBlocked.has(e.visibility??'')&&intersection(e.bbox,region)>0||(e.visibility_spans??[]).some(s=>appearanceBlocked.has(s.state)&&intersection(s.bbox,region)>0);
}
function envelope(e:ElementData):Box{
  const boxes=[e.bbox,...(e.visibility_spans??[]).map(s=>s.bbox)],x=Math.min(...boxes.map(b=>b[0])),y=Math.min(...boxes.map(b=>b[1]));
  return [x,y,Math.max(...boxes.map(b=>b[0]+b[2]))-x,Math.max(...boxes.map(b=>b[1]+b[3]))-y];
}
function intersection(a:Box,b:Box){return Math.max(0,Math.min(a[0]+a[2],b[0]+b[2])-Math.max(a[0],b[0]))*Math.max(0,Math.min(a[1]+a[3],b[1]+b[3])-Math.max(a[1],b[1]));}
function contains(a:Box,b:Box,dx:number,dy:number){return b[0]>=a[0]-dx&&b[1]>=a[1]-dy&&b[0]+b[2]<=a[0]+a[2]+dx&&b[1]+b[3]<=a[1]+a[3]+dy;}
function coveredByUnion(regions:Box[],target:Box,dx:number,dy:number):boolean{
  if(regions.length>256)return false;
  // Tolerate only the OCR line's outer edge error. Expanding each source box
  // would silently bridge small INTERNAL gaps, including raster punctuation.
  target=[target[0]+dx,target[1]+dy,target[2]-2*dx,target[3]-2*dy];
  if(target[2]<=0||target[3]<=0)return false;
  const clipped=regions.map(b=>[Math.max(target[0],b[0]),Math.max(target[1],b[1]),Math.min(target[0]+target[2],b[0]+b[2]),Math.min(target[1]+target[3],b[1]+b[3])])
    .filter(([x,y,right,bottom])=>right>x&&bottom>y);
  const edges=[...new Set([target[0],target[0]+target[2],...clipped.flatMap(b=>[b[0],b[2]])])].sort((a,b)=>a-b);
  // Every nonempty vertical slab must have complete vertical union coverage.
  // A bounding envelope alone cannot establish coverage between source runs.
  for(let i=1;i<edges.length;i++){
    if(edges[i]<=edges[i-1])continue;
    const x=(edges[i]+edges[i-1])/2,intervals=clipped.filter(b=>b[0]<=x&&x<=b[2]).sort((a,b)=>a[1]-b[1]);let end=target[1];
    for(const b of intervals){if(b[1]>end+1e-12)return false;end=Math.max(end,b[3]);}
    if(end<target[1]+target[3]-1e-12)return false;
  }
  return true;
}
const compact=(text:string)=>normalize(text).replace(/\s/gu,'');
function sourceTextInside(regions:ElementData[],target:Box):{text?:string;reason?:string}{
  if(regions.length>256)return {reason:'readable_source_coverage_union_budget_exceeded'};
  const units:{text:string;bbox:Box}[]=[];let count=0;
  for(const e of regions){
    const spans=e.visibility_spans;
    if(!spans?.length){units.push(e);continue;}
    count+=spans.length;
    if(count>8192)return {reason:'readable_source_glyph_agreement_budget_exceeded'};
    if(compact(spans.map(s=>s.text).join(''))!==compact(e.text))return {reason:'readable_source_glyph_text_correlation_unverified'};
    // A neighboring line's metric margin can intersect the target. Its glyph
    // centers remain outside. Conversely a source run may cover several OCR
    // pieces: compare only source glyphs centered in this target, never a
    // substring guessed from OCR text. Raw source remains selected in full.
    const selected=spans.filter(s=>{const b=s.bbox,x=b[0]+b[2]/2,y=b[1]+b[3]/2;return x>=target[0]&&x<=target[0]+target[2]&&y>=target[1]&&y<=target[1]+target[3];});
    // Correlation proves a logical subsequence within the source element.
    // Preserve it for mixed sizes/RTL; apply row ordering only across elements.
    if(selected.length){const x=Math.min(...selected.map(s=>s.bbox[0])),y=Math.min(...selected.map(s=>s.bbox[1]));units.push({text:selected.map(s=>s.text).join(''),bbox:[x,y,Math.max(...selected.map(s=>s.bbox[0]+s.bbox[2]))-x,Math.max(...selected.map(s=>s.bbox[1]+s.bbox[3]))-y]});}
  }
  return {text:rowOrderedRegions(units).map(s=>s.text).join('')};
}
function corroboratesCompleteText(raw:ElementData,ocr:ElementData,a:Box):boolean{
  // Font-metric boxes include ascender/side-bearing space absent from raster
  // ink. Only an exact full-string reading can bridge that metric difference;
  // geometric similarity alone must never swallow unobserved source text.
  const b=ocr.bbox,width=Math.max(0,Math.min(a[0]+a[2],b[0]+b[2])-Math.max(a[0],b[0]));
  return normalize(raw.text)===normalize(ocr.text)&&width>=a[2]*.95&&width>=b[2]*.95&&intersection(a,b)>=.6*Math.max(a[2]*a[3],b[2]*b[3]);
}

// Comparison selection is an annex on immutable observations. It never edits
// source text, visibility, OCR primaries, alternatives, or their confidence.
export function selectHybridComparison(page:PageData):void{
  const raw=page.elements.filter(e=>e.provenance==='observed'&&['text','table_cell'].includes(e.kind)&&e.text.trim());
  const ocr=page.elements.filter(e=>e.method==='vision_ocr'),boxes=new Map(raw.map(e=>[e,envelope(e)]));
  for(const e of raw){e.comparison_role=e.visibility==='hidden_render_mode'?'excluded':readable(e)?'selected':'unresolved';e.comparison_reason=e.visibility==='hidden_render_mode'?'prior_hidden_layer':readable(e)?'readable_observed_source':'unresolved_source';}
  const dx=2/(page.ocr?.width??4096),dy=2/(page.ocr?.height??4096);
  const verifiedRoi=new Map<ElementData,ElementData>();
  const roiClaims=new Map<string,number>();for(const e of ocr){const ref=e.ocr?.reconsideration?.primary_source_ref;if(ref)roiClaims.set(ref,(roiClaims.get(ref)??0)+1);}
  const geometryOK=!!page.ocr?.width&&!!page.ocr.height&&Math.abs((page.width/page.height)/(page.ocr.width/page.ocr.height)-1)<.003;
  const blocks=(b:Box)=>page.elements.some(e=>sourceAppearanceBlocks(e,b))||annotationBlocksRegion(page.elements,b);
  for(const e of ocr){
    if(e.ocr?.reconsideration){
      const matches=ocr.filter(p=>matchesReconsiderationPrimary(e,p)),primary=matches.length===1?matches[0]:undefined;
      const accepted=primary?admitReconsideration(primary,e.ocr.reconsideration.observation,blocks):undefined;
      if(!geometryOK||roiClaims.get(e.ocr.reconsideration.primary_source_ref)!==1||!e.ocr.numeric_consensus||e.ocr.ambiguous||!accepted||accepted.text!==e.text||accepted.confidence!==e.ocr.confidence||!accepted.bbox.every((n,i)=>Math.abs(n-e.bbox[i])<1e-9)){
        e.comparison_role='unresolved';e.comparison_reason='roi_evidence_or_primary_relationship_unverified';continue;
      }
      verifiedRoi.set(e,primary!);
    }
    const nearby=raw.filter(r=>r.visibility!=='hidden_render_mode'&&intersection(boxes.get(r)!,e.bbox)>0),clear=nearby.filter(readable),unknown=nearby.filter(r=>!readable(r));
    e.comparison_role='unresolved';e.comparison_reason='unresolved_ocr';
    // A complete observed strike is readable source. Redundant OCR can be
    // shadowed by that source without promoting the OCR's visibility. Partial,
    // inferred, mixed or covered strikes still block the entire OCR line.
    if(raw.some(r=>sourceAppearanceBlocks(r,e.bbox)&&!(r.visibility==='struck_through'&&readable(r)))){e.comparison_reason='source_appearance_blocks_ocr';continue;}
    if(clear.length){
      const source=sourceTextInside(clear,e.bbox),sameContent=source.text!==undefined&&compact(source.text)===compact(e.text),covered=coveredByUnion(clear.map(r=>boxes.get(r)!),e.bbox,dx,dy);
      if(source.text!==undefined&&!sameContent)page.coverage_gaps.push({feature:'ocr_verification',reason:'raw_ocr_region_disagreement_source_priority'});
      // Even one source run may span whitespace/TJ gaps containing raster text.
      // Only matching content AND covered geometry make the OCR redundant.
      // Reliable raw source remains selected when the OCR line disagrees.
      if(!unknown.length&&covered&&sameContent){
        e.comparison_role='shadowed';e.comparison_reason='readable_source_priority';
      }else{e.comparison_reason=source.reason??(!unknown.length&&covered&&!sameContent?'ocr_text_disagreement_whole_line_unresolved':'ocr_crosses_mixed_or_uncovered_source_regions');page.coverage_gaps.push({feature:'ocr',reason:e.comparison_reason});}
      continue;
    }
    if(annotationBlocksRegion(page.elements,e.bbox)){e.comparison_reason='page_annotation_blocks_independent_raster';page.coverage_gaps.push({feature:'pdf_annotations',reason:'page_annotation_blocks_independent_raster'});continue;}
    if(e.visibility==='visible'&&e.availability==='available'){
      e.comparison_role='selected';e.comparison_reason='independent_inferred_raster_region';
      // Coverage is directional: seeing a prefix cannot resolve an unread tail.
      // Without per-glyph proof we retain the entire unverified source run.
      for(const r of unknown){const extent=boxes.get(r)!;
        if(hasUnverifiedPdfGeometry(r)){page.coverage_gaps.push({feature:'ocr',reason:'estimated_source_geometry_remains_unresolved'});continue;}
        if(contains(e.bbox,extent,dx,dy)||corroboratesCompleteText(r,e,extent)){r.comparison_role='shadowed';r.comparison_reason='unverified_source_compared_by_inferred_raster';}
        else page.coverage_gaps.push({feature:'ocr',reason:'partial_raster_coverage_source_remains_unresolved'});
      }
    }
  }
  for(const [derived,primary]of verifiedRoi){
    // Two derived claims cannot silently settle the same original observation.
    if([...verifiedRoi.values()].filter(p=>p===primary).length!==1)continue;
    if(['selected','shadowed'].includes(derived.comparison_role??'')){
      primary.comparison_role='shadowed';primary.comparison_reason='roi_context_primary_superseded';
    }
  }
  // Roles persist per observation, so occurrence-ID stamping needs no new
  // cross-reference rewriting and paginated queries retain the exact selection.
  const participating=page.elements.filter(e=>e.comparison_role==='selected'||e.comparison_role==='unresolved');
  // Unlocalized/estimated source cannot establish rows or reorder localized OCR.
  // Keep those raw observations after localized evidence in original source order.
  const participants=[...rowOrderedRegions(participating.filter(e=>!hasUnverifiedPdfGeometry(e))),...participating.filter(hasUnverifiedPdfGeometry).sort((a,b)=>a.reading_order-b.reading_order)];
  participants.forEach((e,i)=>{e.comparison_order=i;});
  page.comparison_basis='hybrid_regions_v1';
  page.coverage_gaps=[...new Map(page.coverage_gaps.map(g=>[JSON.stringify([g.feature,g.reason,g.revision_id,g.page_id]),g])).values()];
}
