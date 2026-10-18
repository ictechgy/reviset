import { normalize, type PageData, type MatchData, type MappingDecision, DocverError } from '../schema/index.js';
function grams(text:string):Set<string> {
  const s=normalize(text).toLowerCase().replace(/[+−-]?\d+(?:[.,]\d+)*/gu,'#').replace(/\s/gu,'');
  return new Set(Array.from({length:Math.max(0,s.length-1)},(_,i)=>s.slice(i,i+2)));
}
export function similarity(a:PageData,b:PageData):number {
  const x=grams(a.text),y=grams(b.text);
  if(!x.size||!y.size) return 0;
  const intersection=[...x].filter(g=>y.has(g)).length;
  return 2*intersection/(x.size+y.size);
}
// Rectangular maximum-weight assignment with private dummy columns for unmatched rows.
function assignment(weights:number[][]):number[] {
  if(!weights.length) return [];
  const n=weights.length,m=weights[0].length+n;
  const u=Array(n+1).fill(0),v=Array(m+1).fill(0),p=Array(m+1).fill(0),way=Array(m+1).fill(0);
  for(let i=1;i<=n;i++) {
    p[0]=i; let j0=0;
    const minv=Array(m+1).fill(Infinity),used=Array(m+1).fill(false);
    do {
      used[j0]=true;const i0=p[j0];let delta=Infinity,j1=0;
      for(let j=1;j<=m;j++) if(!used[j]) {
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
export function matchPages(from:PageData[],to:PageData[],decisions:MappingDecision[]=[]):{matches:MatchData[],candidates:MatchData[]} {
  const relevant=decisions.filter(d=>from.some(p=>p.page_id===d.from_page_id)&&to.some(p=>p.page_id===d.to_page_id));
  const links=relevant.filter(d=>d.action==='link');
  if(new Set(links.map(d=>d.from_page_id)).size!==links.length||new Set(links.map(d=>d.to_page_id)).size!==links.length)
    throw new DocverError('MAPPING_CONFLICT','Only one-to-one manual links are supported at this checkpoint');
  const blocked=new Set(relevant.filter(d=>d.action==='unlink').map(d=>d.from_page_id+'|'+d.to_page_id));
  if(links.some(d=>blocked.has(d.from_page_id+'|'+d.to_page_id))) throw new DocverError('MAPPING_CONFLICT','Same pair is linked and unlinked');
  const left=from.filter(p=>!links.some(d=>d.from_page_id===p.page_id));
  const right=to.filter(p=>!links.some(d=>d.to_page_id===p.page_id));
  const weights=left.map(a=>right.map(b=>blocked.has(a.page_id+'|'+b.page_id)?0:similarity(a,b)));
  const candidates:MatchData[]=[],matches:MatchData[]=links.map(d=>({from_page_id:d.from_page_id,to_page_id:d.to_page_id,score:1,status:'human_confirmed',reasons:[d.reason]}));
  for(let i=0;i<left.length;i++) for(let j=0;j<right.length;j++) if(weights[i][j]>=0.4) {
    const score=weights[i][j];
    const ambiguous=weights[i].some((s,k)=>k!==j&&s>=score-0.06)||weights.some((row,k)=>k!==i&&row[j]>=score-0.06);
    candidates.push({from_page_id:left[i].page_id,to_page_id:right[j].page_id,score,status:ambiguous?'needs_review':'inferred',
      reasons:['normalized_text_bigrams',...(ambiguous?['competing_duplicate_or_split_merge_candidate']:[])]});
  }
  const chosen=assignment(weights.map(row=>row.map(s=>s>=0.58?s:0)));
  chosen.forEach((j,i)=>{if(j<right.length&&j>=0&&weights[i][j]>=0.58) matches.push(candidates.find(c=>c.from_page_id===left[i].page_id&&c.to_page_id===right[j].page_id)!);});
  return {matches,candidates};
}
