import { OPS, Util } from 'pdfjs-dist/legacy/build/pdf.mjs';
import { box, type Box } from '../schema/index.js';
export interface PaintedGlyph {text:string;bbox:Box;order:number;hidden:boolean;reliable:boolean;run:number;color:string}
export function paintedGlyphs(page:any,viewport:any,operators:any):PaintedGlyph[]{
  let s={ctm:[1,0,0,1,0,0],tm:[1,0,0,1,0,0],lm:[1,0,0,1,0,0],x:0,size:12,font:'',char:0,word:0,hscale:1,rise:0,leading:0,mode:0,alpha:1,color:'#000000',clip:false,mask:false,blend:'Normal',optional:false};
  const stack:typeof s[]=[],glyphs:PaintedGlyph[]=[];
  const move=(x:number,y:number)=>{s.lm=[s.lm[0],s.lm[1],s.lm[2],s.lm[3],s.lm[4]+s.lm[0]*x+s.lm[2]*y,s.lm[5]+s.lm[1]*x+s.lm[3]*y];s.tm=[...s.lm];s.x=0;};
  for(let order=0;order<operators.fnArray.length;order++){
    const op=operators.fnArray[order],a=operators.argsArray[order];
    if(op===OPS.save){stack.push({...s,ctm:[...s.ctm],tm:[...s.tm],lm:[...s.lm]});continue;}
    if(op===OPS.restore){s=stack.pop()??s;continue;}
    if(op===OPS.transform){s.ctm=Util.transform(s.ctm,a);continue;}
    if(op===OPS.clip||op===OPS.eoClip){s.clip=true;continue;}
    if(op===OPS.setFillRGBColor){s.color=typeof a[0]==='string'?a[0]:'unknown';continue;}
    if(op===OPS.paintFormXObjectBegin){stack.push({...s,ctm:[...s.ctm],tm:[...s.tm],lm:[...s.lm]});if(a[0])s.ctm=Util.transform(s.ctm,a[0]);if(a[1])s.clip=true;continue;}
    if(op===OPS.paintFormXObjectEnd){s=stack.pop()??s;continue;}
    if(op===OPS.beginText){s.tm=[1,0,0,1,0,0];s.lm=[...s.tm];s.x=0;continue;}
    if(op===OPS.setTextMatrix){s.tm=Array.from(a.length===1?a[0]:a);s.lm=[...s.tm];s.x=0;continue;}
    if(op===OPS.setFont){s.font=a[0];s.size=a[1];continue;}
    if(op===OPS.setCharSpacing){s.char=a[0];continue;}
    if(op===OPS.setWordSpacing){s.word=a[0];continue;}
    if(op===OPS.setHScale){s.hscale=a[0]/100;continue;}
    if(op===OPS.setTextRise){s.rise=a[0];continue;}
    if(op===OPS.setLeading){s.leading=a[0];continue;}
    if(op===OPS.setTextRenderingMode){s.mode=a[0];continue;}
    if(op===OPS.setGState){for(const [key,value] of a[0]??[]){if(key==='ca')s.alpha=Number(value);if(key==='BM')s.blend=String(value);if(key==='SMask')s.mask=value!==false&&value!=='None';}continue;}
    if(op===OPS.beginGroup){stack.push({...s,ctm:[...s.ctm],tm:[...s.tm],lm:[...s.lm]});s.mask=true;continue;}
    if(op===OPS.endGroup){s=stack.pop()??s;continue;}
    if(op===OPS.beginMarkedContentProps&&a?.[0]==='OC'){s.optional=true;continue;}
    if(op===OPS.moveText||op===OPS.setLeadingMoveText){if(op===OPS.setLeadingMoveText)s.leading=-a[1];move(a[0],a[1]);continue;}
    if(op===OPS.nextLine){move(0,-s.leading);continue;}
    if(![OPS.showText,OPS.showSpacedText,OPS.nextLineShowText,OPS.nextLineSetSpacingShowText].includes(op))continue;
    if(op===OPS.nextLineShowText||op===OPS.nextLineSetSpacingShowText)move(0,-s.leading);
    let font:any;try{font=page.commonObjs.get(s.font);}catch{font=null;}
    const ascent=font?.ascent??0.8,descent=font?.descent??-0.2;
    const m=Util.transform(viewport.transform,Util.transform(s.ctm,s.tm));
    for(const glyph of (a??[]).flat(3)){
      if(typeof glyph==='number'){s.x-=glyph/1000*s.size;continue;}
      if(!glyph||typeof glyph.unicode!=='string')continue;
      const advance=Number(glyph.width??0)/1000*s.size,base=s.x*s.hscale,w=advance*s.hscale;
      const points=[[base,s.rise+descent*s.size],[base+w,s.rise+descent*s.size],[base,s.rise+ascent*s.size],[base+w,s.rise+ascent*s.size]].map(p=>{Util.applyTransform(p,m);return p;});
      const xs=points.map(p=>p[0]),ys=points.map(p=>p[1]);
      const bbox=box(Math.min(...xs)/viewport.width,Math.min(...ys)/viewport.height,(Math.max(...xs)-Math.min(...xs))/viewport.width,(Math.max(...ys)-Math.min(...ys))/viewport.height);
      glyphs.push({text:glyph.unicode,bbox,order,run:order,hidden:s.mode===3||s.mode===7||s.alpha===0,color:s.color,reliable:!!font&&Number.isFinite(ascent)&&Number.isFinite(descent)&&!font.vertical&&!s.clip&&!s.mask&&s.blend==='Normal'&&!s.optional});
      s.x+=advance+s.char+(glyph.isSpace?s.word:0);
    }
  }
  return glyphs;
}
