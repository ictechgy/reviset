import type {PageData} from './index.js';

// Pure matching primitives shared by derivation and history validation. Keep
// historical kernels' own algorithms archived; this module has no runtime schema import.
export const normalize=(text:string):string=>text.normalize('NFC').replace(/\s+/gu,' ').trim();
export const comparisonRegions=(p:PageData)=>p.elements.filter(e=>e.comparison_role==='selected'||e.comparison_role==='unresolved').sort((a,b)=>(a.comparison_order??a.reading_order)-(b.comparison_order??b.reading_order));
export function grams(text:string):Set<string> {
  const s=normalize(text).toLowerCase().replace(/[+−-]?\d+(?:[.,]\d+)*/gu,'#').replace(/\s/gu,'');
  return new Set(Array.from({length:Math.max(0,s.length-1)},(_,i)=>s.slice(i,i+2)));
}
export function dice(x:Set<string>,y:Set<string>):number {
  if(!x.size||!y.size)return 0;
  const intersection=[...x].filter(g=>y.has(g)).length;
  return 2*intersection/(x.size+y.size);
}
export const matchingText=(p:PageData)=>p.comparison_basis==='hybrid_regions_v1'?comparisonRegions(p).map(e=>e.text).join('\n'):p.comparison_basis==='raster_ocr'?p.elements.filter(e=>e.method==='vision_ocr').map(e=>e.text).join('\n'):p.text+(p.ocr?.mode==='supplement'?'\n'+p.ocr_text:'');
export const sameOriginalPage=(a:PageData,b:PageData)=>a.asset_id===b.asset_id&&a.page===b.page;
export const sameSourceRaster=(a:PageData,b:PageData)=>!a.preview&&!b.preview&&!a.appearance&&!b.appearance&&!!a.raster?.sha256&&a.raster.sha256===b.raster?.sha256;
export function pageSimilarity(a:PageData,b:PageData):number{return sameOriginalPage(a,b)||sameSourceRaster(a,b)?1:dice(grams(matchingText(a)),grams(matchingText(b)));}
