import { Util } from 'pdfjs-dist/legacy/build/pdf.mjs';
import { box,type Box } from '../schema/index.js';
export type Clip = Box|'unknown'|null;
export function transformedBounds(rect:number[],matrix:number[],viewport:any):{bbox:Box;axisAligned:boolean}{
  const t=Util.transform(viewport.transform,matrix),points=[[rect[0],rect[1]],[rect[2],rect[1]],[rect[2],rect[3]],[rect[0],rect[3]]].map(p=>{Util.applyTransform(p,t);return p;});
  const xs=points.map(p=>p[0]),ys=points.map(p=>p[1]);
  const axisAligned=(Math.abs(points[1][0]-points[0][0])<0.01||Math.abs(points[1][1]-points[0][1])<0.01)&&(Math.abs(points[2][0]-points[1][0])<0.01||Math.abs(points[2][1]-points[1][1])<0.01);
  return{bbox:box(Math.min(...xs)/viewport.width,Math.min(...ys)/viewport.height,(Math.max(...xs)-Math.min(...xs))/viewport.width,(Math.max(...ys)-Math.min(...ys))/viewport.height),axisAligned};
}
export function rectanglePath(paths:any):boolean{
  const p=(paths??[]).flatMap((part:any)=>Array.from(part as number[])) as number[],v=[p.slice(1,3),p.slice(4,6),p.slice(7,9),p.slice(10,12)];
  return p.length===13&&p[0]===0&&p[3]===1&&p[6]===1&&p[9]===1&&p[12]===4&&v.every((a,i)=>{const b=v[(i+1)%4];return(Math.abs(a[0]-b[0])<0.001)!==(Math.abs(a[1]-b[1])<0.001);})&&new Set(v.map(a=>a[0])).size===2&&new Set(v.map(a=>a[1])).size===2;
}
export function intersectClip(a:Clip,b:Clip):Clip{
  if(a==='unknown'||b==='unknown')return'unknown';if(!a)return b;if(!b)return a;
  const x=Math.max(a[0],b[0]),y=Math.max(a[1],b[1]);return box(x,y,Math.max(0,Math.min(a[0]+a[2],b[0]+b[2])-x),Math.max(0,Math.min(a[1]+a[3],b[1]+b[3])-y));
}
export function insideClip(clip:Clip,b:Box):boolean{return !clip||clip!=='unknown'&&b[0]>=clip[0]-0.00001&&b[1]>=clip[1]-0.00001&&b[0]+b[2]<=clip[0]+clip[2]+0.00001&&b[1]+b[3]<=clip[1]+clip[3]+0.00001;}
