import { SCHEMA_VERSION, normalize,comparisonText,unresolvedComparisonText, type ElementData,type RevisionData, type MatchData, type ChangeData, type PageData } from '../schema/index.js';
function regionElements(p:PageData):ElementData[]{return p.elements.filter(e=>p.comparison_basis==='raster_ocr'?e.method==='vision_ocr':(e.kind==='text'||e.kind==='table_cell')&&e.method!=='vision_document_cell');}
function comparisonElements(p:PageData):ElementData[]{return regionElements(p).filter(e=>p.comparison_basis==='raster_ocr'||e.visibility===undefined||['visible','struck_through'].includes(e.visibility));}
function regionOverlap(a:ElementData,b:ElementData):number{const x=a.bbox,y=b.bbox;return Math.max(0,Math.min(x[0]+x[2],y[0]+y[2])-Math.max(x[0],y[0]))*Math.max(0,Math.min(x[1]+x[3],y[1]+y[3])-Math.max(x[1],y[1]))/Math.max(0.000001,Math.max(x[2]*x[3],y[2]*y[3]));}
function ocrRegionsPaired(a:PageData,b:PageData):boolean{
  const left=comparisonElements(a),right=comparisonElements(b),numbers=(s:string)=>(s.match(/[0-9]+(?:[.,][0-9]+)*/g)??[]).length;
  const overlap=(a:ElementData,b:ElementData)=>{const x=a.bbox,y=b.bbox;return Math.max(0,Math.min(x[0]+x[2],y[0]+y[2])-Math.max(x[0],y[0]))*Math.max(0,Math.min(x[1]+x[3],y[1]+y[3])-Math.max(x[1],y[1]))/Math.max(0.000001,Math.min(x[2]*x[3],y[2]*y[3]));};
  const paired=(from:ElementData[],to:ElementData[])=>from.filter(e=>e.method==='vision_ocr').every(e=>to.some(f=>overlap(e,f)>0.4&&numbers(e.text)===numbers(f.text)));
  return paired(left,right)&&paired(right,left);
}
export function evidence(revision:RevisionData,page:PageData,focusText=false,focusElement?:ElementData):ChangeData['evidence'][number] {
  const element=focusElement??(focusText?comparisonElements(page).find(e=>/[0-9]/.test(e.text)):undefined);
  return {revision_id:revision.revision_id,revision_occurrence_id:revision.revision_occurrence_id,asset_id:page.asset_id,page_id:page.page_id,page:page.page,
    bbox:element?.bbox??[0,0,1,1],quote:element?.text??(focusText?comparisonText(page):page.text||page.ocr_text||''),method:element?.method??page.elements[0]?.method??'page_observation',provenance:element?.provenance??(page.comparison_basis==='raster_ocr'?'inferred':'observed'),...(element?{observation_id:element.observation_id}:{})};
}
export function diffRevisions(from:RevisionData,to:RevisionData,matches:MatchData[],candidates:MatchData[],entityFor:(pageId:string)=>string):ChangeData[] {
  const changes:ChangeData[]=[];
  function add(kind:ChangeData['kind'],a?:PageData,b?:PageData,match?:MatchData,reason?:string) {
    const gaps=reason?[{feature:kind==='coverage_gap'?'comparison':'text',reason}]:[];
    changes.push({schema_version:SCHEMA_VERSION,report_id:'',change_id:'',entity_id:entityFor((b??a)!.page_id),
      from_revision:from.revision_id,to_revision:to.revision_id,from_occurrence:from.revision_occurrence_id,to_occurrence:to.revision_occurrence_id,kind,
      before:(a?(kind==='text_modified'?comparisonText(a):a.text||a.ocr_text):null)??null,after:(b?(kind==='text_modified'?comparisonText(b):b.text||b.ocr_text):null)??null,evidence:[...(a?[evidence(from,a,kind==='text_modified')]:[]),...(b?[evidence(to,b,kind==='text_modified')]:[])],
      lineage:match?{status:match.status,score:match.score,reasons:match.reasons}:{status:'inferred',score:0,reasons:['unmatched_page']},coverage_gaps:gaps,evidence_uri:''});
  }
  const uncertain=(r:RevisionData)=>r.status!=='success'||r.pages.some(p=>p.capabilities.text!=='available'||p.comparison_basis==='raster_ocr'||!!unresolvedComparisonText(p)||p.visible_text!==undefined&&!comparisonText(p).trim());
  if(from.status==='failed'||to.status==='failed') {
    const p=to.pages[0]??from.pages[0];if(p) add('coverage_gap',from.pages[0],to.pages[0],undefined,'failed_revision_no_comparison');
    return changes;
  }
  const comparisonIncomplete=uncertain(from)||uncertain(to);
  const paired=matches.filter(m=>from.pages.some(p=>p.page_id===m.from_page_id)&&to.pages.some(p=>p.page_id===m.to_page_id));
  // A relative-order inversion is a move; insertions alone do not mark every later page moved.
  const order=paired.map(m=>({m,a:from.pages.findIndex(p=>p.page_id===m.from_page_id),b:to.pages.findIndex(p=>p.page_id===m.to_page_id)}));
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
      const leftChanged=comparisonElements(a).filter(e=>!comparisonElements(b).some(f=>normalize(f.text)===normalize(e.text))),rightChanged=comparisonElements(b).filter(e=>!comparisonElements(a).some(f=>normalize(f.text)===normalize(e.text)));
      const ocr=leftChanged.concat(rightChanged).some(e=>e.provenance==='inferred');
      add('text_modified',a,b,m,ocr?'ocr_inferred_text_requires_source_review':a.elements.concat(b.elements).some(e=>e.visibility==='occluded')?'visible_text_after_inferred_opaque_cover':undefined);
      changes.at(-1)!.text_assessment=ocr?'inferred':'observed';
      const change=changes.at(-1)!,left=comparisonElements(a),right=comparisonElements(b);
      const changed=(old:ElementData[],next:ElementData[])=>old.filter(e=>!next.some(f=>normalize(f.text)===normalize(e.text)));
      const before=changed(left,right),after=changed(right,left);
      change.evidence=[...(before.length?before.slice(0,32).map(e=>evidence(from,a,false,e)):[evidence(from,a)]),...(after.length?after.slice(0,32).map(e=>evidence(to,b,false,e)):[evidence(to,b)])];
      if(before.length>32||after.length>32)change.coverage_gaps.push({feature:'evidence',reason:'additional_changed_regions_available_via_page_elements'});
    }
    if(samePixels&&!sameRaster&&textDiffers)add('coverage_gap',a,b,m,'ooxml_source_changed_while_libreoffice_appearance_unchanged');
    const sourcePdfAppearance=formatA==='pdf'&&formatB==='pdf';
    if(textDiffers&&!sameRaster&&!changes.some(c=>c.kind==='text_modified'&&c.evidence.some(e=>e.page_id===a.page_id))){
      const left=regionElements(a),right=regionElements(b),pattern=(s:string)=>normalize(s).replace(/[+−-]?\s*[0-9]+(?:[.,][0-9]+)*/g,'#');
      const supported=(e:ElementData)=>(e.visibility===undefined||e.visibility==='visible')&&e.bbox[2]*e.bbox[3]<0.8;
      // Pair geometry before looking at values, including unchanged and uncertain observations.
      // Repeated/overlapping rows and an unreadable counterpart cannot become a replacement.
      for(const old of left){
        if(!supported(old))continue;
        const neighbors=right.filter(e=>regionOverlap(old,e)>0.6);if(neighbors.length!==1)continue;
        const current=neighbors[0];if(!supported(current)||left.filter(e=>regionOverlap(e,current)>0.6).length!==1)continue;
        if(right.some(e=>!supported(e)&&regionOverlap(old,e)>0.05)||left.some(e=>!supported(e)&&regionOverlap(e,current)>0.05))continue;
        if(right.some(e=>normalize(e.text)===normalize(old.text))||left.some(e=>normalize(e.text)===normalize(current.text))||normalize(old.text)===normalize(current.text)||pattern(old.text)!==pattern(current.text)||(old.text.match(/[0-9]+(?:[.,][0-9]+)*/g)??[]).length!==1||(current.text.match(/[0-9]+(?:[.,][0-9]+)*/g)??[]).length!==1)continue;
        add('text_modified',a,b,m,'other_page_regions_unresolved');const change=changes.at(-1)!;change.before=old.text;change.after=current.text;change.text_scope='region';change.text_assessment=old.provenance==='inferred'||current.provenance==='inferred'?'inferred':'observed';
        change.evidence=[evidence(from,a,false,old),evidence(to,b,false,current)];
        if(change.text_assessment==='inferred')change.coverage_gaps.push({feature:'ocr',reason:'ocr_inferred_text_requires_source_review'});
      }
    }
    if(rasterA&&rasterB&&rasterA!==rasterB&&!changes.some(c=>c.kind==='text_modified'&&c.evidence.some(e=>e.page_id===a.page_id))){add('visual_region_changed',a,b,m,sourcePdfAppearance?'native_raster_difference_is_not_semantic_deletion':'render_difference_may_include_renderer_substitution');const change=changes.at(-1)!;change.appearance_assessment=sourcePdfAppearance?'observed':'inferred';change.evidence=change.evidence.map((e,i)=>({...e,quote:'',method:'native_raster',provenance:(i===0?formatA:formatB)==='pdf'?'observed':'inferred',render_sha256:i===0?rasterA:rasterB}));}
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
  for(const a of from.pages.filter(p=>!paired.some(m=>m.from_page_id===p.page_id))) {
    const reason=a.hidden&&to.assets.some(s=>s.format==='pdf')?'not_observed_in_export':comparisonIncomplete?'comparison_observation_incomplete':candidates.some(c=>c.from_page_id===a.page_id)?'unresolved_mapping':undefined;
    add(reason?'coverage_gap':'page_deleted',a,undefined,undefined,reason);
  }
  for(const b of to.pages.filter(p=>!paired.some(m=>m.to_page_id===p.page_id))) {
    const reason=b.hidden&&from.assets.some(s=>s.format==='pdf')?'not_observed_in_export':comparisonIncomplete?'comparison_observation_incomplete':candidates.some(c=>c.to_page_id===b.page_id)?'unresolved_mapping':undefined;
    add(reason?'coverage_gap':'page_added',undefined,b,undefined,reason);
  }
  return changes;
}
