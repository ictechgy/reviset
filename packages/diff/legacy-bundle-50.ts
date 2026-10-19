// Archived exact engine50 kernel before51 visual metadata correction. Shared source helpers are unchanged by51.
import {type StructuralComparison} from '../matching/legacy-bundle-50-graph.js';
import {annotationBlocksRegion} from '../ingest/pdf-annotation-regions.js';
import { SCHEMA_VERSION,textChunk, normalize,comparisonText,unresolvedComparisonText,comparisonRegions, type ElementData,type RevisionData, type MatchData, type ChangeData, type PageData } from '../schema/index.js';
import {numericSlots,numericPattern,numericShape,numericNotationSupported} from '../ingest/numeric-slots.js';
import {isEstimatedPdfSource} from '../ingest/pdf-text-geometry.js';
import {reviewEstimatedSource} from './estimated-source-review.js';
import {appearanceRaster,appearanceEnvironment,appearanceEvidence} from '../render/legacy-reference-51.js';
function regionElements(p:PageData):ElementData[]{return p.comparison_basis==='hybrid_regions_v1'?comparisonRegions(p):p.elements.filter(e=>p.comparison_basis==='raster_ocr'?e.method==='vision_ocr':(e.kind==='text'||e.kind==='table_cell')&&e.method!=='vision_document_cell');}
function comparisonElements(p:PageData):ElementData[]{return regionElements(p).filter(e=>p.comparison_basis==='hybrid_regions_v1'?e.comparison_role==='selected':p.comparison_basis==='raster_ocr'||e.visibility===undefined||['visible','struck_through'].includes(e.visibility));}
const selectedRaster=(e:ElementData)=>e.method==='vision_ocr'&&e.provenance==='inferred'&&e.visibility==='visible'&&e.comparison_role==='selected';
function oneAnchoredWordChange(a:string,b:string):boolean{
  if(a.length>128||b.length>128||/[\p{N}]/u.test(a+b))return false;
  const left=normalize(a).trim().split(/\s+/u),right=normalize(b).trim().split(/\s+/u);
  return left.length>=2&&left.length===right.length&&left.filter((word,i)=>word!==right[i]).length===1&&left.some((word,i)=>word===right[i]&&/\p{L}/u.test(word));
}
const boxesIntersect=(a:ElementData,b:ElementData)=>Math.min(a.bbox[0]+a.bbox[2],b.bbox[0]+b.bbox[2])>Math.max(a.bbox[0],b.bbox[0])&&Math.min(a.bbox[1]+a.bbox[3],b.bbox[1]+b.bbox[3])>Math.max(a.bbox[1],b.bbox[1]);
// A token prefix/suffix can be a wrapped word, even when the line keeps the
// same token count. Search only nearby, ordered fragments; an exhausted search
// budget retains uncertainty rather than declaring a partial word replacement.
function fragmentReflow(longer:string,shorter:string,short:ElementData,peers:ElementData[]):boolean {
  const a=normalize(longer).trim().split(/\s+/u),b=normalize(shorter).trim().split(/\s+/u);
  if(a.length!==b.length)return false;
  const changed=a.map((word,i)=>word===b[i]?-1:i).filter(i=>i>=0);if(changed.length!==1)return false;
  const lineFragment=(word:string)=>word.replace(/[\p{Dash_Punctuation}\u00ad\u2212]$/u,'');
  const index=changed[0],complete=a[index],fragment=lineFragment(b[index]);
  if(!fragment||fragment===complete)return false;
  // Repeated boundaries can admit both directions (murmur -> mur). Neither
  // orientation may silently displace the other; both share the search budget.
  const remainders=[...(complete.startsWith(fragment)?[{text:complete.slice(fragment.length),forward:true}]:[]),...(complete.endsWith(fragment)?[{text:complete.slice(0,-fragment.length),forward:false}]:[])];
  let visits=64;
  return remainders.some(remainder=>{
    function follows(anchor:ElementData,e:ElementData):boolean {
      const [x,y,w,h]=anchor.bbox,[u,v,s,t]=e.bbox,height=Math.max(h,t),vertical=Math.min(y+h,v+t)-Math.max(y,v),horizontal=Math.min(x+w,u+s)-Math.max(x,u);
      const near=vertical>0&&Math.max(u-x-w,x-u-s,0)<=2*height||horizontal>0&&Math.max(v-y-h,y-v-t,0)<=2*height;
      const sameRow=Math.abs(y+h/2-v-t/2)<=height/2;
      const after=sameRow?u+s/2>x+w/2:v+t/2>y+h/2;
      return near&&(remainder.forward?after:!after);
    }
    function search(anchor:ElementData,remaining:string,used:Set<ElementData>,depth:number):boolean {
      if(--visits<0)return true;
      const nearby=peers.filter(e=>e!==short&&!used.has(e)&&!!e.text&&follows(anchor,e));
      if(nearby.some(e=>e.text.length>128))return true;
      const candidates=nearby.flatMap(e=>{
        const words=normalize(e.text).trim().split(/\s+/u),word=lineFragment(remainder.forward?words[0]:words.at(-1)!);
        return word&&(remainder.forward?remaining.startsWith(word):remaining.endsWith(word))?[{element:e,word}]:[];
      });
      if(candidates.length>8)return true;
      return candidates.some(({element,word})=>word===remaining||depth>=3||search(element,remainder.forward?remaining.slice(word.length):remaining.slice(0,-word.length),new Set([...used,element]),depth+1));
    }
    return !!remainder.text&&search(short,remainder.text,new Set(),1);
  });
}
function verifiedRasterText(e:ElementData):boolean{return selectedRaster(e)&&e.availability==='available'&&!!e.ocr&&e.ocr.confidence>=.5&&e.ocr.numeric_consensus&&!e.ocr.ambiguous&&(!!e.ocr.reconsideration||e.ocr.strike_status==='not_detected');}
function regionOverlap(a:ElementData,b:ElementData):number{const x=a.bbox,y=b.bbox;return Math.max(0,Math.min(x[0]+x[2],y[0]+y[2])-Math.max(x[0],y[0]))*Math.max(0,Math.min(x[1]+x[3],y[1]+y[3])-Math.max(x[1],y[1]))/Math.max(0.000001,Math.max(x[2]*x[3],y[2]*y[3]));}
function ocrRegionsPaired(a:PageData,b:PageData):boolean{
  const all=(p:PageData)=>regionElements(p).filter(e=>p.comparison_basis==='hybrid_regions_v1'||e.method==='vision_ocr'||e.visibility===undefined||['visible','struck_through'].includes(e.visibility));
  const left=all(a),right=all(b),shapes=new Map<ElementData,string|null>();
  const shape=(e:ElementData):string|null=>{if(!shapes.has(e))shapes.set(e,numericShape(e.text));return shapes.get(e)!;};
  const overlap=(a:ElementData,b:ElementData)=>{const x=a.bbox,y=b.bbox;return Math.max(0,Math.min(x[0]+x[2],y[0]+y[2])-Math.max(x[0],y[0]))*Math.max(0,Math.min(x[1]+x[3],y[1]+y[3])-Math.max(x[1],y[1]))/Math.max(0.000001,Math.min(x[2]*x[3],y[2]*y[3]));};
  const compatible=(e:ElementData,f:ElementData)=>e.comparison_role!=='unresolved'&&f.comparison_role!=='unresolved'&&(e.method!=='vision_ocr'||e.visibility==='visible')&&(f.method!=='vision_ocr'||f.visibility==='visible')&&overlap(e,f)>0.4&&shape(e)!==null&&shape(e)===shape(f);
  const paired=(from:ElementData[],to:ElementData[])=>from.filter(e=>e.method==='vision_ocr').every(e=>{const neighbors=to.filter(f=>compatible(e,f));return neighbors.length===1&&from.filter(old=>compatible(old,neighbors[0])).length===1;});
  return paired(left,right)&&paired(right,left);
}
export function evidence(revision:RevisionData,page:PageData,focusText=false,focusElement?:ElementData):ChangeData['evidence'][number] {
  const selected=comparisonElements(page),element=focusElement??(focusText?(selected.find(e=>numericSlots(e.text).length)??selected[0]):undefined),textSource=(page.text||page.ocr_text)?page.elements.find(e=>e.text.trim()):undefined;
  return {revision_id:revision.revision_id,revision_occurrence_id:revision.revision_occurrence_id,asset_id:page.asset_id,page_id:page.page_id,page:page.page,
    bbox:element?.bbox??[0,0,1,1],quote:element?.text??(focusText?comparisonText(page):page.text||page.ocr_text||''),method:element?.method??textSource?.method??'page_observation',provenance:element?.provenance??textSource?.provenance??(page.comparison_basis==='raster_ocr'?'inferred':'observed'),...(element?{observation_id:element.observation_id}:{})};
}
export function diffRevisions(from:RevisionData,to:RevisionData,matches:MatchData[],candidates:MatchData[],entityFor:(pageId:string)=>string,structural?:StructuralComparison[]):ChangeData[] {
  const changes:ChangeData[]=[];let renderIntervalGap=false;
  function add(kind:ChangeData['kind'],a?:PageData,b?:PageData,match?:MatchData,reason?:string) {
    const gaps=reason?[{feature:kind==='coverage_gap'?'comparison':'text',reason}]:[];
    changes.push({schema_version:SCHEMA_VERSION,report_id:'',change_id:'',entity_id:entityFor((b??a)!.page_id),
      from_revision:from.revision_id,to_revision:to.revision_id,from_occurrence:from.revision_occurrence_id,to_occurrence:to.revision_occurrence_id,kind,
      before:(a?(kind==='text_modified'?comparisonText(a):a.text||a.ocr_text):null)??null,after:(b?(kind==='text_modified'?comparisonText(b):b.text||b.ocr_text):null)??null,evidence:[...(a?[evidence(from,a,kind==='text_modified')]:[]),...(b?[evidence(to,b,kind==='text_modified')]:[])],
      lineage:match?{status:match.status,score:match.score,reasons:[...match.reasons]}:{status:'inferred',score:0,reasons:['unmatched_page']},coverage_gaps:gaps,evidence_uri:''});
  }
  const uncertain=(r:RevisionData)=>r.status!=='success'||r.pages.some(p=>p.capabilities.text!=='available'||p.comparison_basis==='raster_ocr'||p.comparison_basis==='hybrid_regions_v1'&&comparisonRegions(p).some(e=>e.provenance!=='observed')||!!unresolvedComparisonText(p)||p.visible_text!==undefined&&!comparisonText(p).trim());
  if(from.status==='failed'||to.status==='failed') {
    const p=to.pages[0]??from.pages[0];if(p) add('coverage_gap',from.pages[0],to.pages[0],undefined,'failed_revision_no_comparison');
    return changes;
  }
  const comparisonIncomplete=uncertain(from)||uncertain(to);
  const paired=matches.filter(m=>from.pages.some(p=>p.page_id===m.from_page_id)&&to.pages.some(p=>p.page_id===m.to_page_id));
  const groups:StructuralComparison[]=structural??[...new Set(paired.filter(m=>m.relation_id&&m.relation_kind!=='continuation').map(m=>m.relation_id!))].map(relation_id=>{
    const edges=paired.filter(m=>m.relation_id===relation_id);
    return {relation_id,kind:edges[0].relation_kind as 'split'|'merge',from_page_ids:[...new Set(edges.map(m=>m.from_page_id))],to_page_ids:[...new Set(edges.map(m=>m.to_page_id))],status:'human_confirmed',score:1,reasons:edges[0].reasons,semantics:'direct_edges'};
  });
  const structuralFrom=new Set(groups.flatMap(g=>g.from_page_ids)),structuralTo=new Set(groups.flatMap(g=>g.to_page_ids));
  for(const g of groups){
    const before=from.pages.filter(p=>g.from_page_ids.includes(p.page_id)),after=to.pages.filter(p=>g.to_page_ids.includes(p.page_id));
    changes.push({schema_version:SCHEMA_VERSION,report_id:'',change_id:'',entity_id:entityFor((after[0]??before[0]).page_id),from_revision:from.revision_id,to_revision:to.revision_id,from_occurrence:from.revision_occurrence_id,to_occurrence:to.revision_occurrence_id,kind:g.kind==='split'?'page_split':g.kind==='merge'?'page_merged':'page_lineage_changed',before:`이전 ${before.length}페이지`,after:`이후 ${after.length}페이지`,topology:{relation_id:g.relation_id,kind:g.kind,from_page_ids:g.from_page_ids,to_page_ids:g.to_page_ids,semantics:g.semantics},
      evidence:[...before.map(p=>evidence(from,p,false,p.elements.find(e=>e.text.trim()))),...after.map(p=>evidence(to,p,false,p.elements.find(e=>e.text.trim())))].map(e=>({...e,quote:textChunk(e.quote,0,160)})),lineage:{status:g.status,score:g.score,reasons:g.reasons},coverage_gaps:[{feature:'comparison',reason:'split_merge_text_comparison_withheld'},...before.concat(after).flatMap(p=>p.coverage_gaps.map(g=>({...g,page_id:p.page_id})))],evidence_uri:''});
  }
  // A relative-order inversion is a move; insertions alone do not mark every later page moved.
  const order=paired.filter(m=>!structuralFrom.has(m.from_page_id)&&!structuralTo.has(m.to_page_id)).map(m=>({m,a:from.pages.findIndex(p=>p.page_id===m.from_page_id),b:to.pages.findIndex(p=>p.page_id===m.to_page_id)}));
  for(const {m,a:ai,b:bi} of order) {
    const a=from.pages[ai],b=to.pages[bi];
    if(order.some(o=>(o.a-ai)*(o.b-bi)<0)) add('page_moved',a,b,m);
    if((unresolvedComparisonText(a)||unresolvedComparisonText(b))){add('coverage_gap',a,b,m,'pdf_visibility_unresolved_text_comparison_withheld');}
    const rasterA=a.raster?.sha256??a.ocr?.render_sha256,rasterB=b.raster?.sha256??b.ocr?.render_sha256;
    const formatA=from.assets.find(s=>s.asset_id===a.asset_id)?.format,formatB=to.assets.find(s=>s.asset_id===b.asset_id)?.format;
    const samePixels=!!rasterA&&rasterA===rasterB,sameRaster=samePixels&&formatA==='pdf'&&formatB==='pdf';
    if(sameRaster&&normalize(comparisonText(a))!==normalize(comparisonText(b)))add('coverage_gap',a,b,m,'ocr_or_text_disagrees_for_identical_native_raster');
    const textDiffers=normalize(comparisonText(a))!==normalize(comparisonText(b));
    const regionsPaired=ocrRegionsPaired(a,b);
    if(textDiffers&&!regionsPaired)add('coverage_gap',a,b,m,'ocr_region_missing_or_numeric_ambiguity_withheld');
    if(!sameRaster&&regionsPaired&&!unresolvedComparisonText(a)&&!unresolvedComparisonText(b)&&a.capabilities.text==='available'&&b.capabilities.text==='available'&&textDiffers) {
      const changed=(old:ElementData[],next:ElementData[])=>{const byText=new Map<string,ElementData[]>();for(const e of next){const key=normalize(e.text);byText.set(key,[...(byText.get(key)??[]),e]);}return old.filter(e=>!(byText.get(normalize(e.text))??[]).some(f=>regionOverlap(e,f)>0.6));};
      const left=comparisonElements(a),right=comparisonElements(b),before=changed(left,right),after=changed(right,left);
      const unchangedRegions=left.length>0&&left.length===right.length&&left.every(e=>right.filter(f=>normalize(e.text)===normalize(f.text)&&regionOverlap(e,f)>0.6).length===1)&&right.every(f=>left.filter(e=>normalize(e.text)===normalize(f.text)&&regionOverlap(e,f)>0.6).length===1);
      const onlyOcrOrder=formatA==='pdf'&&formatB==='pdf'&&(a.comparison_basis==='hybrid_regions_v1'||b.comparison_basis==='hybrid_regions_v1'||left.concat(right).some(e=>e.method==='vision_ocr'))&&before.length===0&&after.length===0&&unchangedRegions;
      if(onlyOcrOrder){add('coverage_gap',a,b,m,'ocr_reading_order_changed_without_text_region_change');}
      else {
      const ocr=a.comparison_basis==='raster_ocr'||b.comparison_basis==='raster_ocr'||before.concat(after).some(e=>e.provenance==='inferred')||(!before.length&&!after.length&&left.concat(right).some(e=>e.method==='vision_ocr'));
      add('text_modified',a,b,m,ocr?'ocr_inferred_text_requires_source_review':a.elements.concat(b.elements).some(e=>e.visibility==='occluded')?'visible_text_after_inferred_opaque_cover':undefined);
      changes.at(-1)!.text_assessment=ocr?'inferred':'observed';
      const change=changes.at(-1)!;
      change.evidence=[...(before.length?before.slice(0,32).map(e=>evidence(from,a,false,e)):[evidence(from,a)]),...(after.length?after.slice(0,32).map(e=>evidence(to,b,false,e)):[evidence(to,b)])];
      if(before.length>32||after.length>32)change.coverage_gaps.push({feature:'evidence',reason:'additional_changed_regions_available_via_page_elements'});
      }
    }
    if(samePixels&&!sameRaster&&textDiffers)add('coverage_gap',a,b,m,'ooxml_source_changed_while_libreoffice_appearance_unchanged');
    const sourcePdfAppearance=formatA==='pdf'&&formatB==='pdf';
    if(textDiffers&&!sameRaster&&!changes.some(c=>c.kind==='text_modified'&&c.evidence.some(e=>e.page_id===a.page_id))){
      const left=regionElements(a),right=regionElements(b),leftText=new Set(left.map(e=>normalize(e.text))),rightText=new Set(right.map(e=>normalize(e.text)));
      const observedStrike=(e:ElementData)=>e.provenance==='observed'&&e.visibility==='struck_through'&&!!e.visibility_spans?.length&&e.visibility_spans.every(s=>s.state==='struck_through'&&s.assessment==='observed');
      const supported=(e:ElementData)=>e.comparison_role!=='unresolved'&&(e.visibility===undefined||e.visibility==='visible'||observedStrike(e))&&e.bbox[2]*e.bbox[3]<0.8;
      // Pair geometry before looking at values, including unchanged and uncertain observations.
      // Repeated/overlapping rows and an unreadable counterpart cannot become a replacement.
      for(const old of left){
        if(!supported(old))continue;
        // A readable source pair has priority over overlapping OCR hypotheses,
        // including a withheld whole OCR line crossing raster-only content.
        // Unresolved SOURCE regions still veto the pair. Inferred/cross-producer
        // pairing retains the stricter all-observation ambiguity checks.
        const sourcePair=old.provenance==='observed'&&right.some(e=>e.provenance==='observed'&&supported(e)&&regionOverlap(old,e)>.6);
        // Display-only source estimates cannot establish overlap/cardinality for
        // independently selected raster pairs. Localized uncertainty still vetoes
        // them; the raw source and its page-level unresolved gap remain intact.
        const rasterPair=selectedRaster(old)&&right.some(e=>selectedRaster(e)&&supported(e)&&regionOverlap(old,e)>.6);
        const geometryRelevant=(e:ElementData)=>!rasterPair||!isEstimatedPdfSource(e);
        const pairingLeft=sourcePair?left.filter(e=>e.provenance==='observed'):left.filter(geometryRelevant),pairingRight=sourcePair?right.filter(e=>e.provenance==='observed'):right.filter(geometryRelevant);
        const neighbors=pairingRight.filter(e=>regionOverlap(old,e)>0.6);if(neighbors.length!==1)continue;
        const current=neighbors[0];if(!supported(current)||rasterPair&&!selectedRaster(current)||pairingLeft.filter(e=>regionOverlap(e,current)>0.6).length!==1)continue;
        if(pairingRight.some(e=>!supported(e)&&regionOverlap(old,e)>0.05)||pairingLeft.some(e=>!supported(e)&&regionOverlap(e,current)>0.05))continue;
        const oldElsewhere=sourcePair?pairingRight.some(e=>normalize(e.text)===normalize(old.text)):rightText.has(normalize(old.text)),currentElsewhere=sourcePair?pairingLeft.some(e=>normalize(e.text)===normalize(current.text)):leftText.has(normalize(current.text));
        // The same amount can occur at another independently readable row.
        // For a unique bidirectional raster pair, compare the numeric value
        // at this location; do not let another nonoverlapping copy erase a swap.
        // This remains an inferred regional comparison, never entity movement
        // proof. Mixed/overlapping/unreadable pairs still fail the guards above.
        const supportedNumericPair=numericNotationSupported(old.text)&&numericNotationSupported(current.text)&&numericPattern(old.text)===numericPattern(current.text)&&numericSlots(old.text).length===1&&numericSlots(current.text).length===1;
        const numericRasterPair=rasterPair&&selectedRaster(current)&&supportedNumericPair;
        const nativeGeometry=(p:PageData)=>!!p.ocr?.width&&!!p.ocr.height&&Math.abs((p.width/p.height)/(p.ocr.width/p.ocr.height)-1)<.003;
        // A short word substitution can be compared at a unique location while
        // a separate region remains unresolved. Unchanged aligned words anchor
        // the text; this does not identify an entity or settle wraps/moves.
        const lexicalRasterPair=sourcePdfAppearance&&!a.preview&&!b.preview&&(m.status==='human_confirmed'||m.status==='inferred')&&!!rasterA&&!!rasterB&&rasterA!==rasterB&&nativeGeometry(a)&&nativeGeometry(b)&&!!a.ocr?.environment&&a.ocr.environment===b.ocr?.environment&&a.raster?.environment===a.ocr.environment&&b.raster?.environment===b.ocr?.environment&&verifiedRasterText(old)&&verifiedRasterText(current)&&numericSlots(old.text).length===0&&numericSlots(current.text).length===0&&oneAnchoredWordChange(old.text,current.text)&&!pairingLeft.some(e=>e!==old&&(boxesIntersect(e,old)||boxesIntersect(e,current)))&&!pairingRight.some(e=>e!==current&&(boxesIntersect(e,current)||boxesIntersect(e,old)));
        if((oldElsewhere||currentElsewhere)&&!numericRasterPair||normalize(old.text)===normalize(current.text))continue;
        if(rasterPair&&(annotationBlocksRegion(a.elements,old.bbox)||annotationBlocksRegion(b.elements,current.bbox))){add('coverage_gap',a,b,m,'page_annotation_prevents_inferred_raster_edit');continue;}
        if(lexicalRasterPair&&(fragmentReflow(old.text,current.text,current,pairingRight)||fragmentReflow(current.text,old.text,old,pairingLeft))){
          add('coverage_gap',a,b,m,'ocr_fragment_reflow_region_withheld');const gap=changes.at(-1)!;gap.before=old.text;gap.after=current.text;gap.evidence=[evidence(from,a,false,old),evidence(to,b,false,current)];continue;
        }
        if((old.provenance==='inferred'||current.provenance==='inferred')&&!supportedNumericPair&&!lexicalRasterPair)continue;
        const sourceReviews=rasterPair?[{revision:from,page:a,ocr:old,review:reviewEstimatedSource(old,left)},{revision:to,page:b,ocr:current,review:reviewEstimatedSource(current,right)}]:[];
        const disagreement=sourceReviews.some(s=>s.review.disagrees||s.review.numericConflict),budgetExceeded=sourceReviews.some(s=>s.review.budgetExceeded);
        if(disagreement||budgetExceeded){
          add('coverage_gap',a,b,m,budgetExceeded?'unlocalized_source_text_review_budget_exceeded':'ocr_disagrees_with_unlocalized_source_text');
          const gap=changes.at(-1)!;gap.before=old.text;gap.after=current.text;
          gap.evidence=sourceReviews.flatMap(s=>[...s.review.runs.slice(0,16).map(e=>evidence(s.revision,s.page,false,e)),evidence(s.revision,s.page,false,s.ocr)]);
        }
        if(budgetExceeded||sourceReviews.some(s=>s.review.numericConflict)||lexicalRasterPair&&disagreement)continue;
        add('text_modified',a,b,m,'other_page_regions_unresolved');const change=changes.at(-1)!;change.before=old.text;change.after=current.text;change.text_scope='region';change.region_pairing_assessment='inferred';change.text_assessment=old.provenance==='inferred'||current.provenance==='inferred'?'inferred':'observed';
        change.evidence=[evidence(from,a,false,old),evidence(to,b,false,current)];
        if(rasterPair&&left.concat(right).some(isEstimatedPdfSource))change.coverage_gaps.push({feature:'pdf_geometry',reason:'estimated_source_geometry_not_used_for_raster_pairing'});
        if(disagreement)change.coverage_gaps.push({feature:'ocr',reason:'ocr_disagrees_with_unlocalized_source_text'});
        if(change.text_assessment==='inferred')change.coverage_gaps.push({feature:'ocr',reason:'ocr_inferred_text_requires_source_review'});
      }
    }
    if(a.appearance||b.appearance){
      const left=appearanceRaster(a),right=appearanceRaster(b),leftEnvironment=appearanceEnvironment(a),rightEnvironment=appearanceEnvironment(b);
      const comparable=!!left&&!!right&&!!leftEnvironment&&leftEnvironment===rightEnvironment;
      if(!left||!right||!leftEnvironment||!rightEnvironment){
        add('coverage_gap',a,b,m,'reference_appearance_unavailable_or_unverified_for_page');const gap=changes.at(-1)!;gap.coverage_gaps[0].feature='visual_comparison';gap.evidence=[appearanceEvidence(from,a),appearanceEvidence(to,b)];
      }else if(!comparable&&!renderIntervalGap){
        add('coverage_gap',a,b,m,'revision_interval_render_appearance_not_comparable');const gap=changes.at(-1)!;gap.before=null;gap.after=null;gap.coverage_gaps[0].feature='visual_comparison';gap.lineage.reasons.push('gap_applies_to_entire_revision_interval');gap.evidence=[appearanceEvidence(from,a),appearanceEvidence(to,b)];renderIntervalGap=true;
      }else if(comparable&&formatA==='pptx'&&formatB==='pptx'&&a.asset_id===b.asset_id&&left!.sha256!==right!.sha256){
        add('coverage_gap',a,b,m,'reference_pdf_changed_without_pptx_source_change');const gap=changes.at(-1)!;gap.coverage_gaps[0].feature='visual_comparison';gap.appearance_assessment='inferred';gap.evidence=[appearanceEvidence(from,a),appearanceEvidence(to,b)];
      }else if(comparable&&left!.sha256!==right!.sha256&&!changes.some(c=>c.kind==='text_modified'&&c.evidence.some(e=>e.page_id===a.page_id))){
        add('visual_region_changed',a,b,m,'provided_pdf_visual_difference_with_inferred_source_association');const change=changes.at(-1)!;change.appearance_assessment='inferred';change.evidence=[appearanceEvidence(from,a),appearanceEvidence(to,b)];
      }else if(comparable&&left!.sha256===right!.sha256&&formatA==='pptx'&&formatB==='pptx'&&a.asset_id!==b.asset_id){
        add('coverage_gap',a,b,m,'pptx_source_changed_despite_identical_reference_pixels');const gap=changes.at(-1)!;gap.coverage_gaps[0].feature='visual_comparison';gap.evidence=[appearanceEvidence(from,a),appearanceEvidence(to,b)];
      }
    }else{
    if(!renderIntervalGap&&rasterA&&rasterB&&rasterA!==rasterB&&(formatA!==formatB||formatA==='pptx'&&a.preview?.environment!==b.preview?.environment)){
      add('coverage_gap',a,b,m,'revision_interval_render_appearance_not_comparable');const gap=changes.at(-1)!;gap.before=null;gap.after=null;gap.coverage_gaps[0].feature='visual_comparison';gap.lineage.reasons.push('gap_applies_to_entire_revision_interval');
      gap.evidence=gap.evidence.map((e,i)=>({...e,quote:'',method:'native_raster',provenance:(i===0?formatA:formatB)==='pdf'?'observed':'inferred',render_sha256:i===0?rasterA:rasterB}));renderIntervalGap=true;
    }
    if(formatA===formatB&&(formatA==='pdf'||a.preview?.environment===b.preview?.environment)&&rasterA&&rasterB&&rasterA!==rasterB&&!changes.some(c=>c.kind==='text_modified'&&c.evidence.some(e=>e.page_id===a.page_id))){add('visual_region_changed',a,b,m,sourcePdfAppearance?'native_raster_difference_is_not_semantic_deletion':'render_difference_may_include_renderer_substitution');const change=changes.at(-1)!;change.appearance_assessment=sourcePdfAppearance?'observed':'inferred';change.evidence=change.evidence.map((e,i)=>({...e,quote:'',method:'native_raster',provenance:(i===0?formatA:formatB)==='pdf'?'observed':'inferred',render_sha256:i===0?rasterA:rasterB}));}
    }
    if((a.suppressed_text||b.suppressed_text)&&normalize(a.text)!==normalize(b.text)&&normalize(comparisonText(a))===normalize(comparisonText(b)))add('coverage_gap',a,b,m,'raw_text_changed_in_suppressed_layer');
    for(const old of a.elements.filter(e=>e.text)){
      const same=b.elements.filter(e=>e.method===old.method&&e.normalized_text===old.normalized_text);
      if(same.length!==1||a.elements.filter(e=>e.method===old.method&&e.normalized_text===old.normalized_text).length!==1)continue;
      const current=same[0];if(!old.visibility||!current.visibility)continue;const oldState=old.visibility,newState=current.visibility;
      if(oldState===newState)continue;
      const kind=newState==='occluded'||newState==='partially_occluded'?'text_occluded':newState==='struck_through'||newState==='struck_inferred'||newState==='partially_struck_through'?'text_struck_through':['occluded','struck_through','struck_inferred','partially_occluded','partially_struck_through'].includes(oldState)&&newState==='visible'?'text_revealed':null;
      if(!kind)continue;
      add(kind,a,b,m);const change=changes.at(-1)!;change.before=old.text;change.after=current.text;change.appearance_assessment=kind==='text_struck_through'&&newState==='struck_through'?'observed':'inferred';
      if(sameRaster)change.coverage_gaps.push({feature:'appearance',reason:'source_appearance_state_changed_without_native_pixel_delta'});
      change.lineage.reasons=[...change.lineage.reasons,'appearance:'+oldState+'→'+newState];
      change.evidence=[evidence(from,a,false,old),evidence(to,b,false,current)];
      if(old.provenance==='inferred'||current.provenance==='inferred')change.coverage_gaps.push({feature:'ocr',reason:'ocr_inferred_text_requires_source_review'});
    }
    const features=['notes','animation','hidden_slides','structure'] as const;
    const gaps=features.filter(f=>a.capabilities[f]!==b.capabilities[f]&&(a.capabilities[f]!=='available'||b.capabilities[f]!=='available'));
    if(gaps.length) add('coverage_gap',a,b,m,'incomparable_capabilities:'+gaps.join(','));
  }
  for(const a of from.pages.filter(p=>!paired.some(m=>m.from_page_id===p.page_id)&&!structuralFrom.has(p.page_id))) {
    const reason=a.hidden&&to.assets.some(s=>s.format==='pdf')?'not_observed_in_export':!comparisonText(a).trim()?'nontext_page_lineage_unresolved':comparisonIncomplete?'comparison_observation_incomplete':candidates.some(c=>c.from_page_id===a.page_id)?'unresolved_mapping':undefined;
    add(reason?'coverage_gap':'page_deleted',a,undefined,undefined,reason);
  }
  for(const b of to.pages.filter(p=>!paired.some(m=>m.to_page_id===p.page_id)&&!structuralTo.has(p.page_id))) {
    const reason=b.hidden&&from.assets.some(s=>s.format==='pdf')?'not_observed_in_export':!comparisonText(b).trim()?'nontext_page_lineage_unresolved':comparisonIncomplete?'comparison_observation_incomplete':candidates.some(c=>c.to_page_id===b.page_id)?'unresolved_mapping':undefined;
    add(reason?'coverage_gap':'page_added',undefined,b,undefined,reason);
  }
  return changes;
}
