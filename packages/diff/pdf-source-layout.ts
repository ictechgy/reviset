import {type Box,type ElementData,type PageData,comparisonRegions} from '../schema/index.js';
import {rowOrderedRegions} from '../ingest/reading-order.js';
import {hasUnverifiedPdfGeometry} from '../ingest/pdf-text-geometry.js';
import {annotationBlocksRegion} from '../ingest/pdf-annotation-regions.js';

export const PDF_SOURCE_LAYOUT_POLICY='observed-glyph-run-boundaries-v1';
const MAX_GLYPHS=32_768,MAX_RUNS=2_048;
type Unit={text:string;bbox:Box;run:ElementData;index:number;spaceBefore:boolean;spaceAfter:boolean};
type Boundary='space'|'joined'|'row'|'unknown';

// This is a comparison annex, never a replacement text layer. Source strings,
// run identities, punctuation and explicit in-run word boundaries stay intact.
// OCR, estimated geometry and any uncertain appearance cannot prove equality.
function units(page:PageData):Unit[]|undefined {
  if(page.capabilities.text!=='available'||page.source_transform.length!==6||page.source_transform[0]<=0||page.source_transform[3]>=0||page.source_transform[1]!==0||page.source_transform[2]!==0)return;
  const runs=page.comparison_basis==='hybrid_regions_v1'?comparisonRegions(page):page.elements.filter(e=>e.kind==='text'&&e.method==='pdf_text');
  if(!runs.length||runs.length>MAX_RUNS||page.comparison_basis==='raster_ocr')return;
  const result:Unit[]=[];let size=0;
  for(const run of runs){
    if(run.comparison_role==='unresolved'||run.provenance!=='observed'||run.method!=='pdf_text'||run.availability!=='available'||run.visibility!=='visible'||hasUnverifiedPdfGeometry(run)||annotationBlocksRegion(page.elements,run.bbox))return;
    size+=run.text.length;if(size>MAX_GLYPHS)return;
    if(/[\u0590-\u08ff\u200e\u200f\u202a-\u202e\u2066-\u2069\ufb1d-\ufdff\ufe70-\ufeff\u{10800}-\u{10fff}\u{1e800}-\u{1eeff}]/u.test(run.text))return;
    const spans=run.visibility_spans;if(!spans?.length||spans.length>MAX_GLYPHS-result.length)return;
    const characters:{text:string;spaceBefore:boolean;spaceAfter:boolean}[]=[];let space=false;
    for(const text of run.text.normalize('NFC')){
      if(/\s/u.test(text)){space=true;if(characters.length)characters.at(-1)!.spaceAfter=true;continue;}
      characters.push({text,spaceBefore:space,spaceAfter:false});space=false;
    }
    if(characters.length!==spans.length)return;
    for(let i=0;i<spans.length;i++){
      const span=spans[i],character=characters[i];
      if(span.state!=='visible'||span.text.normalize('NFC')!==character.text||span.bbox[2]<=0||span.bbox[3]<=0)return;
      // Vertical/RTL/rotated runs and multiline correlations require their own
      // ordering proof. Do not guess an equivalent logical sequence for them.
      const previous=spans[i-1],first=spans[0];
      if(previous&&(span.bbox[0]+span.bbox[2]/2<previous.bbox[0]+previous.bbox[2]/2||Math.abs(span.bbox[1]+span.bbox[3]/2-first.bbox[1]-first.bbox[3]/2)>Math.min(span.bbox[3],first.bbox[3])*.5))return;
      result.push({...character,bbox:span.bbox,run,index:i});
    }
  }
  const ordered=rowOrderedRegions(result);
  for(let i=1;i<ordered.length;i++){
    const a=ordered[i-1].bbox,b=ordered[i].bbox;
    const overlap=Math.max(0,Math.min(a[0]+a[2],b[0]+b[2])-Math.max(a[0],b[0]))*Math.max(0,Math.min(a[1]+a[3],b[1]+b[3])-Math.max(a[1],b[1]));
    if(overlap>Math.min(a[2]*a[3],b[2]*b[3])*.25)return;
  }
  return ordered;
}

function boundary(a:Unit,b:Unit):Boundary {
  if(a.run===b.run&&b.index===a.index+1)return b.spaceBefore?'space':'joined';
  const [x,y,w,h]=a.bbox,[u,v,s,t]=b.bbox;
  if(v+t/2>y+h/2+Math.max(h,t)*.5)return 'row';
  if(a.spaceAfter||b.spaceBefore)return 'space';
  // A source run boundary is not a word separator. Only near-touching glyph
  // advances prove a join; a clear horizontal gap proves a space. The band in
  // between, a line wrap, or overlapping ordering stays unsupported.
  if(Math.abs(y+h/2-v-t/2)>Math.min(h,t)*.5||u+s/2<=x+w/2)return 'unknown';
  const gap=u-x-w,small=Math.min(w,s);
  if(gap<=Math.max(.0002,small*.08))return 'joined';
  if(gap>=Math.max(.0006,small*.3))return 'space';
  return 'unknown';
}

export function equivalentPdfSourceLayout(a:PageData,b:PageData):boolean {
  if(Math.abs((a.width/a.height)/(b.width/b.height)-1)>.003)return false;
  const left=units(a),right=units(b);
  if(!left?.length||!right||left.length!==right.length)return false;
  for(let i=0;i<left.length;i++){
    const x=left[i],y=right[i];if(x.text!==y.text)return false;
    // Reordered paint commands are harmless only when the corresponding glyph
    // still occupies the same local line. This is not a bag-of-words test and
    // cannot erase row/value swaps or distant repeated content.
    const centerX=Math.abs(x.bbox[0]+x.bbox[2]/2-y.bbox[0]-y.bbox[2]/2),centerY=Math.abs(x.bbox[1]+x.bbox[3]/2-y.bbox[1]-y.bbox[3]/2);
    if(centerX>Math.max(x.bbox[3],y.bbox[3])*1.5||centerY>Math.min(x.bbox[3],y.bbox[3])*.6)return false;
    if(i){const l=boundary(left[i-1],x),r=boundary(right[i-1],y);if(l==='unknown'||r==='unknown'||l!==r)return false;}
  }
  return true;
}
