import { transformedBounds,rectanglePath,intersectClip,insideClip,type Clip } from './pdf-geometry.js';
import { OPS, Util } from 'pdfjs-dist/legacy/build/pdf.mjs';
import { box, type Box } from '../schema/index.js';
export interface PaintedGlyph {text:string;bbox:Box;order:number;hidden:boolean;reliable:boolean;run:number;color:string}
export function paintedGlyphs(page:any,viewport:any,operators:any,fontStyles:Record<string,any>={}):PaintedGlyph[]{
  let s={ctm:[1,0,0,1,0,0],tm:[1,0,0,1,0,0],lm:[1,0,0,1,0,0],x:0,size:12,font:'',char:0,word:0,hscale:1,rise:0,leading:0,mode:0,textClipPending:false,alpha:1,strokeAlpha:1,color:'#000000',clip:null as Clip,pendingClip:false,mask:false,blend:'Normal'};
  const stack:typeof s[]=[],glyphs:PaintedGlyph[]=[],marked:boolean[]=[];let optional=false;
  const move=(x:number,y:number)=>{s.lm=[s.lm[0],s.lm[1],s.lm[2],s.lm[3],s.lm[4]+s.lm[0]*x+s.lm[2]*y,s.lm[5]+s.lm[1]*x+s.lm[3]*y];s.tm=[...s.lm];s.x=0;};
  for(let order=0;order<operators.fnArray.length;order++){
    const op=operators.fnArray[order],a=operators.argsArray[order];
    if(op===OPS.save){stack.push({...s,ctm:[...s.ctm],tm:[...s.tm],lm:[...s.lm]});continue;}
    if(op===OPS.restore){s=stack.pop()??s;continue;}
    if(op===OPS.transform){s.ctm=Util.transform(s.ctm,a);continue;}
    if(op===OPS.clip||op===OPS.eoClip){s.pendingClip=true;continue;}
    if(op===OPS.constructPath&&s.pendingClip){const r=a?.[2],b=r?transformedBounds(Array.from(r),s.ctm,viewport):null;s.clip=intersectClip(s.clip,b&&b.axisAligned&&rectanglePath(a[1])?b.bbox:'unknown');s.pendingClip=false;continue;}
    if([OPS.setFillGray,OPS.setFillCMYKColor,OPS.setFillColor,OPS.setFillColorN].includes(op)){s.color='unknown';continue;}
    if(op===OPS.setFillRGBColor){s.color=typeof a[0]==='string'?a[0]:'unknown';continue;}
    if(op===OPS.paintFormXObjectBegin){stack.push({...s,ctm:[...s.ctm],tm:[...s.tm],lm:[...s.lm]});if(a[0])s.ctm=Util.transform(s.ctm,a[0]);if(a[1]){const b=transformedBounds(Array.from(a[1]),s.ctm,viewport);s.clip=intersectClip(s.clip,b.axisAligned?b.bbox:'unknown');}continue;}
    if(op===OPS.paintFormXObjectEnd){s=stack.pop()??s;continue;}
    if(op===OPS.endText&&s.textClipPending){s.clip='unknown';s.textClipPending=false;continue;}
    if(op===OPS.beginText){s.tm=[1,0,0,1,0,0];s.lm=[...s.tm];s.x=0;continue;}
    if(op===OPS.setTextMatrix){s.tm=Array.from(a.length===1?a[0]:a);s.lm=[...s.tm];s.x=0;continue;}
    if(op===OPS.setFont){s.font=a[0];s.size=a[1];continue;}
    if(op===OPS.setCharSpacing){s.char=a[0];continue;}
    if(op===OPS.setWordSpacing){s.word=a[0];continue;}
    if(op===OPS.setHScale){s.hscale=a[0]/100;continue;}
    if(op===OPS.setTextRise){s.rise=a[0];continue;}
    if(op===OPS.setLeading){s.leading=a[0];continue;}
    if(op===OPS.setTextRenderingMode){s.mode=a[0];continue;}
    if(op===OPS.setGState){for(const [key,value] of a[0]??[]){if(key==='ca')s.alpha=Number(value);if(key==='CA')s.strokeAlpha=Number(value);if(key==='BM')s.blend=['source-over','Normal','Compatible'].includes(String(value))?'Normal':String(value);if(key==='SMask')s.mask=value!==false&&value!=='None';}continue;}
    if(op===OPS.beginGroup){stack.push({...s,ctm:[...s.ctm],tm:[...s.tm],lm:[...s.lm]});s.mask=true;continue;}
    if(op===OPS.endGroup){s=stack.pop()??s;continue;}
    if(op===OPS.beginMarkedContent||op===OPS.beginMarkedContentProps){marked.push(optional);if(a?.[0]==='OC')optional=true;continue;}
    if(op===OPS.endMarkedContent){optional=marked.pop()??false;continue;}
    if(op===OPS.moveText||op===OPS.setLeadingMoveText){if(op===OPS.setLeadingMoveText)s.leading=-a[1];move(a[0],a[1]);continue;}
    if(op===OPS.nextLine){move(0,-s.leading);continue;}
    if(![OPS.showText,OPS.showSpacedText,OPS.nextLineShowText,OPS.nextLineSetSpacingShowText].includes(op))continue;
    if(s.mode>=4)s.textClipPending=true;
    if(op===OPS.nextLineShowText||op===OPS.nextLineSetSpacingShowText)move(0,-s.leading);
    if(op===OPS.nextLineSetSpacingShowText){s.word=Number(a[0]);s.char=Number(a[1]);}
    const glyphArgs=op===OPS.nextLineSetSpacingShowText?a[2]:a[0];
    let font:any;try{font=page.commonObjs.get(s.font);}catch{font=null;}
    const metrics=fontStyles[s.font]??font;
    const ascent=metrics?.ascent??0.8,descent=metrics?.descent??-0.2,metricsKnown=Number.isFinite(metrics?.ascent)&&Number.isFinite(metrics?.descent);
    const standardMatrix=!font?.fontMatrix||font.fontMatrix.every((v:number,i:number)=>Math.abs(v-([0.001,0,0,0.001,0,0][i]??NaN))<0.000001);
    const m=Util.transform(viewport.transform,Util.transform(s.ctm,s.tm));
    for(const glyph of (glyphArgs??[]).flat(3)){
      if(typeof glyph==='number'){s.x-=glyph/1000*s.size;continue;}
      if(!glyph||typeof glyph.unicode!=='string')continue;
      const advance=Number(glyph.width??0)/1000*s.size,base=s.x*s.hscale,w=advance*s.hscale;
      const points=[[base,s.rise+descent*s.size],[base+w,s.rise+descent*s.size],[base,s.rise+ascent*s.size],[base+w,s.rise+ascent*s.size]].map(p=>{Util.applyTransform(p,m);return p;});
      const xs=points.map(p=>p[0]),ys=points.map(p=>p[1]);
      const bbox=box(Math.min(...xs)/viewport.width,Math.min(...ys)/viewport.height,(Math.max(...xs)-Math.min(...xs))/viewport.width,(Math.max(...ys)-Math.min(...ys))/viewport.height);
      const hidden=s.mode===3||s.mode===7||([0,4].includes(s.mode)&&s.alpha===0)||([2,6].includes(s.mode)&&s.alpha===0&&s.strokeAlpha===0);
      glyphs.push({text:glyph.unicode,bbox,order,run:order,hidden,color:s.color,reliable:(s.alpha>=0.999||hidden)&&s.color!=='unknown'&&!!font&&!font.isType3Font&&(s.mode===0||s.mode===3)&&metricsKnown&&standardMatrix&&Number.isFinite(ascent)&&Number.isFinite(descent)&&!font.vertical&&insideClip(s.clip,bbox)&&!s.pendingClip&&!s.mask&&s.blend==='Normal'&&!optional});
      s.x+=advance+s.char+(glyph.isSpace?s.word:0);
    }
  }
  return glyphs;
}
