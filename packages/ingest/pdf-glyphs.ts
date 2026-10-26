import { transformedBounds,rectanglePath,intersectClip,insideClip,type Clip } from './pdf-geometry.js';
import { OPS, Util } from 'pdfjs-dist/legacy/build/pdf.mjs';
import { box, type Box } from '../schema/index.js';
import {pdfFontMetrics} from './pdf-text-geometry.js';
export interface PaintedGlyph {text:string;bbox:Box;order:number;hidden:boolean;nonpainting_mode:boolean;reliable:boolean;run:number;color:string;clip_ink?:Box;paint_ink?:Box;geometry_unverified?:boolean}
export const PDF_APPEARANCE_BUDGET_POLICY='bounded-page-document-appearance-v2';
// These budgets cover our analysis after PDF.js decoding. Visibility is withheld
// when any budget is exhausted; the original text observations remain intact.
export const PDF_APPEARANCE_LIMITS=Object.freeze({
  page:Object.freeze({work:8_000_000,glyphs:100_000,characters:500_000,regions:50_000,evidence:25_000}),
  // The calibrated 1,000-page case has 200 runs × 15 glyphs per page,
  // retaining 3M glyph spans. Keep explicit 4M output/glyph bounds and the
  // original 128M work bound; spatial admission avoids quadratic scanning.
  document:Object.freeze({work:128_000_000,glyphs:4_000_000,characters:10_000_000,regions:1_000_000,evidence:4_000_000}),
});
type AppearanceResource=keyof typeof PDF_APPEARANCE_LIMITS.page;
export class PdfAppearanceBudgetExceeded extends Error {}
export class PdfAppearanceDocumentBudget {
  private used={work:0,glyphs:0,characters:0,regions:0,evidence:0};
  page(){
    const used={work:0,glyphs:0,characters:0,regions:0,evidence:0};
    return (resource:AppearanceResource,amount=1)=>{
      if(!Number.isSafeInteger(amount)||amount<0||used[resource]+amount>PDF_APPEARANCE_LIMITS.page[resource]||this.used[resource]+amount>PDF_APPEARANCE_LIMITS.document[resource])throw new PdfAppearanceBudgetExceeded();
      used[resource]+=amount;this.used[resource]+=amount;
    };
  }
}
export type PdfAppearanceSpend=ReturnType<PdfAppearanceDocumentBudget['page']>;
const inkBounds=new WeakMap<object,Map<string,number[]|null>>();
function outlineBounds(font:any,objects:any,glyph:any):number[]|undefined{
  if(font.docverEmbeddedFontProgram!==true||font.missingFile||font.isType3Font||font.remeasure||font.isInvalidPDFjsFont||glyph.isInFont!==true||glyph.accent||typeof glyph.fontChar!=='string'||typeof font.getPathGenerator!=='function')return;
  let cache=inkBounds.get(font);if(!cache){cache=new Map();inkBounds.set(font,cache);}
  const known=cache.get(glyph.fontChar);if(known!==undefined)return known??undefined;
  if(cache.size>=4096)return;
  try{const path=font.getPathGenerator(objects,glyph.fontChar),b=path.computeTightBounds?.();
    if(Array.isArray(b)&&b.length===4&&b.every(Number.isFinite)&&b[2]>b[0]&&b[3]>b[1]){cache.set(glyph.fontChar,b);return b;}
  }catch{/* Missing/unsupported paths preserve uncertainty; never use an empty path as proof. */}
  cache.set(glyph.fontChar,null);
}
export const supportedGraphicsStateKey=(key:string)=>['LW','LC','LJ','ML','D','RI','FL','ca','CA','BM','SMask'].includes(key);
export function nativePixelMargins(viewport:any):[number,number]{
  const pixel=Math.max(72/300*(viewport.scale??1)*Math.max(1,viewport.userUnit??1),Math.max(viewport.width,viewport.height)/4096);
  return [pixel/viewport.width,pixel/viewport.height];
}
export function paintedGlyphs(page:any,viewport:any,operators:any,fontStyles:Record<string,any>={},spend:PdfAppearanceSpend=new PdfAppearanceDocumentBudget().page()):PaintedGlyph[]{
  let s={ctm:[1,0,0,1,0,0],tm:[1,0,0,1,0,0],lm:[1,0,0,1,0,0],x:0,size:12,font:'',char:0,word:0,hscale:1,rise:0,leading:0,mode:0,textClipPending:false,alpha:1,strokeAlpha:1,color:'#000000',clip:null as Clip,pendingClip:false,mask:false,blend:'Normal',unsupportedState:false};
  const stack:typeof s[]=[],glyphs:PaintedGlyph[]=[],marked:boolean[]=[];let optional=false;
  const move=(x:number,y:number)=>{s.lm=[s.lm[0],s.lm[1],s.lm[2],s.lm[3],s.lm[4]+s.lm[0]*x+s.lm[2]*y,s.lm[5]+s.lm[1]*x+s.lm[3]*y];s.tm=[...s.lm];s.x=0;};
  for(let order=0;order<operators.fnArray.length;order++){
    spend('work');
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
    if(op===OPS.setGState){spend('work',a[0]?.length??0);for(const [key,value] of a[0]??[]){if(!supportedGraphicsStateKey(key))s.unsupportedState=true;if(key==='ca')s.alpha=Number(value);if(key==='CA')s.strokeAlpha=Number(value);if(key==='BM')s.blend=['source-over','Normal','Compatible'].includes(String(value))?'Normal':String(value);if(key==='SMask')s.mask=value!==false&&value!=='None';}continue;}
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
    // textContent omits fonts used exclusively by whitespace. Use the same
    // actual worker metrics for those fonts; never estimate a painted extent.
    const metrics=fontStyles[s.font]??font?.docverFontMetrics??font;
    const {ascent,descent,known:metricsKnown}=pdfFontMetrics(metrics);
    // PDF.js 6.4 CanvasGraphics.setFont and text extraction both use
    // FONT_IDENTITY_MATRIX when the serialized fontMatrix is absent.
    // Match that renderer default; reject malformed or nonstandard matrices.
    const identity=[0.001,0,0,0.001,0,0],matrix=font?.fontMatrix??identity;
    const standardMatrix=Array.isArray(matrix)&&matrix.length===6&&matrix.every((v:number,i:number)=>Number.isFinite(v)&&Math.abs(v-identity[i])<0.000001);
    const m=Util.transform(viewport.transform,Util.transform(s.ctm,s.tm));
    // Iterate without flat(3), which allocated the complete attacker-controlled
    // operand expansion before any glyph limit could be applied.
    function* operands(values:any,depth=3):Generator<any>{
      if(!Array.isArray(values))return;
      for(const value of values){spend('work');if(Array.isArray(value)&&depth>0)yield*operands(value,depth-1);else yield value;}
    }
    for(const glyph of operands(glyphArgs??[])){
      if(typeof glyph==='number'){s.x-=glyph/1000*s.size;continue;}
      if(!glyph||typeof glyph.unicode!=='string')continue;
      spend('glyphs');spend('characters',glyph.unicode.length);
      const advance=Number(glyph.width??0)/1000*s.size,base=s.x*s.hscale,w=advance*s.hscale;
      const points=[[base,s.rise+descent*s.size],[base+w,s.rise+descent*s.size],[base,s.rise+ascent*s.size],[base+w,s.rise+ascent*s.size]].map(p=>{Util.applyTransform(p,m);return p;});
      const xs=points.map(p=>p[0]),ys=points.map(p=>p[1]);
      const finite=xs.concat(ys).every(Number.isFinite),bbox=finite?box(Math.min(...xs)/viewport.width,Math.min(...ys)/viewport.height,(Math.max(...xs)-Math.min(...xs))/viewport.width,(Math.max(...ys)-Math.min(...ys))/viewport.height):box(0,0,0,0);
      const nonpaintingMode=!!font&&!font.isType3Font&&!s.unsupportedState&&(s.mode===3||s.mode===7);
      const hidden=nonpaintingMode||!!font&&!font.isType3Font&&!s.unsupportedState&&(([0,4].includes(s.mode)&&s.alpha===0)||([2,6].includes(s.mode)&&s.alpha===0&&s.strokeAlpha===0));
      let clipOK=insideClip(s.clip,bbox),clipInk:Box|undefined,paintInk:Box|undefined;
      // Metric ascenders/descenders are not painted ink. A known rectangular
      // clip may cut that empty margin while preserving the complete outline.
      // Use the loaded PDF.js glyph path, never a larger clip or a percent epsilon.
      const determinant=m[0]*m[3]-m[1]*m[2];
      if(metricsKnown&&standardMatrix&&font&&!font.vertical&&s.mode===0&&s.size>0&&s.hscale>0&&Number.isFinite(determinant)&&determinant!==0){
        const ink=outlineBounds(font,page.commonObjs,glyph);
        if(ink){const corners=[[ink[0],ink[1]],[ink[2],ink[1]],[ink[0],ink[3]],[ink[2],ink[3]]].map(([x,y])=>{const p=[base+x*s.size*s.hscale,s.rise+y*s.size];Util.applyTransform(p,m);return p;});
          const xx=corners.map(p=>p[0]/viewport.width),yy=corners.map(p=>p[1]/viewport.height);
          if(xx.concat(yy).every(n=>Number.isFinite(n)&&n>=0&&n<=1)){
            const candidate=box(Math.min(...xx),Math.min(...yy),Math.max(...xx)-Math.min(...xx),Math.max(...yy)-Math.min(...yy));
            if(candidate[2]>0&&candidate[3]>0)paintInk=candidate;
            // The existing metric-box check has a compatibility tolerance.
            // A complete-outline proof must not inherit any expanded clip.
            // Only document-embedded font programs qualify. Require an inward
            // native-pixel clearance as well; boundary contact cannot prove ink.
            // PDFKit cropBox thumbnails on the tested host ignore UserUnit,
            // while PDF.js scales its viewport. Never shrink native clearance
            // on either renderer interpretation, including UserUnit below1.
            const [px,py]=nativePixelMargins(viewport);
            if(!clipOK&&Array.isArray(s.clip)&&candidate[2]>0&&candidate[3]>0&&candidate[0]>=s.clip[0]+px&&candidate[1]>=s.clip[1]+py&&candidate[0]+candidate[2]<=s.clip[0]+s.clip[2]-px&&candidate[1]+candidate[3]<=s.clip[1]+s.clip[3]-py){clipOK=true;clipInk=candidate;}
          }
        }
      }
      glyphs.push({text:glyph.unicode,bbox,order,run:order,hidden,nonpainting_mode:nonpaintingMode,color:s.color,...(!metricsKnown||!finite||font?.isType3Font||!standardMatrix?{geometry_unverified:true}:{}),...(clipInk?{clip_ink:clipInk}:{}),...(paintInk?{paint_ink:paintInk}:{}),reliable:finite&&(s.alpha>=0.999||hidden)&&s.color!=='unknown'&&!!font&&!font.isType3Font&&(s.mode===0||s.mode===3)&&metricsKnown&&standardMatrix&&Number.isFinite(ascent)&&Number.isFinite(descent)&&!font.vertical&&clipOK&&!s.pendingClip&&!s.mask&&!s.unsupportedState&&s.blend==='Normal'&&!optional});
      s.x+=advance+s.char+(glyph.isSpace?s.word:0);
    }
  }
  return glyphs;
}
