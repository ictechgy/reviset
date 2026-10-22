import { Util } from 'pdfjs-dist/legacy/build/pdf.mjs';
import { box,type Box } from '../schema/index.js';
export type Clip = Box|'unknown'|null;
export const PDF_RECTANGLE_PATH_POLICY='single-axis-aligned-rectangle-v2';
export function transformedBounds(rect:number[],matrix:number[],viewport:any):{bbox:Box;axisAligned:boolean}{
  const t=Util.transform(viewport.transform,matrix),points=[[rect[0],rect[1]],[rect[2],rect[1]],[rect[2],rect[3]],[rect[0],rect[3]]].map(p=>{Util.applyTransform(p,t);return p;});
  const xs=points.map(p=>p[0]),ys=points.map(p=>p[1]);
  const axisAligned=(Math.abs(points[1][0]-points[0][0])<0.01||Math.abs(points[1][1]-points[0][1])<0.01)&&(Math.abs(points[2][0]-points[1][0])<0.01||Math.abs(points[2][1]-points[1][1])<0.01);
  return{bbox:box(Math.min(...xs)/viewport.width,Math.min(...ys)/viewport.height,(Math.max(...xs)-Math.min(...xs))/viewport.width,(Math.max(...ys)-Math.min(...ys))/viewport.height),axisAligned};
}
export function rectanglePath(paths:any):boolean{
  // LibreOffice may start halfway along an edge, repeat vertices, and emit
  // an explicit closing line before closePath. Keep this proof bounded and
  // accept only one closed M/L/Z subpath; other geometry stays uncertain.
  // Pinned PDF.js paints only data[0]; never join separate buffers into a
  // contour that the renderer did not paint.
  if(!Array.isArray(paths)||paths.length!==1)return false;
  const p:number[]=[];
  for(const part of paths){
    if(!Array.isArray(part)&&!(ArrayBuffer.isView(part)&&!(part instanceof DataView)))return false;
    const values=part as ArrayLike<unknown>;
    if(values.length>256-p.length)return false;
    for(let i=0;i<values.length;i++){const value=values[i];if(typeof value!=='number'||!Number.isFinite(value))return false;p.push(value);}
  }
  if(p.length<13||p[0]!==0)return false;
  const vertices:number[][]=[[p[1],p[2]]];let cursor=3,closed=false;
  while(cursor<p.length){
    const command=p[cursor++];
    if(command===1&&cursor+2<=p.length){vertices.push([p[cursor++],p[cursor++]]);}
    else if(command===4&&cursor===p.length){closed=true;break;}
    else return false;
  }
  if(!closed)return false;
  const xs=vertices.map(v=>v[0]),ys=vertices.map(v=>v[1]),width=Math.max(...xs)-Math.min(...xs),height=Math.max(...ys)-Math.min(...ys);
  if(!Number.isFinite(width)||!Number.isFinite(height)||width<=0||height<=0)return false;
  const directions:number[]=[];
  for(const [i,a]of vertices.entries()){
    const b=vertices[(i+1)%vertices.length];
    if(a[0]===b[0]&&a[1]===b[1])continue;
    if(a[0]!==b[0]&&a[1]!==b[1])return false;
    const direction=a[1]===b[1]?(b[0]>a[0]?0:2):(b[1]>a[1]?1:3);
    if(directions.at(-1)!==direction)directions.push(direction);
  }
  // Merge a monotonic edge split by the starting point. Four equal quarter
  // turns prove a simple rectangle; reversals, concavity and extra windings
  // retain additional or opposite turns and cannot certify opaque coverage.
  if(directions.length>1&&directions[0]===directions.at(-1))directions.pop();
  if(directions.length!==4)return false;
  const turn=(directions[1]-directions[0]+4)%4;
  return(turn===1||turn===3)&&directions.every((d,i)=>(directions[(i+1)%4]-d+4)%4===turn);
}
export function intersectClip(a:Clip,b:Clip):Clip{
  if(a==='unknown'||b==='unknown')return'unknown';if(!a)return b;if(!b)return a;
  const x=Math.max(a[0],b[0]),y=Math.max(a[1],b[1]);return box(x,y,Math.max(0,Math.min(a[0]+a[2],b[0]+b[2])-x),Math.max(0,Math.min(a[1]+a[3],b[1]+b[3])-y));
}
export function insideClip(clip:Clip,b:Box):boolean{return !clip||clip!=='unknown'&&b[0]>=clip[0]-0.00001&&b[1]>=clip[1]-0.00001&&b[0]+b[2]<=clip[0]+clip[2]+0.00001&&b[1]+b[3]<=clip[1]+clip[3]+0.00001;}
