import { transformedBounds,rectanglePath,intersectClip,insideClip,type Clip } from './pdf-geometry.js';
import { paintedGlyphs } from './pdf-glyphs.js';
import { OPS, AnnotationType, AnnotationMode, Util } from 'pdfjs-dist/legacy/build/pdf.mjs';
import { box, normalize, type Box, type ElementData } from '../schema/index.js';
interface Region {bbox:Box;order:number;kind:'fill'|'line'|'stroke'|'image'|'text';opaque:boolean;axisAligned:boolean;color?:string;line?:Region}
const area=(b:Box)=>b[2]*b[3];
const overlap=(a:Box,b:Box)=>Math.max(0,Math.min(a[0]+a[2],b[0]+b[2])-Math.max(a[0],b[0]))*Math.max(0,Math.min(a[1]+a[3],b[1]+b[3])-Math.max(a[1],b[1]));
const compact=(s:string)=>normalize(s).replace(/\s/gu,'');
export async function inspectAppearance(page:any,viewport:any,elements:ElementData[],fontStyles:Record<string,any>={}):Promise<{regions:Region[];gaps:{feature:string;reason:string}[]}> {
  const operators=await page.getOperatorList({annotationMode:AnnotationMode.DISABLE}),annotations=await page.getAnnotations({intent:'display'}),regions:Region[]=[],gaps:{feature:string;reason:string}[]=[];
  if(operators.fnArray.length>250000){for(const e of elements)e.visibility='unverified';return{regions,gaps:[{feature:'pdf_visibility',reason:'operator_limit_exceeded_visibility_unverified'}]};}
  let state={matrix:[1,0,0,1,0,0],alpha:1,strokeAlpha:1,lineWidth:1,blend:'Normal',mask:false,clip:null as Clip,pendingClip:false,textMode:0,textClipPending:false,color:'#000000'},stack:typeof state[]=[],marked:boolean[]=[];let sawComplexClipOrMask=false,optional=false;
  const glyphs=paintedGlyphs(page,viewport,operators,fontStyles);
  const bounds=(rect:number[],matrix=state.matrix)=>transformedBounds(rect,matrix,viewport);
  for(let i=0;i<operators.fnArray.length;i++){
    const op=operators.fnArray[i],args=operators.argsArray[i];
    if(op===OPS.beginMarkedContent||op===OPS.beginMarkedContentProps){marked.push(optional);if(args?.[0]==='OC'){optional=true;gaps.push({feature:'pdf_visibility',reason:'optional_content_visibility_unverified'});}continue;}
    if(op===OPS.endMarkedContent){optional=marked.pop()??false;continue;}
    if(op===OPS.setTextRenderingMode){state.textMode=Number(args[0]);continue;}
    if([OPS.showText,OPS.showSpacedText,OPS.nextLineShowText,OPS.nextLineSetSpacingShowText].includes(op)&&state.textMode>=4)state.textClipPending=true;
    if(op===OPS.endText&&state.textClipPending){state.clip='unknown';state.textClipPending=false;sawComplexClipOrMask=true;continue;}
    if(op===OPS.save){stack.push({...state,matrix:[...state.matrix]});continue;}
    if(op===OPS.restore){state=stack.pop()??state;continue;}
    if(op===OPS.setLineWidth){state.lineWidth=Number(args[0]);continue;}
    if([OPS.setFillGray,OPS.setFillCMYKColor,OPS.setFillColor,OPS.setFillColorN].includes(op)){state.color='unknown';continue;}
    if(op===OPS.setFillRGBColor){state.color=typeof args[0]==='string'?args[0]:'unknown';continue;}
    if(op===OPS.paintFormXObjectBegin){stack.push({...state,matrix:[...state.matrix]});if(args[0])state.matrix=Util.transform(state.matrix,args[0]);if(args[1]){const b=bounds(Array.from(args[1]));state.clip=intersectClip(state.clip,b.axisAligned?b.bbox:'unknown');}continue;}
    if(op===OPS.paintFormXObjectEnd){state=stack.pop()??state;continue;}
    if(op===OPS.beginGroup){stack.push({...state,matrix:[...state.matrix]});state.mask=true;sawComplexClipOrMask=true;continue;}
    if(op===OPS.endGroup){state=stack.pop()??state;continue;}
    if(op===OPS.transform){state.matrix=Util.transform(state.matrix,args);continue;}
    if(op===OPS.setGState){for(const [key,value] of args[0]??[]){if(key==='ca')state.alpha=Number(value);if(key==='CA')state.strokeAlpha=Number(value);if(key==='BM')state.blend=['source-over','Normal','Compatible'].includes(String(value))?'Normal':String(value);if(key==='SMask')state.mask=value!==false&&value!=='None';}if(state.mask)sawComplexClipOrMask=true;continue;}
    if(op===OPS.clip||op===OPS.eoClip){state.pendingClip=true;continue;}
    if(op===OPS.constructPath&&Array.isArray(args)&&args.length>=3){
      const [paintOp,paths,rect]=args;if(!rect||rect.length<4){regions.push({bbox:box(0,0,1,1),axisAligned:false,order:i,kind:'image',opaque:false});gaps.push({feature:'pdf_visibility',reason:'path_geometry_unresolved'});continue;}
      const shape=bounds(Array.from(rect)),isRectangle=rectanglePath(paths);
      if(state.pendingClip){state.clip=intersectClip(state.clip,isRectangle&&shape.axisAligned?shape.bbox:'unknown');state.pendingClip=false;if(state.clip==='unknown')sawComplexClipOrMask=true;}
      const fill=[OPS.fill,OPS.eoFill,OPS.fillStroke,OPS.eoFillStroke,OPS.closeFillStroke,OPS.closeEOFillStroke].includes(paintOp);
      const stroke=[OPS.stroke,OPS.closeStroke,OPS.fillStroke,OPS.eoFillStroke,OPS.closeFillStroke,OPS.closeEOFillStroke].includes(paintOp);
      if(fill&&isRectangle)regions.push({...shape,order:i,kind:'fill',color:state.color,opaque:!optional&&state.color!=='unknown'&&state.alpha>=0.999&&state.blend==='Normal'&&!state.mask&&insideClip(state.clip,shape.bbox)});
      else if(fill&&area(shape.bbox)>0){regions.push({...shape,order:i,kind:'fill',opaque:false});gaps.push({feature:'pdf_visibility',reason:'non_rectangular_fill_not_used_as_confirmed_occlusion'});}
      if(stroke){
        let curveReported=false;
        const unknownStroke=()=>{if(curveReported)return;curveReported=true;const m=Util.transform(viewport.transform,state.matrix),pad=state.lineWidth*Math.max(Math.hypot(m[0],m[1]),Math.hypot(m[2],m[3]))/2;
          regions.push({bbox:box(shape.bbox[0]-pad/viewport.width,shape.bbox[1]-pad/viewport.height,shape.bbox[2]+2*pad/viewport.width,shape.bbox[3]+2*pad/viewport.height),order:i,kind:'image',opaque:false,axisAligned:false});gaps.push({feature:'pdf_visibility',reason:'curve_stroke_visibility_unverified'});};
        // A single stroke can contain every border of a table or many strike lines.
        for(const path of paths??[]){const p=Array.from(path as number[]);let cursor=0,last:number[]|undefined,start:number[]|undefined;
          while(cursor<p.length){const command=p[cursor++];
            if(command===0){last=[p[cursor++],p[cursor++]];start=last;}
            else if(command===1||command===4){const next=command===4?start:[p[cursor++],p[cursor++]];
              if(last&&next){const segment=bounds([Math.min(last[0],next[0]),Math.min(last[1],next[1]),Math.max(last[0],next[0]),Math.max(last[1],next[1])]);
                const m=Util.transform(viewport.transform,state.matrix),pad=state.lineWidth*Math.max(Math.hypot(m[0],m[1]),Math.hypot(m[2],m[3]))/2;
                const footprint=box(segment.bbox[0]-pad/viewport.width,segment.bbox[1]-pad/viewport.height,segment.bbox[2]+2*pad/viewport.width,segment.bbox[3]+2*pad/viewport.height);
                const line:Region={...segment,order:i,kind:'line',opaque:!optional&&state.strokeAlpha>=0.999&&state.blend==='Normal'&&!state.mask&&insideClip(state.clip,segment.bbox)};
                regions.push({bbox:footprint,axisAligned:segment.axisAligned,order:i,kind:2*pad>2?'image':'stroke',opaque:false,line});
                if(2*pad>2)gaps.push({feature:'pdf_visibility',reason:'thick_stroke_overlap_requires_review'});
                else regions.push(line);
              }last=next;}
            else if(command===2){unknownStroke();cursor+=6;last=undefined;}else if(command===3){unknownStroke();cursor+=4;last=undefined;}else break;
          }
        }
      }
    }
    const ordinaryImage=op===OPS.paintImageXObject||op===OPS.paintInlineImageXObject||op===OPS.paintImageMaskXObject||op===OPS.paintSolidColorImageMask;
    const complexPaint=[OPS.paintImageMaskXObjectGroup,OPS.paintImageMaskXObjectRepeat,OPS.paintImageXObjectRepeat,OPS.paintInlineImageXObjectGroup,OPS.shadingFill].includes(op);
    if(ordinaryImage||complexPaint){
      const shape=complexPaint?{bbox:box(0,0,1,1),axisAligned:false}:bounds([0,0,1,1]);regions.push({...shape,order:i,kind:'image',opaque:false});
      gaps.push({feature:'pdf_visibility',reason:'image_opacity_or_mask_requires_review'});
    }
  }
  const textRuns=new Map<number,Box>();
  for(const g of glyphs){if(g.hidden)continue;const b=textRuns.get(g.order);textRuns.set(g.order,b?box(Math.min(b[0],g.bbox[0]),Math.min(b[1],g.bbox[1]),Math.max(b[0]+b[2],g.bbox[0]+g.bbox[2])-Math.min(b[0],g.bbox[0]),Math.max(b[1]+b[3],g.bbox[1]+g.bbox[3])-Math.min(b[1],g.bbox[1])):g.bbox);}
  for(const [order,bbox] of textRuns)regions.push({bbox,order,kind:'text',opaque:false,axisAligned:false});
  const verticalBuckets=new Map<number,Region[]>(),connectedCache=new Map<Region,boolean>();
  for(const v of regions.filter(v=>v.kind==='line'&&v.bbox[2]<0.002&&v.bbox[3]>0.02)){const key=Math.floor(v.bbox[0]*100);verticalBuckets.set(key,[...(verticalBuckets.get(key)??[]),v]);}
  function connectedLine(r:Region):boolean{if(connectedCache.has(r))return connectedCache.get(r)!;const lineY=r.bbox[1]+r.bbox[3]/2;let connected=false;
    for(let key=Math.floor((r.bbox[0]-0.003)*100);key<=Math.floor((r.bbox[0]+r.bbox[2]+0.003)*100)&&!connected;key++)connected=(verticalBuckets.get(key)??[]).some(v=>v.bbox[0]>=r.bbox[0]-0.003&&v.bbox[0]<=r.bbox[0]+r.bbox[2]+0.003&&lineY>=v.bbox[1]-0.003&&lineY<=v.bbox[1]+v.bbox[3]+0.003);
    connectedCache.set(r,connected);return connected;
  }
  function strikeCandidate(r:Region,e:ElementData):boolean{
    const mid=e.bbox[1]+e.bbox[3]*0.5,lineY=r.bbox[1]+r.bbox[3]/2,widthRatio=r.bbox[2]/e.bbox[2];
    return r.opaque&&r.axisAligned&&!connectedLine(r)&&r.bbox[3]<=Math.max(0.002,e.bbox[3]*0.13)&&Math.abs(lineY-mid)<e.bbox[3]*0.22&&widthRatio>=0.8&&widthRatio<=1.15;
  }
  // Correlate operator-derived glyphs with textContent only after geometry has been computed.
  let cursor=0;
  const stream=glyphs.flatMap(g=>g.text.split('').filter(c=>!/\s/u.test(c)).map(c=>({char:c,glyph:g}))),source=stream.map(v=>v.char).join('');
  for(const e of elements){
    e.visibility='unverified';e.visibility_evidence=[];e.visibility_spans=[];
    const target=compact(e.text),index=source.indexOf(target,cursor);
    if(!target||index<0){e.visibility_evidence.push({method:'glyph_text_correlation_unresolved',bbox:e.bbox,assessment:'inferred',coverage:0});gaps.push({feature:'pdf_visibility',reason:'visibility_requires_review:unverified'});continue;}
    const selected=[...new Set(stream.slice(index,index+target.length).map(v=>v.glyph))];cursor=index+target.length;
    if(!selected.every(g=>g.reliable)||selected.some(g=>overlap(g.bbox,e.bbox)<=0)){e.visibility_evidence.push({method:'glyph_geometry_or_paint_state_unresolved',bbox:e.bbox,assessment:'inferred',coverage:0});gaps.push({feature:'pdf_visibility',reason:'visibility_requires_review:unverified'});continue;}
    for(const g of selected){
      let state=g.hidden?'hidden_render_mode':'visible',assessment:'observed'|'inferred'=g.hidden?'observed':'inferred';
      const backgrounds=regions.filter(r=>r.kind==='fill'&&r.opaque&&r.axisAligned&&r.order<g.order&&area(g.bbox)>0&&overlap(g.bbox,r.bbox)/area(g.bbox)>=0.95);
      const background=backgrounds.at(-1)?.color??'#ffffff';
      if(g.color!=='unknown'&&background!=='unknown'&&g.color===background){state='uncertain';e.visibility_evidence.push({method:'text_color_matches_background',bbox:g.bbox,assessment:'inferred',coverage:1});}
      const centralBand=box(g.bbox[0],g.bbox[1]+g.bbox[3]*0.25,g.bbox[2],g.bbox[3]*0.5);
      for(const r of regions){
        const coverage=area(g.bbox)>0?overlap(g.bbox,r.bbox)/area(g.bbox):0;
        if(r.kind==='fill'&&r.order>g.order&&coverage>0.05){
          if(r.opaque&&r.axisAligned){state=coverage>=0.999?'occluded':'partially_occluded';e.visibility_evidence.push({method:'later_opaque_rectangle_per_glyph',bbox:r.bbox,assessment:'inferred',coverage});}
          else{state='uncertain';e.visibility_evidence.push({method:'transparency_clip_or_transform_overlap',bbox:r.bbox,assessment:'inferred',coverage});}
        }
        // Even a short thin line can erase a minus sign. Grid membership does
        // not prove visibility when a stroke crosses the actual glyph body.
        const shortStroke=r.kind==='stroke'&&r.order>g.order&&coverage>0.005&&overlap(centralBand,r.bbox)>0&&(!r.line||!strikeCandidate(r.line,e));
        if((r.kind==='image'&&coverage>0.005||r.kind==='stroke'&&coverage>0.2||shortStroke||r.kind==='text'&&state==='visible'&&coverage>0.2)&&r.order>g.order){state='uncertain';e.visibility_evidence.push({method:shortStroke?'short_stroke_glyph_body_overlap_unverified':'later_image_opacity_unverified',bbox:r.bbox,assessment:'inferred',coverage});}
      }
      for(const a of annotations){
        if(a.annotationFlags&35)continue;
        if(a.annotationType!==AnnotationType.STRIKEOUT&&a.subtype!=='Redact'){
          if(a.annotationType===AnnotationType.LINK||a.annotationType===AnnotationType.POPUP)continue;
          if(a.rect?.length===4){const r=bounds(Array.from(a.rect),[1,0,0,1,0,0]).bbox,coverage=area(g.bbox)>0?overlap(g.bbox,r)/area(g.bbox):0;if(coverage>0.2){state='uncertain';e.visibility_evidence.push({method:'annotation_overlay_unverified',bbox:r,assessment:'inferred',coverage});}}
          continue;
        }
        const q=a.quadPoints?Array.from(a.quadPoints) as number[]:[];
        if(q.length<8){e.visibility_evidence.push({method:'annotation_quadpoints_missing',bbox:e.bbox,assessment:'inferred',coverage:0});gaps.push({feature:'pdf_visibility',reason:'visibility_requires_review:unverified'});continue;}
        for(let k=0;k+7<q.length;k+=8){const group=q.slice(k,k+8),xs=group.filter((_,i)=>i%2===0),ys=group.filter((_,i)=>i%2===1),region=bounds([Math.min(...xs),Math.min(...ys),Math.max(...xs),Math.max(...ys)],[1,0,0,1,0,0]).bbox,coverage=area(g.bbox)>0?overlap(region,g.bbox)/area(g.bbox):0;
          if(coverage>0.2){if(a.subtype==='Redact'){state='uncertain';assessment='inferred';}else if(['visible','struck_through','partially_struck_through'].includes(state)){state=coverage>=0.8&&state!=='partially_struck_through'?'struck_through':'partially_struck_through';assessment=state==='struck_through'?'observed':'inferred';}
            e.visibility_evidence.push({method:a.subtype==='Redact'?'redaction_annotation_intent_unapplied':'strikeout_annotation_quad',bbox:region,assessment,coverage});}
        }
      }
      if(g.hidden)state='hidden_render_mode';
      if(state!=='hidden_render_mode'&&state!=='struck_through')assessment='inferred';
      e.visibility_spans.push({text:g.text,state,bbox:g.bbox,paint_index:g.order,assessment});
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
    for(const r of regions.filter(r=>r.kind==='line'&&r.opaque&&r.order>order&&r.axisAligned)){
      if(strikeCandidate(r,e)&&e.visibility==='visible'){e.visibility='struck_inferred';e.visibility_evidence.push({method:'flattened_non_grid_strike_candidate',bbox:r.bbox,assessment:'inferred',coverage:Math.min(1,r.bbox[2]/e.bbox[2])});}
    }
    e.visibility_evidence=[...new Map(e.visibility_evidence.map(v=>[v.method+JSON.stringify(v.bbox),v])).values()];
    if(!['visible','struck_through','hidden_render_mode'].includes(e.visibility))gaps.push({feature:'pdf_visibility',reason:'visibility_requires_review:'+e.visibility});
  }
  // Grid inference is explicitly separate from original PowerPoint table semantics.
  const lines=regions.filter(r=>r.kind==='line'&&r.opaque&&r.axisAligned);
  const h=lines.filter(r=>r.bbox[3]<0.002&&r.bbox[2]>0.1),v=lines.filter(r=>r.bbox[2]<0.002&&r.bbox[3]>0.05);
  if(h.length>=3&&v.length>=3&&h.length+v.length<=1000){
    const tolerance=2/Math.min(viewport.width,viewport.height),remaining=new Set([...h,...v]);let tableIndex=0;
    while(remaining.size){
      const first=remaining.values().next().value!,component:Region[]=[first];remaining.delete(first);
      for(let cursor=0;cursor<component.length;cursor++)for(const line of [...remaining]){
        const a=component[cursor].bbox,b=line.bbox;
        const touches=a[0]<=b[0]+b[2]+tolerance&&a[0]+a[2]+tolerance>=b[0]&&a[1]<=b[1]+b[3]+tolerance&&a[1]+a[3]+tolerance>=b[1];
        if(touches){component.push(line);remaining.delete(line);}
      }
      const hs=component.filter(r=>h.includes(r)),vs=component.filter(r=>v.includes(r));if(hs.length<3||vs.length<3)continue;
      const xs=[...new Set(vs.map(l=>Number(l.bbox[0].toFixed(4))))].sort((a,b)=>a-b),ys=[...new Set(hs.map(l=>Number(l.bbox[1].toFixed(4))))].sort((a,b)=>a-b);
      const xmin=xs[0],xmax=xs.at(-1)!,ymin=ys[0],ymax=ys.at(-1)!;
      if(hs.some(l=>Math.abs(l.bbox[0]-xmin)>tolerance||Math.abs(l.bbox[0]+l.bbox[2]-xmax)>tolerance)||vs.some(l=>Math.abs(l.bbox[1]-ymin)>tolerance||Math.abs(l.bbox[1]+l.bbox[3]-ymax)>tolerance))continue;
      const assignments=elements.flatMap(e=>{const cx=e.bbox[0]+e.bbox[2]/2,cy=e.bbox[1]+e.bbox[3]/2,col=xs.findIndex((x,i)=>i<xs.length-1&&cx>=x&&cx<xs[i+1]),row=ys.findIndex((y,i)=>i<ys.length-1&&cy>=y&&cy<ys[i+1]);
        return row>=0&&col>=0&&e.bbox[0]>=xs[col]-tolerance&&e.bbox[0]+e.bbox[2]<=xs[col+1]+tolerance&&e.bbox[1]>=ys[row]-tolerance&&e.bbox[1]+e.bbox[3]<=ys[row+1]+tolerance?[{e,row,col}]:[];});
      if(new Set(assignments.map(a=>a.row)).size<2||new Set(assignments.map(a=>a.col)).size<2)continue;
      tableIndex++;for(const {e,row,col} of assignments)e.table={table_id:'pdf_grid_'+tableIndex,row,column:col,origin:'pdf_grid_inferred',assessment:'inferred'};
    }
  }

  if(sawComplexClipOrMask||state.mask||state.clip==='unknown'||state.pendingClip)gaps.push({feature:'pdf_visibility',reason:'clipping_or_soft_mask_visibility_not_fully_verified'});
  return{regions,gaps:[...new Map(gaps.map(g=>[g.reason,g])).values()]};
}
