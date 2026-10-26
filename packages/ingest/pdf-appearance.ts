import { transformedBounds,rectanglePath,intersectClip,insideClip,type Clip } from './pdf-geometry.js';
import { paintedGlyphs,supportedGraphicsStateKey,nativePixelMargins,PdfAppearanceDocumentBudget,PdfAppearanceBudgetExceeded } from './pdf-glyphs.js';
import {annotationCarriers,annotationBudgetCarrier,PDF_ANNOTATION_LIMIT} from './pdf-annotations.js';
import {hasUnverifiedPdfGeometry,PDF_GEOMETRY_UNVERIFIED} from './pdf-text-geometry.js';
import { OPS, AnnotationType, AnnotationMode, Util } from 'pdfjs-dist/legacy/build/pdf.mjs';
import { box, normalize, type Box, type ElementData } from '../schema/index.js';
interface Region {bbox:Box;order:number;kind:'fill'|'line'|'stroke'|'image'|'text'|'unknown_text';opaque:boolean;axisAligned:boolean;color?:string;line?:Region;ink?:Box}
const area=(b:Box)=>b[2]*b[3];
const overlap=(a:Box,b:Box)=>Math.max(0,Math.min(a[0]+a[2],b[0]+b[2])-Math.max(a[0],b[0]))*Math.max(0,Math.min(a[1]+a[3],b[1]+b[3])-Math.max(a[1],b[1]));
const coverageOf=(target:Box,region:Box)=>area(target)>0?Math.min(1,overlap(target,region)/area(target)):0;
const compact=(s:string)=>normalize(s).replace(/\s/gu,'');
// Exact substring occurrence counts for the nonpainting correlation proof.
// A suffix automaton has at most 2*S states and 3*S transitions for S UTF-16
// code units. Build once per page, lazily; overlap counts saturate at two.
// All states, transition copies and count arrays reserve work before allocation.
function uniqueTextOccurrences(source:string,spend:ReturnType<PdfAppearanceDocumentBudget['page']>):(target:string)=>boolean {
  interface State {length:number;link:number;next:Map<string,number>;occurrences:number}
  spend('work');const states:State[]=[{length:0,link:-1,next:new Map(),occurrences:0}];let last=0;
  for(let i=0;i<source.length;i++){
    spend('work');const char=source[i],current=states.length;
    states.push({length:states[last].length+1,link:0,next:new Map(),occurrences:1});
    let previous=last;
    while(previous>=0&&!states[previous].next.has(char)){
      spend('work');states[previous].next.set(char,current);previous=states[previous].link;
    }
    if(previous>=0){
      spend('work');const next=states[previous].next.get(char)!;
      if(states[previous].length+1===states[next].length)states[current].link=next;
      else{
        spend('work',1+states[next].next.size);const clone=states.length;
        states.push({length:states[previous].length+1,link:states[next].link,next:new Map(states[next].next),occurrences:0});
        while(previous>=0&&states[previous].next.get(char)===next){
          spend('work');states[previous].next.set(char,clone);previous=states[previous].link;
        }
        states[next].link=states[current].link=clone;
      }
    }
    last=current;
  }
  // Counting order avoids a comparison sort. Descending maximum lengths give
  // every suffix link its complete end-position count before it propagates.
  spend('work',source.length+1+3*states.length);
  const counts=new Uint32Array(source.length+1),order=new Uint32Array(states.length);
  for(const state of states)counts[state.length]++;
  for(let i=1;i<counts.length;i++)counts[i]+=counts[i-1];
  for(let i=0;i<states.length;i++)order[--counts[states[i].length]]=i;
  for(let i=order.length-1;i>0;i--){const state=states[order[i]],parent=states[state.link];parent.occurrences=Math.min(2,parent.occurrences+state.occurrences);}
  return target=>{
    if(!target)return false;
    spend('work',target.length);let state=0;
    for(let i=0;i<target.length;i++){const next=states[state].next.get(target[i]);if(next===undefined)return false;state=next;}
    return states[state].occurrences===1;
  };
}
export async function inspectAppearance(page:any,viewport:any,elements:ElementData[],fontStyles:Record<string,any>,assetId:string,documentBudget=new PdfAppearanceDocumentBudget()):Promise<{regions:Region[];gaps:{feature:string;reason:string}[]}> {
  const operators=await page.getOperatorList({annotationMode:AnnotationMode.DISABLE}),annotations=await page.getAnnotations({intent:'display'}),regions:Region[]=[],gaps:{feature:string;reason:string}[]=[];
  const sourceElementCount=elements.length,spend=documentBudget.page(),gapReasons=new Set<string>();
  let annotationEvidence:ReturnType<typeof annotationCarriers>={elements:[],gaps:[],budgetExceeded:false};
  let annotationCarriersPrepared=false;
  const addGap=(...values:{feature:string;reason:string}[])=>{for(const value of values)if(!gapReasons.has(value.reason)){gapReasons.add(value.reason);gaps.push(value);}};
  const addRegion=(...values:Region[])=>{spend('regions',values.length);regions.push(...values);};
  const withhold=(reason:string)=>{
    // Partial element assessments are discarded below. Their state-specific
    // review reasons must not survive as an apparent occlusion/strike finding.
    // Keep independent geometry and annotation gaps, including their vetoes.
    for(let i=gaps.length-1;i>=0;i--)if(gaps[i].feature==='pdf_visibility'&&gaps[i].reason.startsWith('visibility_requires_review:')){gapReasons.delete(gaps[i].reason);gaps.splice(i,1);}
    // Coverage gaps alone are not an annotation veto for OCR, comparison or
    // stored-report diff consumers. Reserve at most one full-page carrier when
    // limits prevent inspecting source annotations, even if evidence is spent.
    if(!annotationCarriersPrepared&&annotations.length){annotationEvidence=annotationBudgetCarrier(assetId,page.pageNumber,sourceElementCount,reason);addGap(...annotationEvidence.gaps);}
    for(let i=0;i<sourceElementCount;i++){const e=elements[i],geometry=hasUnverifiedPdfGeometry(e);e.visibility='unverified';e.visibility_spans=[];e.visibility_evidence=geometry?[{method:PDF_GEOMETRY_UNVERIFIED,bbox:e.bbox,assessment:'inferred',coverage:0}]:[];delete e.table;}
    elements.splice(sourceElementCount);elements.push(...annotationEvidence.elements);
    addGap({feature:'pdf_visibility',reason});return {regions:[],gaps};
  };
  if(operators.fnArray.length>250000)return withhold('operator_limit_exceeded_visibility_unverified');
  if(annotations.length>PDF_ANNOTATION_LIMIT)return withhold('source_annotation_budget_exceeded');
  try{
  // Carrier evidence is also retained output and participates in the document budget.
  spend('evidence',annotations.length);
  annotationEvidence=annotationCarriers(annotations,viewport,assetId,page.pageNumber,elements.length);annotationCarriersPrepared=true;addGap(...annotationEvidence.gaps);
  if(annotationEvidence.budgetExceeded)return withhold('source_annotation_budget_exceeded');
  let state={matrix:[1,0,0,1,0,0],alpha:1,strokeAlpha:1,lineWidth:1,lineCap:0,lineJoin:0,miterLimit:10,blend:'Normal',mask:false,clip:null as Clip,pendingClip:false,textMode:0,textClipPending:false,color:'#000000',unsupportedState:false},stack:typeof state[]=[],marked:boolean[]=[];let sawComplexClipOrMask=false,optional=false;
  const glyphs=paintedGlyphs(page,viewport,operators,fontStyles,spend);
  const bounds=(rect:number[],matrix=state.matrix)=>transformedBounds(rect,matrix,viewport);
  const strokeMetrics=()=>{const m=Util.transform(viewport.transform,state.matrix),w=state.lineWidth,det=Math.abs(m[0]*m[3]-m[1]*m[2]),nx=Math.hypot(m[0],m[1]),ny=Math.hypot(m[2],m[3]);
    if(!det||!nx||!ny)return null;
    // Match pinned PDF.js getScaleForStroking: positive subpixel widths,
    // as well as w=0 hairlines, are enlarged per axis before stroking.
    const sx=m[1]===0&&m[2]===0?(w===0?1/nx:Math.max(1,1/(w*nx))):(w===0?ny/det:Math.max(1,ny/(w*det)));
    const sy=m[1]===0&&m[2]===0?(w===0?1/ny:Math.max(1,1/(w*ny))):(w===0?nx/det:Math.max(1,nx/(w*det)));
    const a=m[0]*sx,b=m[1]*sx,c=m[2]*sy,d=m[3]*sy,trace=a*a+b*b+c*c+d*d,product=(a*d-b*c)**2;
    const scale=Math.sqrt((trace+Math.sqrt(Math.max(0,trace*trace-4*product)))/2),pad=(w||1)*scale/2*(state.lineCap===2?Math.SQRT2:1);
    return Number.isFinite(pad)&&Number.isFinite(sx)&&Number.isFinite(sy)?{pad,sx,sy}:null;};
  for(let i=0;i<operators.fnArray.length;i++){
    spend('work');
    const op=operators.fnArray[i],args=operators.argsArray[i];
    if(op===OPS.beginMarkedContent||op===OPS.beginMarkedContentProps){marked.push(optional);if(args?.[0]==='OC'){optional=true;addGap({feature:'pdf_visibility',reason:'optional_content_visibility_unverified'});}continue;}
    if(op===OPS.endMarkedContent){optional=marked.pop()??false;continue;}
    if(op===OPS.setTextRenderingMode){state.textMode=Number(args[0]);continue;}
    if([OPS.showText,OPS.showSpacedText,OPS.nextLineShowText,OPS.nextLineSetSpacingShowText].includes(op)&&state.textMode>=4)state.textClipPending=true;
    if(op===OPS.endText&&state.textClipPending){state.clip='unknown';state.textClipPending=false;sawComplexClipOrMask=true;continue;}
    if(op===OPS.save){stack.push({...state,matrix:[...state.matrix]});continue;}
    if(op===OPS.restore){state=stack.pop()??state;continue;}
    if(op===OPS.setLineWidth){state.lineWidth=Number(args[0]);continue;}
    if(op===OPS.setLineCap){state.lineCap=Number(args[0]);continue;}
    if(op===OPS.setLineJoin){state.lineJoin=Number(args[0]);continue;}
    if(op===OPS.setMiterLimit){state.miterLimit=Number(args[0]);continue;}
    if([OPS.setFillGray,OPS.setFillCMYKColor,OPS.setFillColor,OPS.setFillColorN].includes(op)){state.color='unknown';continue;}
    if(op===OPS.setFillRGBColor){state.color=typeof args[0]==='string'?args[0]:'unknown';continue;}
    if(op===OPS.paintFormXObjectBegin){stack.push({...state,matrix:[...state.matrix]});if(args[0])state.matrix=Util.transform(state.matrix,args[0]);if(args[1]){const b=bounds(Array.from(args[1]));state.clip=intersectClip(state.clip,b.axisAligned?b.bbox:'unknown');}continue;}
    if(op===OPS.paintFormXObjectEnd){state=stack.pop()??state;continue;}
    if(op===OPS.beginGroup){stack.push({...state,matrix:[...state.matrix]});state.mask=true;sawComplexClipOrMask=true;continue;}
    if(op===OPS.endGroup){state=stack.pop()??state;continue;}
    if(op===OPS.transform){state.matrix=Util.transform(state.matrix,args);continue;}
    if(op===OPS.setGState){spend('work',args[0]?.length??0);for(const [key,value] of args[0]??[]){if(!supportedGraphicsStateKey(key)){state.unsupportedState=true;addRegion({bbox:box(0,0,1,1),order:i,kind:'image',opaque:false,axisAligned:false});addGap({feature:'pdf_visibility',reason:'unsupported_graphics_state:'+key});}if(key==='LW')state.lineWidth=Number(value);if(key==='LC')state.lineCap=Number(value);if(key==='LJ')state.lineJoin=Number(value);if(key==='ML')state.miterLimit=Number(value);if(key==='ca')state.alpha=Number(value);if(key==='CA')state.strokeAlpha=Number(value);if(key==='BM')state.blend=['source-over','Normal','Compatible'].includes(String(value))?'Normal':String(value);if(key==='SMask')state.mask=value!==false&&value!=='None';}if(state.mask)sawComplexClipOrMask=true;continue;}
    if(op===OPS.clip||op===OPS.eoClip){state.pendingClip=true;continue;}
    if(op===OPS.constructPath&&Array.isArray(args)&&args.length>=3){
      const [paintOp,paths,rect]=args;if(!rect||rect.length<4){addRegion({bbox:box(0,0,1,1),axisAligned:false,order:i,kind:'image',opaque:false});addGap({feature:'pdf_visibility',reason:'path_geometry_unresolved'});continue;}
      const shape=bounds(Array.from(rect)),isRectangle=rectanglePath(paths);
      if(state.pendingClip){state.clip=intersectClip(state.clip,isRectangle&&shape.axisAligned?shape.bbox:'unknown');state.pendingClip=false;if(state.clip==='unknown')sawComplexClipOrMask=true;}
      const fill=[OPS.fill,OPS.eoFill,OPS.fillStroke,OPS.eoFillStroke,OPS.closeFillStroke,OPS.closeEOFillStroke].includes(paintOp);
      const stroke=[OPS.stroke,OPS.closeStroke,OPS.fillStroke,OPS.eoFillStroke,OPS.closeFillStroke,OPS.closeEOFillStroke].includes(paintOp);
      if(fill&&isRectangle)addRegion({...shape,order:i,kind:'fill',color:state.color,opaque:!optional&&!state.unsupportedState&&state.color!=='unknown'&&state.alpha>=0.999&&state.blend==='Normal'&&!state.mask&&insideClip(state.clip,shape.bbox)});
      else if(fill&&area(shape.bbox)>0){addRegion({...shape,order:i,kind:'fill',opaque:false});addGap({feature:'pdf_visibility',reason:'non_rectangular_fill_not_used_as_confirmed_occlusion'});}
      if(stroke){
        if(!Number.isFinite(state.lineWidth)||state.lineWidth<0||!Number.isFinite(state.miterLimit)||state.miterLimit<1||![0,1,2].includes(state.lineCap)||![0,1,2].includes(state.lineJoin)){
          addRegion({bbox:box(0,0,1,1),order:i,kind:'image',opaque:false,axisAligned:false});addGap({feature:'pdf_visibility',reason:'invalid_stroke_state_visibility_unverified'});continue;
        }
        if(state.lineWidth===0)addGap({feature:'pdf_visibility',reason:'device_hairline_visibility_unverified'});
        const metrics=strokeMetrics();if(!metrics){addRegion({bbox:box(0,0,1,1),order:i,kind:'image',opaque:false,axisAligned:false});addGap({feature:'pdf_visibility',reason:'stroke_transform_visibility_unverified'});continue;}
        const {pad,sx,sy}=metrics,joinPad=pad*(state.lineJoin===0?2*Math.max(1,state.miterLimit):1);
        const joinRegion=(point:number[],from?:number[],to?:number[])=>{const b=bounds([point[0],point[1],point[0],point[1]]).bbox;let radius=joinPad;
          if(state.lineJoin!==0)radius=pad;
          else if(from&&to){const u=[(from[0]-point[0])/sx,(from[1]-point[1])/sy],v=[(to[0]-point[0])/sx,(to[1]-point[1])/sy],nu=Math.hypot(...u),nv=Math.hypot(...v);
            if(nu>0&&nv>0){const cosine=Math.max(-1,Math.min(1,(u[0]*v[0]+u[1]*v[1])/(nu*nv))),ratio=1/Math.sqrt((1-cosine)/2);radius=pad*(Number.isFinite(ratio)&&ratio<=state.miterLimit?ratio:1);}}
          addRegion({bbox:box(b[0]-radius/viewport.width,b[1]-radius/viewport.height,2*radius/viewport.width,2*radius/viewport.height),order:i,kind:'image',opaque:false,axisAligned:false});addGap({feature:'pdf_visibility',reason:'stroke_join_geometry_unverified'});};
        let curveReported=false;
        const unknownStroke=()=>{if(curveReported)return;curveReported=true;
          addRegion({bbox:box(shape.bbox[0]-joinPad/viewport.width,shape.bbox[1]-joinPad/viewport.height,shape.bbox[2]+2*joinPad/viewport.width,shape.bbox[3]+2*joinPad/viewport.height),order:i,kind:'image',opaque:false,axisAligned:false});addGap({feature:'pdf_visibility',reason:'curve_stroke_visibility_unverified'});};
        // A single stroke can contain every border of a table or many strike lines.
        for(const path of paths??[]){spend('work',path.length);const p=Array.from(path as number[]);let cursor=0,last:number[]|undefined,start:number[]|undefined,previous:number[]|undefined,firstNext:number[]|undefined,closed=false;
          const segmentTo=(next:number[]|undefined,closing=false)=>{if(last&&next){const segment=bounds([Math.min(last[0],next[0]),Math.min(last[1],next[1]),Math.max(last[0],next[0]),Math.max(last[1],next[1])]);
              if(previous)joinRegion(last,previous,next);if(closing&&start&&firstNext)joinRegion(start,last,firstNext);firstNext??=next;
              const footprint=box(segment.bbox[0]-pad/viewport.width,segment.bbox[1]-pad/viewport.height,segment.bbox[2]+2*pad/viewport.width,segment.bbox[3]+2*pad/viewport.height);
              const line:Region={...segment,order:i,kind:'line',opaque:!optional&&!state.unsupportedState&&state.strokeAlpha>=0.999&&state.blend==='Normal'&&!state.mask&&insideClip(state.clip,segment.bbox)};
              addRegion({bbox:footprint,axisAligned:segment.axisAligned,order:i,kind:2*pad>2?'image':'stroke',opaque:false,line});if(2*pad>2)addGap({feature:'pdf_visibility',reason:'thick_stroke_overlap_requires_review'});else addRegion(line);
              previous=last;last=next;}};
          while(cursor<p.length){const command=p[cursor++];
            if(command===0){last=[p[cursor++],p[cursor++]];start=last;previous=undefined;firstNext=undefined;closed=false;}
            else if(command===1)segmentTo([p[cursor++],p[cursor++]]);
            else if(command===4){segmentTo(start,true);closed=true;}
            else if(command===2){unknownStroke();cursor+=6;last=undefined;}else if(command===3){unknownStroke();cursor+=4;last=undefined;}else break;
          }
          if(!closed&&[OPS.closeStroke,OPS.closeFillStroke,OPS.closeEOFillStroke].includes(paintOp))segmentTo(start,true);
        }
      }
    }
    const ordinaryImage=op===OPS.paintImageXObject||op===OPS.paintInlineImageXObject||op===OPS.paintImageMaskXObject||op===OPS.paintSolidColorImageMask;
    const complexPaint=[OPS.paintImageMaskXObjectGroup,OPS.paintImageMaskXObjectRepeat,OPS.paintImageXObjectRepeat,OPS.paintInlineImageXObjectGroup,OPS.shadingFill].includes(op);
    if(ordinaryImage||complexPaint){
      const shape=complexPaint?{bbox:box(0,0,1,1),axisAligned:false}:bounds([0,0,1,1]);addRegion({...shape,order:i,kind:'image',opaque:false});
      addGap({feature:'pdf_visibility',reason:'image_opacity_or_mask_requires_review'});
    }
  }
  const textRuns=new Map<number,{bbox:Box;ink?:Box;complete:boolean}>(),unknownRuns=new Set<number>();let lastUnknownTextOrder=-1;
  const envelope=(a:Box,b:Box)=>box(Math.min(a[0],b[0]),Math.min(a[1],b[1]),Math.max(a[0]+a[2],b[0]+b[2])-Math.min(a[0],b[0]),Math.max(a[1]+a[3],b[1]+b[3])-Math.min(a[1],b[1]));
  for(const g of glyphs){
    spend('work');
    if(g.hidden)continue;
    if(g.geometry_unverified){lastUnknownTextOrder=Math.max(lastUnknownTextOrder,g.order);unknownRuns.add(g.order);continue;}
    const footprint=g.reliable&&g.clip_ink?g.clip_ink:g.bbox,ink=g.reliable?g.paint_ink:undefined,run=textRuns.get(g.order);
    textRuns.set(g.order,{bbox:run?envelope(run.bbox,footprint):footprint,ink:ink?(run?.ink?envelope(run.ink,ink):ink):run?.ink,complete:(run?.complete??true)&&!!ink});
  }
  // An estimate is not a maximum painted extent. It can only withhold
  // visibility of earlier paint, never certify occlusion.
  // All such extents are the same full page: only the last visible unknown
  // order matters. Avoid per-operator duplicate evidence/region work.
  if(lastUnknownTextOrder>=0)addRegion({bbox:box(0,0,1,1),order:lastUnknownTextOrder,kind:'unknown_text',opaque:false,axisAligned:false});
  for(const [order,run] of textRuns)addRegion({bbox:run.bbox,order,kind:'text',opaque:false,axisAligned:false,...(run.complete&&!unknownRuns.has(order)&&run.ink?{ink:run.ink}:{})});
  const [px,py]=nativePixelMargins(viewport),paddedInk=(b:Box)=>box(b[0]-px,b[1]-py,b[2]+2*px,b[3]+2*py);
  const regionInk=new Map(regions.filter(r=>r.ink).map(r=>[r,paddedInk(r.ink!)]));
  // A fixed grid only narrows the existing exact overlap tests. Index BOTH
  // metric footprints and padded qualified ink, including overhangs. Retain
  // original region order because successive paints can change an assessment.
  // Broad regions occupy one shared list, never 4,096 copies per region.
  const cells=64,regionBuckets=new Map<number,number[]>(),broadRegions:number[]=[];
  const cellRange=(b:Box)=>[Math.max(0,Math.min(cells-1,Math.floor(b[0]*cells))),Math.max(0,Math.min(cells-1,Math.floor(b[1]*cells))),Math.max(0,Math.min(cells-1,Math.floor((b[0]+b[2])*cells))),Math.max(0,Math.min(cells-1,Math.floor((b[1]+b[3])*cells)))];
  for(let index=0;index<regions.length;index++){
    const r=regions[index],ink=regionInk.get(r),range=cellRange(ink?envelope(r.bbox,ink):r.bbox),[x0,y0,x1,y1]=range,count=(x1-x0+1)*(y1-y0+1);
    spend('work',1+(count>32?1:count));
    if(count>32){broadRegions.push(index);continue;}
    for(let y=y0;y<=y1;y++)for(let x=x0;x<=x1;x++){const key=y*cells+x,bucket=regionBuckets.get(key);if(bucket)bucket.push(index);else regionBuckets.set(key,[index]);}
  }
  const nearbyRegions=(bounds:Box):Region[]=>{
    const [x0,y0,x1,y1]=cellRange(bounds);spend('work',(x1-x0+1)*(y1-y0+1));
    let entries=broadRegions.length;
    for(let y=y0;y<=y1;y++)for(let x=x0;x<=x1;x++)entries+=regionBuckets.get(y*cells+x)?.length??0;
    // Reserve duplicate traversal, de-duplication, sorting and result storage
    // BEFORE allocating candidates; dense overlap still exhausts page work.
    spend('work',entries*(3+Math.ceil(Math.log2(entries+1))));
    const selected=new Set(broadRegions);
    for(let y=y0;y<=y1;y++)for(let x=x0;x<=x1;x++)for(const index of regionBuckets.get(y*cells+x)??[])selected.add(index);
    return [...selected].sort((a,b)=>a-b).map(index=>regions[index]);
  };
  const strikeLines=regions.filter(r=>r.kind==='line'&&r.opaque&&r.axisAligned);
  const annotationWork=annotations.reduce((n:number,a:any)=>n+1+(a.quadPoints?.length??0),0);
  const verticalBuckets=new Map<number,Region[]>(),connectedCache=new Map<Region,boolean>();
  for(const v of regions.filter(v=>v.kind==='line'&&v.bbox[2]<0.002&&v.bbox[3]>0.02)){const key=Math.floor(v.bbox[0]*100);const bucket=verticalBuckets.get(key);if(bucket)bucket.push(v);else verticalBuckets.set(key,[v]);}
  function connectedLine(r:Region):boolean{if(connectedCache.has(r))return connectedCache.get(r)!;const lineY=r.bbox[1]+r.bbox[3]/2;let connected=false;
    for(let key=Math.floor((r.bbox[0]-0.003)*100);key<=Math.floor((r.bbox[0]+r.bbox[2]+0.003)*100)&&!connected;key++){const bucket=verticalBuckets.get(key)??[];spend('work',1+bucket.length);connected=bucket.some(v=>v.bbox[0]>=r.bbox[0]-0.003&&v.bbox[0]<=r.bbox[0]+r.bbox[2]+0.003&&lineY>=v.bbox[1]-0.003&&lineY<=v.bbox[1]+v.bbox[3]+0.003);}
    connectedCache.set(r,connected);return connected;
  }
  function strikeCandidate(r:Region,e:ElementData):boolean{
    const mid=e.bbox[1]+e.bbox[3]*0.5,lineY=r.bbox[1]+r.bbox[3]/2,widthRatio=r.bbox[2]/e.bbox[2];
    return r.opaque&&r.axisAligned&&!connectedLine(r)&&r.bbox[3]<=Math.max(0.002,e.bbox[3]*0.13)&&Math.abs(lineY-mid)<e.bbox[3]*0.22&&widthRatio>=0.8&&widthRatio<=1.15;
  }
  // Correlate operator-derived glyphs with textContent only after geometry has been computed.
  let cursor=0;
  const stream:{char:string;glyph:(typeof glyphs)[number]}[]=[];for(const glyph of glyphs)for(let i=0;i<glyph.text.length;i++){spend('work');const char=glyph.text[i];if(!/\s/u.test(char))stream.push({char,glyph});}const source=stream.map(v=>v.char).join('');
  const findText=(target:string,start=0)=>{
    // Each native search is bounded by the admitted 500K page characters.
    // Charge the prefix actually traversed, rather than the entire remaining
    // page for every short consecutive run. Charge before slicing matches.
    const found=source.indexOf(target,start);
    spend('work',4*(found<0?Math.max(0,source.length-start):found-start+target.length));
    return found;
  };
  let uniqueText:ReturnType<typeof uniqueTextOccurrences>|undefined;
  for(const e of elements){
    const geometryUnverified=hasUnverifiedPdfGeometry(e);
    e.visibility='unverified';e.visibility_evidence=geometryUnverified?[{method:PDF_GEOMETRY_UNVERIFIED,bbox:e.bbox,assessment:'inferred',coverage:0}]:[];e.visibility_spans=[];
    spend('work',e.text.length);
    const evidenceKeys=new Map(e.visibility_evidence.map((v,i)=>[v.method+JSON.stringify(v.bbox),i]));
    const addEvidence=(method:string,bbox:Box,assessment:'observed'|'inferred',coverage:number)=>{const key=method+JSON.stringify(bbox),index=evidenceKeys.get(key);if(index!==undefined){const previous=e.visibility_evidence![index];previous.assessment=assessment;previous.coverage=coverage;return;}spend('evidence');evidenceKeys.set(key,e.visibility_evidence!.length);e.visibility_evidence!.push({method,bbox,assessment,coverage});};
    const target=compact(e.text),index=target?findText(target,cursor):-1;
    spend('work',4*target.length);
    const correlated=target&&index>=0?stream.slice(index,index+target.length):[];
    // Uniform explicit modes 3/7 do not paint text. A unique complete textual
    // match proves this independently of metrics, color or clipping geometry.
    const nonpainting=target&&correlated.length===target.length&&correlated.every(v=>v.glyph.nonpainting_mode);
    if(nonpainting&&(uniqueText??=uniqueTextOccurrences(source,spend))(target)){
      cursor=index+target.length;e.visibility='hidden_render_mode';addEvidence('explicit_nonpainting_text_mode',box(0,0,0,0),'observed',0);
      if(geometryUnverified)addGap({feature:'pdf_visibility',reason:PDF_GEOMETRY_UNVERIFIED});continue;
    }
    if(geometryUnverified){if(target&&index>=0)cursor=index+target.length;addGap({feature:'pdf_visibility',reason:PDF_GEOMETRY_UNVERIFIED});continue;}
    if(!target||index<0){addEvidence('glyph_text_correlation_unresolved',e.bbox,'inferred',0);addGap({feature:'pdf_visibility',reason:'visibility_requires_review:unverified'});continue;}
    const selected=[...new Set(correlated.map(v=>v.glyph))];cursor=index+target.length;
    if(!selected.every(g=>g.reliable)||selected.some(g=>overlap(g.bbox,e.bbox)<=0)){addEvidence('glyph_geometry_or_paint_state_unresolved',e.bbox,'inferred',0);addGap({feature:'pdf_visibility',reason:'visibility_requires_review:unverified'});continue;}
    // Annotation/line loops remain explicitly bounded. Spatial candidates
    // reserve their complete traversal/sort bound before per-glyph evidence.
    spend('work',selected.length*(annotationWork+1)+strikeLines.length);
    for(const g of selected){
      let state=g.hidden?'hidden_render_mode':'visible',assessment:'observed'|'inferred'=g.hidden?'observed':'inferred';
      if(g.clip_ink)addEvidence('loaded_glyph_outline_inside_rect_clip',g.clip_ink,'inferred',1);
      const footprint=g.clip_ink??g.bbox;
      const targetInk=g.reliable&&g.paint_ink?paddedInk(g.paint_ink):undefined,candidates=nearbyRegions(targetInk?envelope(footprint,targetInk):footprint);
      let background='#ffffff';for(const r of candidates)if(r.kind==='fill'&&r.opaque&&r.axisAligned&&r.order<g.order&&area(footprint)>0&&overlap(footprint,r.bbox)/area(footprint)>=0.95)background=r.color??'#ffffff';
      if(g.color!=='unknown'&&background!=='unknown'&&g.color===background){state='uncertain';addEvidence('text_color_matches_background',g.bbox,'inferred',1);}
      for(const r of candidates){
        if(r.order<=g.order)continue;
        const coverage=coverageOf(footprint,r.bbox);
        // A decimal point can occupy less than 5% of its font-metric box.
        // Any positive overlap is uncertain unless a stronger assessment applies.
        if(r.kind==='fill'&&r.order>g.order&&coverage>0){
          if(r.opaque&&r.axisAligned&&coverage>0.05){state=coverage>=0.999?'occluded':'partially_occluded';addEvidence('later_opaque_rectangle_per_glyph',r.bbox,'inferred',coverage);}
          else{state='uncertain';addEvidence('transparency_clip_or_transform_overlap',r.bbox,'inferred',coverage);}
        }
        // Grid membership or a small overlap cannot prove punctuation visibility.
        const shortStroke=r.kind==='stroke'&&r.order>g.order&&coverage>0&&(!r.line||!strikeCandidate(r.line,e));
        // Both sides must have qualified embedded outlines. One-sided ink vs
        // target advance metrics misses overhangs (f/j/italics). Pad EACH ink
        // envelope by the existing native-pixel floor before clearing overlap.
        // Incomplete later runs retain their entire original metric footprint.
        const inkPair=r.kind==='text'&&targetInk&&regionInk.has(r);
        const textTarget=inkPair?targetInk!:footprint,textRegion=inkPair?regionInk.get(r)!:r.bbox;
        const textCoverage=r.kind==='text'&&state==='visible'?coverageOf(textTarget,textRegion):0;
        if(((r.kind==='image'||r.kind==='unknown_text')&&coverage>0||shortStroke||r.kind==='text'&&textCoverage>0)&&r.order>g.order){state='uncertain';addEvidence(r.kind==='unknown_text'?'later_text_geometry_unverified':shortStroke?'short_stroke_glyph_overlap_unverified':r.kind==='text'?(inkPair?'later_embedded_text_ink_clearance_unverified':'later_text_glyph_overlap_unverified'):'later_image_opacity_unverified',r.kind==='text'?textRegion:r.bbox,'inferred',r.kind==='text'?textCoverage:coverage);}
      }
      for(const a of annotations){
        // PDF.js displays known annotation types with Invisible (1) set.
        // Hidden (2) and NoView (32) are the display exclusions.
        if(a.annotationFlags&34)continue;
        if(a.annotationType!==AnnotationType.STRIKEOUT){
          if((a.annotationType===AnnotationType.LINK||a.annotationType===AnnotationType.POPUP)&&!a.hasAppearance)continue;
          if(a.rect?.length===4){const r=bounds(Array.from(a.rect),[1,0,0,1,0,0]).bbox,coverage=coverageOf(g.bbox,r);if(coverage>0){state='uncertain';assessment='inferred';addEvidence(a.subtype==='Redact'?'redaction_annotation_intent_unapplied':'annotation_overlay_unverified',r,'inferred',coverage);}}
          continue;
        }
        const q=a.quadPoints?Array.from(a.quadPoints) as number[]:[];
        if(q.length<8){if(a.rect?.length===4&&overlap(g.bbox,bounds(Array.from(a.rect),[1,0,0,1,0,0]).bbox)>0){state='uncertain';assessment='inferred';}addEvidence('annotation_quadpoints_missing',e.bbox,'inferred',0);addGap({feature:'pdf_visibility',reason:'visibility_requires_review:unverified'});continue;}
        for(let k=0;k+7<q.length;k+=8){const group=q.slice(k,k+8),xs=group.filter((_,i)=>i%2===0),ys=group.filter((_,i)=>i%2===1),region=bounds([Math.min(...xs),Math.min(...ys),Math.max(...xs),Math.max(...ys)],[1,0,0,1,0,0]).bbox,coverage=coverageOf(g.bbox,region);
          if(coverage>0){if(['visible','struck_through','partially_struck_through'].includes(state)){state=coverage<=0.2?'uncertain':coverage>=0.8&&state!=='partially_struck_through'?'struck_through':'partially_struck_through';assessment=state==='struck_through'?'observed':'inferred';}
            addEvidence('strikeout_annotation_quad',region,assessment,coverage);}
        }
      }
      if(g.hidden)state='hidden_render_mode';
      if(state!=='hidden_render_mode'&&state!=='struck_through')assessment='inferred';
      spend('evidence');e.visibility_spans.push({text:g.text,state,bbox:g.bbox,paint_index:g.order,assessment});
    }
    const states=e.visibility_spans.map(s=>s.state);
    if(states.every(s=>s==='visible'))e.visibility='visible';
    else if(states.every(s=>s==='occluded'))e.visibility='occluded';
    else if(states.every(s=>s==='struck_through'))e.visibility='struck_through';
    else if(states.every(s=>s==='hidden_render_mode'))e.visibility='hidden_render_mode';
    else if(states.some(s=>s==='uncertain'))e.visibility='uncertain';
    else if(states.some(s=>s.includes('occluded')))e.visibility='partially_occluded';
    else if(states.some(s=>s.includes('struck')))e.visibility='partially_struck_through';
    const order=selected[0]?.order??Infinity;
    for(const r of strikeLines){
      if(r.order<=order)continue;
      if(strikeCandidate(r,e)&&e.visibility==='visible'){e.visibility='struck_inferred';addEvidence('flattened_non_grid_strike_candidate',r.bbox,'inferred',Math.min(1,r.bbox[2]/e.bbox[2]));}
    }
    if(!['visible','struck_through','hidden_render_mode'].includes(e.visibility))addGap({feature:'pdf_visibility',reason:'visibility_requires_review:'+e.visibility});
  }
  // Grid inference is explicitly separate from original PowerPoint table semantics.
  const lines=regions.filter(r=>r.kind==='line'&&r.opaque&&r.axisAligned);
  const h=lines.filter(r=>r.bbox[3]<0.002&&r.bbox[2]>0.1),v=lines.filter(r=>r.bbox[2]<0.002&&r.bbox[3]>0.05);
  if(h.length>=3&&v.length>=3&&h.length+v.length<=1000){
    const tolerance=2/Math.min(viewport.width,viewport.height),remaining=new Set([...h,...v]);let tableIndex=0;
    while(remaining.size){
      const first=remaining.values().next().value!,component:Region[]=[first];remaining.delete(first);
      for(let cursor=0;cursor<component.length;cursor++)for(const line of [...remaining]){
        spend('work');
        const a=component[cursor].bbox,b=line.bbox;
        const touches=a[0]<=b[0]+b[2]+tolerance&&a[0]+a[2]+tolerance>=b[0]&&a[1]<=b[1]+b[3]+tolerance&&a[1]+a[3]+tolerance>=b[1];
        if(touches){component.push(line);remaining.delete(line);}
      }
      spend('work',component.length*(h.length+v.length));
      const hs=component.filter(r=>h.includes(r)),vs=component.filter(r=>v.includes(r));if(hs.length<3||vs.length<3)continue;
      const xs=[...new Set(vs.map(l=>Number(l.bbox[0].toFixed(4))))].sort((a,b)=>a-b),ys=[...new Set(hs.map(l=>Number(l.bbox[1].toFixed(4))))].sort((a,b)=>a-b);
      const xmin=xs[0],xmax=xs.at(-1)!,ymin=ys[0],ymax=ys.at(-1)!;
      if(hs.some(l=>Math.abs(l.bbox[0]-xmin)>tolerance||Math.abs(l.bbox[0]+l.bbox[2]-xmax)>tolerance)||vs.some(l=>Math.abs(l.bbox[1]-ymin)>tolerance||Math.abs(l.bbox[1]+l.bbox[3]-ymax)>tolerance))continue;
      spend('work',elements.length*(xs.length+ys.length+1));
      const assignments=elements.flatMap(e=>{if(hasUnverifiedPdfGeometry(e))return [];const cx=e.bbox[0]+e.bbox[2]/2,cy=e.bbox[1]+e.bbox[3]/2,col=xs.findIndex((x,i)=>i<xs.length-1&&cx>=x&&cx<xs[i+1]),row=ys.findIndex((y,i)=>i<ys.length-1&&cy>=y&&cy<ys[i+1]);
        return row>=0&&col>=0&&e.bbox[0]>=xs[col]-tolerance&&e.bbox[0]+e.bbox[2]<=xs[col+1]+tolerance&&e.bbox[1]>=ys[row]-tolerance&&e.bbox[1]+e.bbox[3]<=ys[row+1]+tolerance?[{e,row,col}]:[];});
      if(new Set(assignments.map(a=>a.row)).size<2||new Set(assignments.map(a=>a.col)).size<2)continue;
      tableIndex++;for(const {e,row,col} of assignments)e.table={table_id:'pdf_grid_'+tableIndex,row,column:col,origin:'pdf_grid_inferred',assessment:'inferred'};
    }
  }

  elements.push(...annotationEvidence.elements);
  if(sawComplexClipOrMask||state.mask||state.clip==='unknown'||state.pendingClip)addGap({feature:'pdf_visibility',reason:'clipping_or_soft_mask_visibility_not_fully_verified'});
  return{regions,gaps};
  }catch(error){if(error instanceof PdfAppearanceBudgetExceeded)return withhold('appearance_budget_exceeded_visibility_unverified');throw error;}
}
