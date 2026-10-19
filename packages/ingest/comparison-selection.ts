import {normalize,type PageData,type ElementData,type Box} from '../schema/index.js';

const appearanceBlocked=new Set(['occluded','partially_occluded','struck_inferred','partially_struck_through']);
const readable=(e:ElementData)=>e.provenance==='observed'&&e.availability==='available'&&['visible','struck_through'].includes(e.visibility??'');
function envelope(e:ElementData):Box{
  const boxes=[e.bbox,...(e.visibility_spans??[]).map(s=>s.bbox)],x=Math.min(...boxes.map(b=>b[0])),y=Math.min(...boxes.map(b=>b[1]));
  return [x,y,Math.max(...boxes.map(b=>b[0]+b[2]))-x,Math.max(...boxes.map(b=>b[1]+b[3]))-y];
}
function intersection(a:Box,b:Box){return Math.max(0,Math.min(a[0]+a[2],b[0]+b[2])-Math.max(a[0],b[0]))*Math.max(0,Math.min(a[1]+a[3],b[1]+b[3])-Math.max(a[1],b[1]));}
function contains(a:Box,b:Box,dx:number,dy:number){return b[0]>=a[0]-dx&&b[1]>=a[1]-dy&&b[0]+b[2]<=a[0]+a[2]+dx&&b[1]+b[3]<=a[1]+a[3]+dy;}
function sameExtent(a:Box,b:Box){const aa=a[2]*a[3],ba=b[2]*b[3];return Math.max(aa,ba)<=2.5*Math.min(aa,ba)&&intersection(a,b)>0.85*Math.min(aa,ba);}

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
    if(nearby.some(r=>appearanceBlocked.has(r.visibility??''))){e.comparison_reason='source_appearance_blocks_ocr';continue;}
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
      for(const r of unknown)if(sameExtent(boxes.get(r)!,e.bbox)){r.comparison_role='shadowed';r.comparison_reason='unverified_source_compared_by_inferred_raster';}
    }
  }
  // Roles persist per observation, so occurrence-ID stamping needs no new
  // cross-reference rewriting and paginated queries retain the exact selection.
  const participants=page.elements.filter(e=>e.comparison_role==='selected'||e.comparison_role==='unresolved').sort((a,b)=>a.bbox[1]-b.bbox[1]||a.bbox[0]-b.bbox[0]||a.reading_order-b.reading_order);
  participants.forEach((e,i)=>{e.comparison_order=i;});
  page.comparison_basis='hybrid_regions_v1';
}
