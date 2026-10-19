import {normalize,type PageData,type ElementData,type Box} from '../schema/index.js';
import {rowOrderedRegions} from './reading-order.js';

const appearanceBlocked=new Set(['occluded','partially_occluded','struck_through','struck_inferred','partially_struck_through']);
const readable=(e:ElementData)=>e.provenance==='observed'&&e.availability==='available'&&['visible','struck_through'].includes(e.visibility??'')&&!(e.visibility_spans??[]).some(s=>['occluded','partially_occluded','struck_inferred','partially_struck_through'].includes(s.state))&&(e.visibility!=='struck_through'||!!e.visibility_spans?.length&&e.visibility_spans.every(s=>s.state==='struck_through'&&s.assessment==='observed'));
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
  for(const e of ocr){
    const nearby=raw.filter(r=>r.visibility!=='hidden_render_mode'&&intersection(boxes.get(r)!,e.bbox)>0),clear=nearby.filter(readable),unknown=nearby.filter(r=>!readable(r));
    e.comparison_role='unresolved';e.comparison_reason='unresolved_ocr';
    // A complete observed strike is readable source. Redundant OCR can be
    // shadowed by that source without promoting the OCR's visibility. Partial,
    // inferred, mixed or covered strikes still block the entire OCR line.
    if(raw.some(r=>sourceAppearanceBlocks(r,e.bbox)&&!(r.visibility==='struck_through'&&readable(r)))){e.comparison_reason='source_appearance_blocks_ocr';continue;}
    if(clear.length){
      const source=normalize(clear.map(r=>r.text).join(' ')),sameContent=source.replace(/\s/gu,'')===normalize(e.text).replace(/\s/gu,''),covered=coveredByUnion(clear.map(r=>boxes.get(r)!),e.bbox,dx,dy);
      if(source!==normalize(e.text))page.coverage_gaps.push({feature:'ocr_verification',reason:'raw_ocr_region_disagreement_source_priority'});
      // Even one source run may span whitespace/TJ gaps containing raster text.
      // Only matching content AND covered geometry make the OCR redundant.
      // Reliable raw source remains selected when the OCR line disagrees.
      if(!unknown.length&&covered&&sameContent){
        e.comparison_role='shadowed';e.comparison_reason='readable_source_priority';
      }else{e.comparison_reason=clear.length>256?'readable_source_coverage_union_budget_exceeded':!unknown.length&&covered&&!sameContent?'ocr_text_disagreement_whole_line_unresolved':'ocr_crosses_mixed_or_uncovered_source_regions';page.coverage_gaps.push({feature:'ocr',reason:e.comparison_reason});}
      continue;
    }
    if(e.visibility==='visible'&&e.availability==='available'){
      e.comparison_role='selected';e.comparison_reason='independent_inferred_raster_region';
      // Coverage is directional: seeing a prefix cannot resolve an unread tail.
      // Without per-glyph proof we retain the entire unverified source run.
      for(const r of unknown){const extent=boxes.get(r)!;
        if(contains(e.bbox,extent,dx,dy)||corroboratesCompleteText(r,e,extent)){r.comparison_role='shadowed';r.comparison_reason='unverified_source_compared_by_inferred_raster';}
        else page.coverage_gaps.push({feature:'ocr',reason:'partial_raster_coverage_source_remains_unresolved'});
      }
    }
  }
  // Roles persist per observation, so occurrence-ID stamping needs no new
  // cross-reference rewriting and paginated queries retain the exact selection.
  const participants=rowOrderedRegions(page.elements.filter(e=>e.comparison_role==='selected'||e.comparison_role==='unresolved'));
  participants.forEach((e,i)=>{e.comparison_order=i;});
  page.comparison_basis='hybrid_regions_v1';
  page.coverage_gaps=[...new Map(page.coverage_gaps.map(g=>[JSON.stringify([g.feature,g.reason,g.revision_id,g.page_id]),g])).values()];
}
