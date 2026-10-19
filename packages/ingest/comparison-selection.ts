import {normalize,type PageData,type ElementData,type Box} from '../schema/index.js';
import {rowOrderedRegions} from './reading-order.js';

const appearanceBlocked=new Set(['occluded','partially_occluded','struck_through','struck_inferred','partially_struck_through']);
const readable=(e:ElementData)=>e.provenance==='observed'&&e.availability==='available'&&['visible','struck_through'].includes(e.visibility??'')&&!(e.visibility_spans??[]).some(s=>['occluded','partially_occluded','struck_inferred','partially_struck_through'].includes(s.state));
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
      const b=clear.map(r=>boxes.get(r)!),x=Math.min(...b.map(r=>r[0])),y=Math.min(...b.map(r=>r[1])),extent:Box=[x,y,Math.max(...b.map(r=>r[0]+r[2]))-x,Math.max(...b.map(r=>r[1]+r[3]))-y];
      if(!unknown.length&&contains(extent,e.bbox,dx,dy)){
        e.comparison_role='shadowed';e.comparison_reason='readable_source_priority';
        if(normalize(clear.map(r=>r.text).join(' '))!==normalize(e.text))page.coverage_gaps.push({feature:'ocr_verification',reason:'raw_ocr_region_disagreement_source_priority'});
      }else{e.comparison_reason='ocr_crosses_mixed_or_uncovered_source_regions';page.coverage_gaps.push({feature:'ocr',reason:e.comparison_reason});}
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
