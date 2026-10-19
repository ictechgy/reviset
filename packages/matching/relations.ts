import { DocverError,id,MappingRelation,RelationSelection,type MappingRelationData,type RelationSelectionData,type RevisionData,type MappingDecision,type MatchData,type ReportData } from '../schema/index.js';

export const primaryPages=(r:RevisionData)=>r.assets.some(a=>a.format==='pptx')?r.pages.filter(p=>r.assets.find(a=>a.asset_id===p.asset_id)?.format==='pptx'):r.pages;
const key=(a:string,b:string)=>JSON.stringify([a,b]);
export function relationEdges(r:MappingRelationData):MatchData[]{return r.from_page_ids.flatMap(a=>r.to_page_ids.map(b=>({from_page_id:a,to_page_id:b,score:1,status:'human_confirmed' as const,reasons:[r.reason],relation_id:r.relation_id,relation_kind:r.kind})));}
export function canonicalRelation(revisions:RevisionData[],raw:RelationSelectionData):MappingRelationData {
  const r=RelationSelection.parse(raw),from=revisions.findIndex(v=>v.revision_occurrence_id===r.from_occurrence),to=revisions.findIndex(v=>v.revision_occurrence_id===r.to_occurrence);
  if(from<0||to!==from+1)throw new DocverError('MAPPING_INTERVAL','인접 버전의 페이지를 선택하세요.');
  const order=(ids:string[],index:number)=>{
    const pages=primaryPages(revisions[index]);
    if(new Set(ids).size!==ids.length)throw new DocverError('MAPPING_DUPLICATE','같은 페이지를 중복 선택할 수 없습니다.');
    if(ids.some(id=>!pages.some(p=>p.page_id===id)))throw new DocverError('MAPPING_NOT_FOUND','현재 구간의 주 문서 페이지를 선택하세요.');
    return pages.filter(p=>ids.includes(p.page_id)).map(p=>p.page_id);
  };
  const a=order(r.from_page_ids,from),b=order(r.to_page_ids,to);
  if(!(r.kind==='continuation'?a.length===1&&b.length===1:r.kind==='split'?a.length===1&&b.length>=2:a.length>=2&&b.length===1))throw new DocverError('MAPPING_CARDINALITY','연결은 1:1, 분할은 1:N, 병합은 N:1로 선택하세요.');
  const topology={kind:r.kind,from_occurrence:r.from_occurrence,to_occurrence:r.to_occurrence,from_page_ids:a,to_page_ids:b};
  return MappingRelation.parse({...topology,reason:r.reason,relation_id:id('rel',topology)});
}
export function validateMappings(revisions:RevisionData[],decisions:MappingDecision[],selections:RelationSelectionData[]):MappingRelationData[]{
  const groups=selections.map(r=>canonicalRelation(revisions,r)),occupiedFrom=new Set<string>(),occupiedTo=new Set<string>();
  const reserve=(from:string[],to:string[],interval:string)=>{
    for(const [ids,set] of [[from,occupiedFrom],[to,occupiedTo]] as const)for(const p of ids){const k=interval+'|'+p;if(set.has(k))throw new DocverError('MAPPING_CONFLICT','같은 구간의 페이지에는 한 개의 대응만 설정할 수 있습니다.');set.add(k);}
  };
  for(const g of groups)reserve(g.from_page_ids,g.to_page_ids,g.from_occurrence);
  const seen=new Set<string>(),blocked=new Set<string>();
  for(const d of decisions){
    const a=revisions.findIndex(v=>primaryPages(v).some(p=>p.page_id===d.from_page_id)),b=revisions.findIndex(v=>primaryPages(v).some(p=>p.page_id===d.to_page_id));
    if(a<0||b<0)throw new DocverError('MAPPING_NOT_FOUND','Decision references a primary page outside this timeline');
    if(b!==a+1)throw new DocverError('MAPPING_INTERVAL','Manual decisions require adjacent revisions');
    const pair=key(d.from_page_id,d.to_page_id);
    if(seen.has(pair))throw new DocverError('MAPPING_CONFLICT','Duplicate or contradictory mapping decisions');seen.add(pair);
    if(d.action==='unlink')blocked.add(pair);else reserve([d.from_page_id],[d.to_page_id],revisions[a].revision_occurrence_id);
  }
  if(groups.flatMap(relationEdges).some(e=>blocked.has(key(e.from_page_id,e.to_page_id))))throw new DocverError('MAPPING_CONFLICT','A relation contains an explicitly excluded pair');
  return groups.sort((a,b)=>revisions.findIndex(r=>r.revision_occurrence_id===a.from_occurrence)-revisions.findIndex(r=>r.revision_occurrence_id===b.from_occurrence)||a.relation_id.localeCompare(b.relation_id,'en'));
}

