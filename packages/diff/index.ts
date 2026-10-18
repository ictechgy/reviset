import { SCHEMA_VERSION, normalize, type RevisionData, type MatchData, type ChangeData, type PageData } from '../schema/index.js';
export function evidence(revision:RevisionData,page:PageData,focusText=false):ChangeData['evidence'][number] {
  const element=focusText?page.elements.find(e=>(e.kind==='text'||e.kind==='table_cell')&&!['occluded','struck_through'].includes(e.visibility??'')&&/[0-9]/.test(e.text)):undefined;
  return {revision_id:revision.revision_id,revision_occurrence_id:revision.revision_occurrence_id,asset_id:page.asset_id,page_id:page.page_id,page:page.page,
    bbox:element?.bbox??[0,0,1,1],quote:element?.text??page.text,method:element?.method??page.elements[0]?.method??'page_observation',...(element?{observation_id:element.observation_id}:{})};
}
export function diffRevisions(from:RevisionData,to:RevisionData,matches:MatchData[],candidates:MatchData[],entityFor:(pageId:string)=>string):ChangeData[] {
  const changes:ChangeData[]=[];
  function add(kind:ChangeData['kind'],a?:PageData,b?:PageData,match?:MatchData,reason?:string) {
    const gaps=reason?[{feature:kind==='coverage_gap'?'comparison':'text',reason}]:[];
    changes.push({schema_version:SCHEMA_VERSION,report_id:'',change_id:'',entity_id:entityFor((b??a)!.page_id),
      from_revision:from.revision_id,to_revision:to.revision_id,from_occurrence:from.revision_occurrence_id,to_occurrence:to.revision_occurrence_id,kind,
      before:(kind==='text_modified'?a?.visible_text??a?.text:a?.text)??null,after:(kind==='text_modified'?b?.visible_text??b?.text:b?.text)??null,evidence:[...(a?[evidence(from,a,kind==='text_modified')]:[]),...(b?[evidence(to,b,kind==='text_modified')]:[])],
      lineage:match?{status:match.status,score:match.score,reasons:match.reasons}:{status:'inferred',score:0,reasons:['unmatched_page']},coverage_gaps:gaps,evidence_uri:''});
  }
  const uncertain=(r:RevisionData)=>r.status!=='success'||r.pages.some(p=>p.capabilities.text!=='available');
  if(from.status==='failed'||to.status==='failed') {
    const p=to.pages[0]??from.pages[0];if(p) add('coverage_gap',from.pages[0],to.pages[0],undefined,'failed_revision_no_comparison');
    return changes;
  }
  const paired=matches.filter(m=>from.pages.some(p=>p.page_id===m.from_page_id)&&to.pages.some(p=>p.page_id===m.to_page_id));
  // A relative-order inversion is a move; insertions alone do not mark every later page moved.
  const order=paired.map(m=>({m,a:from.pages.findIndex(p=>p.page_id===m.from_page_id),b:to.pages.findIndex(p=>p.page_id===m.to_page_id)}));
  for(const {m,a:ai,b:bi} of order) {
    const a=from.pages[ai],b=to.pages[bi];
    if(order.some(o=>(o.a-ai)*(o.b-bi)<0)) add('page_moved',a,b,m);
    if((a.unresolved_text||b.unresolved_text)){add('coverage_gap',a,b,m,'pdf_visibility_unresolved_text_comparison_withheld');}
    if(!a.unresolved_text&&!b.unresolved_text&&a.capabilities.text==='available'&&b.capabilities.text==='available'&&normalize(a.visible_text??a.text)!==normalize(b.visible_text??b.text)) add('text_modified',a,b,m,a.elements.concat(b.elements).some(e=>e.visibility==='occluded')?'visible_text_after_inferred_opaque_cover':undefined);
    if(normalize(a.text)!==normalize(b.text)&&normalize(a.visible_text??a.text)===normalize(b.visible_text??b.text))add('coverage_gap',a,b,m,'raw_text_changed_in_suppressed_layer');
    for(const old of a.elements.filter(e=>e.text)){
      const same=b.elements.filter(e=>e.normalized_text===old.normalized_text);
      if(same.length!==1||a.elements.filter(e=>e.normalized_text===old.normalized_text).length!==1)continue;
      const current=same[0];if(!old.visibility||!current.visibility)continue;const oldState=old.visibility,newState=current.visibility;
      if(oldState===newState)continue;
      const kind=newState==='occluded'||newState==='partially_occluded'?'text_occluded':newState==='struck_through'||newState==='struck_inferred'||newState==='partially_struck_through'?'text_struck_through':['occluded','struck_through','partially_occluded','partially_struck_through'].includes(oldState)&&newState==='visible'?'text_revealed':null;
      if(!kind)continue;
      add(kind,a,b,m);const change=changes.at(-1)!;change.before=old.text;change.after=current.text;change.appearance_assessment=kind==='text_struck_through'&&newState==='struck_through'?'observed':'inferred';
      change.lineage.reasons=[...change.lineage.reasons,'appearance:'+oldState+'→'+newState];
      change.evidence=[{...evidence(from,a),observation_id:old.observation_id,bbox:old.bbox,quote:old.text,method:old.method},{...evidence(to,b),observation_id:current.observation_id,bbox:current.bbox,quote:current.text,method:current.method}];
    }
    const features=['notes','animation','hidden_slides','structure'] as const;
    const gaps=features.filter(f=>a.capabilities[f]!==b.capabilities[f]&&(a.capabilities[f]!=='available'||b.capabilities[f]!=='available'));
    if(gaps.length) add('coverage_gap',a,b,m,'incomparable_capabilities:'+gaps.join(','));
  }
  for(const a of from.pages.filter(p=>!paired.some(m=>m.from_page_id===p.page_id))) {
    const reason=a.hidden&&to.assets.some(s=>s.format==='pdf')?'not_observed_in_export':uncertain(to)?'target_observation_incomplete':candidates.some(c=>c.from_page_id===a.page_id)?'unresolved_mapping':undefined;
    add(reason?'coverage_gap':'page_deleted',a,undefined,undefined,reason);
  }
  for(const b of to.pages.filter(p=>!paired.some(m=>m.to_page_id===p.page_id))) {
    const reason=b.hidden&&from.assets.some(s=>s.format==='pdf')?'not_observed_in_export':uncertain(from)?'source_observation_incomplete':candidates.some(c=>c.to_page_id===b.page_id)?'unresolved_mapping':undefined;
    add(reason?'coverage_gap':'page_added',undefined,b,undefined,reason);
  }
  return changes;
}
