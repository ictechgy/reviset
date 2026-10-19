// Archived canonical engine51 from immutable native52 before manual-bundle changes.
import {id,DocverError,type MatchData,type ReportData,type RevisionData} from '../schema/index.js';
import {primaryPages} from './relations.js';

export interface StructuralComparison {
  relation_id:string;kind:'split'|'merge'|'range_lineage';from_page_ids:string[];to_page_ids:string[];
  status:MatchData['status'];score:number;reasons:string[];semantics:'direct_edges'|'directed_reachability';
}
const status=(values:MatchData['status'][]):MatchData['status']=>values.includes('needs_review')?'needs_review':values.includes('inferred')?'inferred':'human_confirmed';
/** Family membership is an undirected container. Only these directed edges
 * establish ancestry. Optional endpoints select the edges on actual paths. */
export function pathEdges(report:ReportData,from?:string,to?:string):MatchData[]{
  const positions=new Map(report.revisions.flatMap((r,i)=>primaryPages(r).map(p=>[p.page_id,i] as const)));
  if(from&&!positions.has(from)||to&&!positions.has(to))throw new DocverError('PAGE_NOT_FOUND','Ancestry endpoint is outside the primary report pages');
  const edges=report.matches.filter(e=>positions.has(e.from_page_id)&&positions.has(e.to_page_id)&&positions.get(e.from_page_id)!<positions.get(e.to_page_id)!);
  const visit=(root:string,reverse:boolean)=>{const graph=new Map<string,string[]>();for(const e of edges){const a=reverse?e.to_page_id:e.from_page_id,b=reverse?e.from_page_id:e.to_page_id;graph.set(a,[...(graph.get(a)??[]),b]);}const found=new Set([root]),pending=[root];while(pending.length){for(const n of graph.get(pending.pop()!)??[])if(!found.has(n)){found.add(n);pending.push(n);}}return found;};
  const forward=from?visit(from,false):undefined,backward=to?visit(to,true):undefined;
  if(from&&to&&!forward!.has(to))return [];
  return edges.filter(e=>(!forward||forward.has(e.from_page_id))&&(!backward||backward.has(e.to_page_id)));
}

/** Bitset propagation avoids materializing an N*M endpoint edge cross product.
 * A structural component describes a family, never a complete bipartite graph;
 * pathEdges / list_page_relations recover its actual directed paths. */
export function rangeLineage(report:ReportData,left:RevisionData,right:RevisionData):{matches:MatchData[];structural:StructuralComparison[]} {
  const a=report.revisions.indexOf(left),b=report.revisions.indexOf(right);
  if(a<0||b<=a)throw new DocverError('RANGE_ORDER','from must precede to');
  const revisions=report.revisions.slice(a,b+1),pages=revisions.flatMap(primaryPages),byId=new Map(pages.map(p=>[p.page_id,p])),order=new Map(revisions.flatMap((r,i)=>primaryPages(r).map(p=>[p.page_id,i] as const))),out=new Map<string,MatchData[]>(),incoming=new Map<string,number>();
  for(const e of report.matches)if(byId.has(e.from_page_id)&&byId.has(e.to_page_id)&&order.get(e.from_page_id)!<order.get(e.to_page_id)!){out.set(e.from_page_id,[...(out.get(e.from_page_id)??[]),e]);incoming.set(e.to_page_id,(incoming.get(e.to_page_id)??0)+1);}
  const start=primaryPages(left),end=primaryPages(right),words=Math.ceil(end.length/32),endIndex=new Map(end.map((p,i)=>[p.page_id,i])),bits=new Map<string,Uint32Array>(),summaries=new Map<string,{score:number;status:MatchData['status'];branched:boolean}>();
  for(const p of [...pages].reverse()){
    const value=new Uint32Array(words),endpoint=endIndex.get(p.page_id);
    if(endpoint!==undefined){value[endpoint>>>5]|=1<<(endpoint&31);summaries.set(p.page_id,{score:1,status:'human_confirmed',branched:false});}
    else {
      const viable=(out.get(p.page_id)??[]).filter(e=>bits.get(e.to_page_id)?.some(n=>n!==0)),children=viable.map(e=>summaries.get(e.to_page_id)!);
      for(const e of viable){const next=bits.get(e.to_page_id)!;for(let i=0;i<words;i++)value[i]|=next[i];}
      summaries.set(p.page_id,{score:Math.min(1,...viable.map(e=>e.score),...children.map(c=>c.score)),status:status([...viable.map(e=>e.status),...children.map(c=>c.status)]),branched:viable.length>1||viable.some(e=>(incoming.get(e.to_page_id)??0)>1||e.relation_kind==='split'||e.relation_kind==='merge')||children.some(c=>c.branched)});
    }
    bits.set(p.page_id,value);
  }
  const parent=Array.from({length:start.length+end.length},(_,i)=>i),root=(n:number):number=>{let r=n;while(parent[r]!==r)r=parent[r];while(parent[n]!==n){const next=parent[n];parent[n]=r;n=next;}return r;};
  function* targets(value:Uint32Array){for(let word=0;word<value.length;word++){let mask=value[word]>>>0;while(mask){const bit=31-Math.clz32(mask&-mask),index=word*32+bit;if(index<end.length)yield index;mask=(mask&(mask-1))>>>0;}}}
  for(let i=0;i<start.length;i++)for(const j of targets(bits.get(start[i].page_id)!))parent[root(start.length+j)]=root(i);
  const components=new Map<number,{from:number[];to:number[]}>();
  for(let i=0;i<start.length;i++)if(bits.get(start[i].page_id)!.some(n=>n!==0)){const r=root(i),c=components.get(r)??{from:[],to:[]};c.from.push(i);components.set(r,c);}
  for(let j=0;j<end.length;j++){const c=components.get(root(start.length+j));if(c)c.to.push(j);}
  const matches:MatchData[]=[],structural:StructuralComparison[]=[];
  for(const c of components.values()){
    const sources=c.from.map(i=>start[i].page_id),destinations=c.to.map(j=>end[j].page_id),states=sources.map(p=>summaries.get(p)!),s=status(states.map(v=>v.status)),score=Math.min(...states.map(v=>v.score));
    if(c.from.length===1&&c.to.length===1&&!states.some(v=>v.branched))matches.push({from_page_id:sources[0],to_page_id:destinations[0],score,status:s,reasons:['directed_lineage_range_net']});
    else structural.push({relation_id:id('range_rel',[left.revision_occurrence_id,right.revision_occurrence_id,sources,destinations]),kind:'range_lineage',from_page_ids:sources,to_page_ids:destinations,status:s,score,reasons:['directed_lineage_range_net','structural_lineage_does_not_confirm_text'],semantics:'directed_reachability'});
  }
  return {matches,structural};
}