/** Rewrite a complete adjacent interval before saving once. Removed accepted edges
 * become negative decisions so automatic matching cannot silently recreate them. */
export function rewriteMappings(report:ReportData,decisions:MappingDecision[],groups:MappingRelationData[],selection:RelationSelectionData,unlink=false):{mapping_decisions:MappingDecision[];mapping_relations:MappingRelationData[]} {
  const requested=canonicalRelation(report.revisions,selection),edges=relationEdges(requested),selected=new Set(edges.map(e=>key(e.from_page_id,e.to_page_id))),left=new Set(requested.from_page_ids),right=new Set(requested.to_page_ids);
  if(unlink&&requested.kind!=='continuation')throw new DocverError('MAPPING_CARDINALITY','연결 해제는 양쪽 페이지를 하나씩 선택하세요.');
  const displaced=(a:string,b:string)=>unlink?selected.has(key(a,b)):left.has(a)||right.has(b);
  const nextDecisions=decisions.filter(d=>d.action==='unlink'||!displaced(d.from_page_id,d.to_page_id)),nextGroups:MappingRelationData[]=[];
  for(const g of groups){
    if(g.from_occurrence!==requested.from_occurrence||g.to_occurrence!==requested.to_occurrence){nextGroups.push(g);continue;}
    const retained=relationEdges(g).filter(e=>!displaced(e.from_page_id,e.to_page_id));
    if(!retained.length)continue;
    const a=[...new Set(retained.map(e=>e.from_page_id))],b=[...new Set(retained.map(e=>e.to_page_id))];
    nextGroups.push(canonicalRelation(report.revisions,{...g,from_page_ids:a,to_page_ids:b,kind:a.length===1&&b.length===1?'continuation':a.length===1?'split':'merge'}));
  }
  const tombstones=new Map(nextDecisions.filter(d=>d.action==='unlink').map(d=>[key(d.from_page_id,d.to_page_id),d]));
  for(const e of report.matches){
    if(!displaced(e.from_page_id,e.to_page_id)||!unlink&&selected.has(key(e.from_page_id,e.to_page_id)))continue;
    // Only edges in this interval may be displaced, including branch leftovers.
    const from=report.revisions.find(r=>r.revision_occurrence_id===requested.from_occurrence),to=report.revisions.find(r=>r.revision_occurrence_id===requested.to_occurrence);
    if(from?.pages.some(p=>p.page_id===e.from_page_id)&&to?.pages.some(p=>p.page_id===e.to_page_id))tombstones.set(key(e.from_page_id,e.to_page_id),{from_page_id:e.from_page_id,to_page_id:e.to_page_id,action:'unlink',reason:requested.reason});
  }
  if(unlink)for(const e of edges)tombstones.set(key(e.from_page_id,e.to_page_id),{from_page_id:e.from_page_id,to_page_id:e.to_page_id,action:'unlink',reason:requested.reason});
  else {for(const e of edges)tombstones.delete(key(e.from_page_id,e.to_page_id));nextGroups.push(requested);}
  const next={mapping_decisions:[...nextDecisions.filter(d=>d.action==='link'),...tombstones.values()],mapping_relations:nextGroups};
  next.mapping_relations=validateMappings(report.revisions,next.mapping_decisions,next.mapping_relations);return next;
}
