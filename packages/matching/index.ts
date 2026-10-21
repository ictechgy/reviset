import {setImmediate as yieldTurn} from 'node:timers/promises';
import { type PageData, type MatchData, type MappingDecision, type MappingRelationData, DocverError } from '../schema/index.js';
import {grams,dice,matchingText,sameOriginalPage,sameSourceRaster} from '../schema/page-similarity.js';
export {matchingText,pageSimilarity as similarity} from '../schema/page-similarity.js';
import {relationEdges} from './relations.js';
export const MATCHING_WORK_POLICY='hungarian-1000-pages-1b-costs-v2';
export const MAX_ASSIGNMENT_COSTS=1_000_000_000;
// Rectangular maximum-weight assignment with private dummy columns for unmatched rows.
function* assignment(weights:number[][],maxCosts=Infinity):Generator<void,number[],undefined> {
  if(!weights.length) return [];
  if(weights.every(row=>row.every(value=>value===0)))return weights.map(()=>-1);
  // For a square uniform positive matrix the stable solver chooses its
  // diagonal. Preserve that exact result without cubic repeated tie searches.
  if(weights.length===weights[0].length&&weights[0][0]>0&&weights.every(row=>row.every(value=>value===weights[0][0])))return weights.map((_,i)=>i);
  let costs=0;
  const n=weights.length,m=weights[0].length+n;
  const u=Array(n+1).fill(0),v=Array(m+1).fill(0),p=Array(m+1).fill(0),way=Array(m+1).fill(0);
  for(let i=1;i<=n;i++) {
    p[0]=i; let j0=0;
    const minv=Array(m+1).fill(Infinity),used=Array(m+1).fill(false);
    do {
      used[j0]=true;const i0=p[j0];let delta=Infinity,j1=0;
      for(let j=1;j<=m;j++) if(!used[j]) {
        if(++costs>maxCosts)throw new DocverError('MATCHING_LIMIT','페이지 대응 계산 한도에 도달했습니다. 원문과 기존 보고서는 유지됩니다. 문서를 나눠 비교하거나 기존 대응을 확인하세요.');
        if(costs%250_000===0)yield;
        const cur=-(weights[i0-1][j-1]??0)-u[i0]-v[j];
        if(cur<minv[j]) {minv[j]=cur;way[j]=j0;}
        if(minv[j]<delta) {delta=minv[j];j1=j;}
      }
      for(let j=0;j<=m;j++) if(used[j]) {u[p[j]]+=delta;v[j]-=delta;} else minv[j]-=delta;
      j0=j1;
    } while(p[j0]!==0);
    do {const j1=way[j0];p[j0]=p[j1];j0=j1;} while(j0!==0);
  }
  const out=Array(n).fill(-1);
  for(let j=1;j<=m;j++) if(p[j]) out[p[j]-1]=j-1;
  return out;
}
function* matchingSteps(from:PageData[],to:PageData[],decisions:MappingDecision[]=[],relations:MappingRelationData[]=[],options:{maxCosts?:number}={}):Generator<void,{matches:MatchData[],candidates:MatchData[]},undefined> {
  const fromIds=new Set(from.map(p=>p.page_id)),toIds=new Set(to.map(p=>p.page_id)),groups=relations.filter(r=>r.from_page_ids.some(p=>fromIds.has(p))||r.to_page_ids.some(p=>toIds.has(p)));
  if(groups.some(r=>r.from_page_ids.some(p=>!fromIds.has(p))||r.to_page_ids.some(p=>!toIds.has(p))))throw new DocverError('MAPPING_INTERVAL','Relation is outside this primary comparison interval');
  const groupEdges=groups.flatMap(relationEdges);
  const relevant=decisions.filter(d=>from.some(p=>p.page_id===d.from_page_id)&&to.some(p=>p.page_id===d.to_page_id));
  const links=relevant.filter(d=>d.action==='link');
  if(new Set(links.map(d=>d.from_page_id)).size!==links.length||new Set(links.map(d=>d.to_page_id)).size!==links.length)
    throw new DocverError('MAPPING_CONFLICT','Manual pair links must be one-to-one; use a typed split/merge relation');
  const blocked=new Set(relevant.filter(d=>d.action==='unlink').map(d=>d.from_page_id+'|'+d.to_page_id));
  if(links.some(d=>blocked.has(d.from_page_id+'|'+d.to_page_id))) throw new DocverError('MAPPING_CONFLICT','Same pair is linked and unlinked');
  const manual=[...links,...groupEdges];
  const occupiedFrom=groups.flatMap(r=>r.from_page_ids).concat(links.map(d=>d.from_page_id)),occupiedTo=groups.flatMap(r=>r.to_page_ids).concat(links.map(d=>d.to_page_id));
  if(new Set(occupiedFrom).size!==occupiedFrom.length||new Set(occupiedTo).size!==occupiedTo.length||groupEdges.some(e=>blocked.has(e.from_page_id+'|'+e.to_page_id)))throw new DocverError('MAPPING_CONFLICT','Overlapping manual relations or excluded pairs');
  const left=from.filter(p=>!manual.some(d=>d.from_page_id===p.page_id));
  const right=to.filter(p=>!manual.some(d=>d.to_page_id===p.page_id));
  if(Number.isFinite(options.maxCosts)&&left.length*right.length>1_000_000)throw new DocverError('MATCHING_LIMIT','대응 후보 행렬 한도에 도달했습니다. 원문과 기존 보고서는 유지됩니다. 문서를 나눠 비교하세요.');
  const sourceKey=(p:PageData)=>JSON.stringify([p.asset_id,p.page]);
  function counts(pages:PageData[],key:(p:PageData)=>string|undefined){const out=new Map<string,number>();for(const p of pages){const k=key(p);if(k!==undefined)out.set(k,(out.get(k)??0)+1);}return out;}
  const sourceLeft=counts(left,sourceKey),sourceRight=counts(right,sourceKey);
  const rasterKey=(p:PageData)=>p.preview||p.appearance?undefined:p.raster?.sha256;
  const rasterLeft=counts(left,rasterKey),rasterRight=counts(right,rasterKey);
  const uniqueOriginal=(i:number,j:number)=>sameOriginalPage(left[i],right[j])&&sourceLeft.get(sourceKey(left[i]))===1&&sourceRight.get(sourceKey(right[j]))===1;
  const uniqueRaster=(i:number,j:number)=>sameSourceRaster(left[i],right[j])&&rasterLeft.get(left[i].raster!.sha256)===1&&rasterRight.get(right[j].raster!.sha256)===1;
  const leftGrams=left.map(p=>grams(matchingText(p))),rightGrams=right.map(p=>grams(matchingText(p)));
  const weights=left.map((a,i)=>right.map((b,j)=>blocked.has(a.page_id+'|'+b.page_id)?0:sameOriginalPage(a,b)||sameSourceRaster(a,b)?1:dice(leftGrams[i],rightGrams[j])));
  const candidates:MatchData[]=[],matches:MatchData[]=[...links.map<MatchData>(d=>({from_page_id:d.from_page_id,to_page_id:d.to_page_id,score:1,status:'human_confirmed' as const,reasons:[d.reason]})),...groupEdges];
  const topRow=weights.map(row=>row.map((score,j)=>({score,j})).sort((a,b)=>b.score-a.score||a.j-b.j));
  const topCol=right.map((_,j)=>weights.map((row,i)=>({score:row[j],i})).sort((a,b)=>b.score-a.score||a.i-b.i));
  function candidate(i:number,j:number):MatchData {
    const score=weights[i][j];
    const competingRow=topRow[i].find(v=>v.j!==j)?.score??0,competingCol=topCol[j].find(v=>v.i!==i)?.score??0;
    const original=sameOriginalPage(left[i],right[j]),exact=sameSourceRaster(left[i],right[j]);
    const ambiguous=!uniqueOriginal(i,j)&&!uniqueRaster(i,j)&&(competingRow>=score-0.06||competingCol>=score-0.06);
    return {from_page_id:left[i].page_id,to_page_id:right[j].page_id,score,status:ambiguous?'needs_review':'inferred',reasons:[original?'exact_source_page':exact?'exact_native_raster':'normalized_text_bigrams',...(ambiguous?['competing_duplicate_or_split_merge_candidate']:[]),...(topRow[i].filter(v=>v.score>=0.4).length>8||topCol[j].filter(v=>v.score>=0.4).length>8?['candidate_pool_limited_to_top_8_per_direction']:[])]};
  }
  // Retain both directions: absence from this bounded array must still mean no plausible edge.
  const retained=new Set<string>();
  function keep(i:number,j:number){const key=i+'|'+j;if(weights[i][j]>=0.4&&!retained.has(key)){retained.add(key);candidates.push(candidate(i,j));}}
  for(let i=0;i<left.length;i++)for(const {j} of topRow[i].filter(v=>v.score>=0.4).slice(0,8))keep(i,j);
  for(let j=0;j<right.length;j++)for(const {i} of topCol[j].filter(v=>v.score>=0.4).slice(0,8))keep(i,j);
  // Unique immutable identity constrains assignment before textual similarity.
  // A normalized text score of1 must not displace an exact source/raster pair.
  const chosen=left.map(()=>-1),used=new Set<number>();
  function anchor(unique:(i:number,j:number)=>boolean){for(let i=0;i<left.length;i++)if(chosen[i]<0){const j=right.findIndex((_,j)=>!used.has(j)&&weights[i][j]>0&&unique(i,j));if(j>=0){chosen[i]=j;used.add(j);}}}
  anchor(uniqueOriginal);anchor(uniqueRaster);
  const remainingLeft=left.map((_,i)=>i).filter(i=>chosen[i]<0),remainingRight=right.map((_,j)=>j).filter(j=>!used.has(j));
  (yield* assignment(remainingLeft.map(i=>remainingRight.map(j=>weights[i][j]>=0.58?weights[i][j]:0)),options.maxCosts)).forEach((j,k)=>{if(j>=0&&j<remainingRight.length)chosen[remainingLeft[k]]=remainingRight[j];});
  chosen.forEach((j,i)=>{if(j<right.length&&j>=0&&weights[i][j]>=0.58) {matches.push(candidate(i,j));keep(i,j);}});
  return {matches,candidates};
}

// At most n existing rows can participate in an augmentation. For n,m<=1000,
// sum_i(sum_{k=0}^{i-1}(m+n-k)) <=834,333,500 cost evaluations. The 1B limit
// admits that supported domain, while bounded yields keep cancellation live.
export function matchPages(from:PageData[],to:PageData[],decisions:MappingDecision[]=[],relations:MappingRelationData[]=[],options:{maxCosts?:number}={}):{matches:MatchData[],candidates:MatchData[]} {
  const steps=matchingSteps(from,to,decisions,relations,options);
  for(;;){const step=steps.next();if(step.done)return step.value;}
}
export async function matchPagesCooperative(from:PageData[],to:PageData[],decisions:MappingDecision[]=[],relations:MappingRelationData[]=[],options:{maxCosts?:number;signal?:AbortSignal}={}):Promise<{matches:MatchData[],candidates:MatchData[]}> {
  options.signal?.throwIfAborted();const steps=matchingSteps(from,to,decisions,relations,options);
  for(;;){const step=steps.next();if(step.done)return step.value;await yieldTurn();options.signal?.throwIfAborted();}
}
