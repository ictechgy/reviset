import type {ElementData} from '../schema/index.js';

// Match the native observer's mutual-center row rule. A tall neighboring block
// must not absorb several short rows; a larger KPI can still share its label's row.
export function rowOrderedRegions(regions:ElementData[]):ElementData[]{
  const ordered=regions.map((e,i)=>({e,i})).sort((a,b)=>a.e.bbox[1]-b.e.bbox[1]||a.e.bbox[0]-b.e.bbox[0]||a.i-b.i);
  const bands:typeof ordered[]=[];
  for(const item of ordered){
    const b=item.e.bbox,a=bands.at(-1)?.[0].e.bbox;
    if(a&&a[1]<=b[1]+b[3]/2&&b[1]+b[3]/2<=a[1]+a[3]&&b[1]<=a[1]+a[3]/2&&a[1]+a[3]/2<=b[1]+b[3])bands.at(-1)!.push(item);
    else bands.push([item]);
  }
  return bands.flatMap(band=>band.sort((a,b)=>a.e.bbox[0]-b.e.bbox[0]||a.e.bbox[1]-b.e.bbox[1]||a.i-b.i).map(item=>item.e));
}
