import { paintedGlyphs } from './pdf-glyphs.js';
import { OPS, AnnotationType, Util } from 'pdfjs-dist/legacy/build/pdf.mjs';
import { box, normalize, type Box, type ElementData } from '../schema/index.js';
interface Region {bbox:Box;order:number;kind:'fill'|'line'|'image';opaque:boolean;axisAligned:boolean;color?:string}
const area=(b:Box)=>b[2]*b[3];
const overlap=(a:Box,b:Box)=>Math.max(0,Math.min(a[0]+a[2],b[0]+b[2])-Math.max(a[0],b[0]))*Math.max(0,Math.min(a[1]+a[3],b[1]+b[3])-Math.max(a[1],b[1]));
const compact=(s:string)=>normalize(s).replace(/\s/gu,'');
export async function inspectAppearance(page:any,viewport:any,elements:ElementData[]):Promise<{regions:Region[];gaps:{feature:string;reason:string}[]}> {
  const operators=await page.getOperatorList(),annotations=await page.getAnnotations({intent:'display'}),regions:Region[]=[],gaps:{feature:string;reason:string}[]=[];
  if(operators.fnArray.length>250000){for(const e of elements)e.visibility='unverified';return{regions,gaps:[{feature:'pdf_visibility',reason:'operator_limit_exceeded_visibility_unverified'}]};}
  let state={matrix:[1,0,0,1,0,0],alpha:1,blend:'Normal',mask:false,clip:false,color:'#000000'},stack:typeof state[]=[];
  const glyphs=paintedGlyphs(page,viewport,operators);
  function bounds(rect:number[],matrix=state.matrix):{bbox:Box;axisAligned:boolean;color?:string}{
    const transform=Util.transform(viewport.transform,matrix);
    const points=[[rect[0],rect[1]],[rect[2],rect[1]],[rect[2],rect[3]],[rect[0],rect[3]]].map(p=>{Util.applyTransform(p,transform);return p;});
    const xs=points.map(p=>p[0]),ys=points.map(p=>p[1]);
    const axisAligned=(Math.abs(points[1][0]-points[0][0])<0.01||Math.abs(points[1][1]-points[0][1])<0.01)&&(Math.abs(points[2][0]-points[1][0])<0.01||Math.abs(points[2][1]-points[1][1])<0.01);
    return{bbox:box(Math.min(...xs)/viewport.width,Math.min(...ys)/viewport.height,(Math.max(...xs)-Math.min(...xs))/viewport.width,(Math.max(...ys)-Math.min(...ys))/viewport.height),axisAligned};
  }
  for(let i=0;i<operators.fnArray.length;i++){
    const op=operators.fnArray[i],args=operators.argsArray[i];
    if(op===OPS.save){stack.push({...state,matrix:[...state.matrix]});continue;}
    if(op===OPS.restore){state=stack.pop()??state;continue;}
    if(op===OPS.setFillRGBColor){state.color=typeof args[0]==='string'?args[0]:'unknown';continue;}
    if(op===OPS.paintFormXObjectBegin){stack.push({...state,matrix:[...state.matrix]});if(args[0])state.matrix=Util.transform(state.matrix,args[0]);if(args[1])state.clip=true;continue;}
    if(op===OPS.paintFormXObjectEnd){state=stack.pop()??state;continue;}
    if(op===OPS.beginGroup){stack.push({...state,matrix:[...state.matrix]});state.mask=true;continue;}
    if(op===OPS.endGroup){state=stack.pop()??state;continue;}
    if(op===OPS.transform){state.matrix=Util.transform(state.matrix,args);continue;}
    if(op===OPS.setGState){for(const [key,value] of args[0]??[]){if(key==='ca')state.alpha=Number(value);if(key==='BM')state.blend=String(value);if(key==='SMask')state.mask=value!==false&&value!=='None';}continue;}
    if(op===OPS.clip||op===OPS.eoClip){state.clip=true;continue;}
    if(op===OPS.constructPath&&Array.isArray(args)&&args.length>=3){
      const [paintOp,paths,rect]=args;if(!rect||rect.length<4)continue;
      const chunks=(paths??[]).flatMap((p:any)=>Array.from(p as number[])) as number[];
      const shape=bounds(Array.from(rect));
      const fill=[OPS.fill,OPS.eoFill,OPS.fillStroke,OPS.eoFillStroke,OPS.closeFillStroke,OPS.closeEOFillStroke].includes(paintOp);
      const stroke=[OPS.stroke,OPS.closeStroke,OPS.fillStroke,OPS.eoFillStroke,OPS.closeFillStroke,OPS.closeEOFillStroke].includes(paintOp);
      // PDF.js 6's normalized path encoding: move(0), line(1), cubic(2), close(4).
      const vertices=[chunks.slice(1,3),chunks.slice(4,6),chunks.slice(7,9),chunks.slice(10,12)];
      const isRectangle=chunks.length===13&&chunks[0]===0&&chunks[3]===1&&chunks[6]===1&&chunks[9]===1&&chunks[12]===4
        &&vertices.every((p,j)=>{const q=vertices[(j+1)%4];return (Math.abs(p[0]-q[0])<0.001)!==(Math.abs(p[1]-q[1])<0.001);})
        &&new Set(vertices.map(p=>p[0])).size===2&&new Set(vertices.map(p=>p[1])).size===2;
      const isLine=chunks.length===6&&chunks[0]===0&&chunks[3]===1;
      if(fill&&isRectangle)regions.push({...shape,order:i,kind:'fill',color:state.color,opaque:state.alpha>=0.999&&state.blend==='Normal'&&!state.mask&&!state.clip});
      else if(fill&&area(shape.bbox)>0){regions.push({...shape,order:i,kind:'fill',opaque:false});gaps.push({feature:'pdf_visibility',reason:'non_rectangular_fill_not_used_as_confirmed_occlusion'});}
      if(stroke&&isLine)regions.push({...shape,order:i,kind:'line',opaque:state.alpha>=0.999&&state.blend==='Normal'&&!state.mask&&!state.clip});
    }
    if(op===OPS.paintImageXObject||op===OPS.paintInlineImageXObject){
      const shape=bounds([0,0,1,1]);regions.push({...shape,order:i,kind:'image',opaque:false});
      gaps.push({feature:'pdf_visibility',reason:'image_opacity_or_mask_requires_review'});
    }
  }
  // Correlate operator-derived glyphs with textContent only after geometry has been computed.
  let cursor=0;
  const stream=glyphs.flatMap(g=>g.text.split('').filter(c=>!/\s/u.test(c)).map(c=>({char:c,glyph:g}))),source=stream.map(v=>v.char).join('');
  for(const e of elements){
    e.visibility='unverified';e.visibility_evidence=[];e.visibility_spans=[];
    const target=compact(e.text),index=source.indexOf(target,cursor);
    if(!target||index<0){e.visibility_evidence.push({method:'glyph_text_correlation_unresolved',bbox:e.bbox,assessment:'inferred',coverage:0});gaps.push({feature:'pdf_visibility',reason:'visibility_requires_review:unverified'});continue;}
    const selected=[...new Set(stream.slice(index,index+target.length).map(v=>v.glyph))];cursor=index+target.length;
    if(!selected.every(g=>g.reliable)||selected.some(g=>overlap(g.bbox,e.bbox)<=0)){e.visibility_evidence.push({method:'font_metrics_or_glyph_geometry_unresolved',bbox:e.bbox,assessment:'inferred',coverage:0});gaps.push({feature:'pdf_visibility',reason:'visibility_requires_review:unverified'});continue;}
    for(const g of selected){
      let state=g.hidden?'hidden_render_mode':'visible',assessment:'observed'|'inferred'=g.hidden?'observed':'inferred';
      const backgrounds=regions.filter(r=>r.kind==='fill'&&r.opaque&&r.order<g.order&&area(g.bbox)>0&&overlap(g.bbox,r.bbox)/area(g.bbox)>=0.95);
      const background=backgrounds.at(-1)?.color??'#ffffff';
      if(g.color===background){state='uncertain';e.visibility_evidence.push({method:'text_color_matches_background',bbox:g.bbox,assessment:'inferred',coverage:1});}
      for(const r of regions){
        const coverage=area(g.bbox)>0?overlap(g.bbox,r.bbox)/area(g.bbox):0;
        if(r.kind==='fill'&&r.order>g.order&&coverage>0.05){
          if(r.opaque&&r.axisAligned){state=coverage>=0.95?'occluded':'partially_occluded';e.visibility_evidence.push({method:'later_opaque_rectangle_per_glyph',bbox:r.bbox,assessment:'inferred',coverage});}
          else if(coverage>=0.2){state='uncertain';e.visibility_evidence.push({method:'transparency_clip_or_transform_overlap',bbox:r.bbox,assessment:'inferred',coverage});}
        }
        if(r.kind==='image'&&r.order>g.order&&coverage>0.2){state='uncertain';e.visibility_evidence.push({method:'later_image_opacity_unverified',bbox:r.bbox,assessment:'inferred',coverage});}
      }
      for(const a of annotations){
        if(a.annotationFlags&35)continue;
        if(a.annotationType!==AnnotationType.STRIKEOUT&&a.subtype!=='Redact')continue;
        const q=a.quadPoints?Array.from(a.quadPoints) as number[]:[];
        if(q.length<8){e.visibility_evidence.push({method:'annotation_quadpoints_missing',bbox:e.bbox,assessment:'inferred',coverage:0});gaps.push({feature:'pdf_visibility',reason:'visibility_requires_review:unverified'});continue;}
        for(let k=0;k+7<q.length;k+=8){const group=q.slice(k,k+8),xs=group.filter((_,i)=>i%2===0),ys=group.filter((_,i)=>i%2===1),region=bounds([Math.min(...xs),Math.min(...ys),Math.max(...xs),Math.max(...ys)],[1,0,0,1,0,0]).bbox,coverage=area(g.bbox)>0?overlap(region,g.bbox)/area(g.bbox):0;
          if(coverage>0.2){if(a.subtype==='Redact'){state='uncertain';assessment='inferred';}else if(coverage>=0.8&&state!=='occluded'){state='struck_through';assessment='observed';}else if(state!=='occluded'){state='partially_struck_through';assessment='inferred';}
            e.visibility_evidence.push({method:a.subtype==='Redact'?'redaction_annotation_intent_unapplied':'strikeout_annotation_quad',bbox:region,assessment,coverage});}
        }
      }
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
      const mid=e.bbox[1]+e.bbox[3]*0.5,lineY=r.bbox[1]+r.bbox[3]/2,widthRatio=r.bbox[2]/e.bbox[2];
      const connected=regions.some(v=>v.kind==='line'&&v.bbox[2]<0.002&&v.bbox[3]>0.02&&v.bbox[0]>=r.bbox[0]-0.003&&v.bbox[0]<=r.bbox[0]+r.bbox[2]+0.003&&lineY>=v.bbox[1]-0.003&&lineY<=v.bbox[1]+v.bbox[3]+0.003);
      if(!connected&&r.bbox[3]<=Math.max(0.002,e.bbox[3]*0.13)&&Math.abs(lineY-mid)<e.bbox[3]*0.22&&widthRatio>=0.8&&widthRatio<=1.15&&e.visibility==='visible'){e.visibility='struck_inferred';e.visibility_evidence.push({method:'flattened_non_grid_strike_candidate',bbox:r.bbox,assessment:'inferred',coverage:Math.min(1,widthRatio)});}
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

  if(state.mask||state.clip)gaps.push({feature:'pdf_visibility',reason:'clipping_or_soft_mask_visibility_not_fully_verified'});
  return{regions,gaps:[...new Map(gaps.map(g=>[g.reason,g])).values()]};
}
