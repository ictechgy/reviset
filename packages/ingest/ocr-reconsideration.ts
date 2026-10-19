import {OcrReconsideration,hash,type OcrReconsiderationData,type ElementData,type Box} from '../schema/index.js';

const compact=(s:string)=>s.normalize('NFC').replace(/\s/gu,'');
const contains=(a:Box,b:Box)=>b[0]>=a[0]-1e-9&&b[1]>=a[1]-1e-9&&b[0]+b[2]<=a[0]+a[2]+1e-9&&b[1]+b[3]<=a[1]+a[3]+1e-9;
const sameBox=(a:Box,b:Box)=>a.every((n,i)=>Math.abs(n-b[i])<1e-9);
function iou(a:Box,b:Box){const area=Math.max(0,Math.min(a[0]+a[2],b[0]+b[2])-Math.max(a[0],b[0]))*Math.max(0,Math.min(a[1]+a[3],b[1]+b[3])-Math.max(a[1],b[1]));return area/(a[2]*a[3]+b[2]*b[3]-area);}
// Recover altered scalars, not a set difference: unchanged l/I/O characters
// must not veto an unrelated correction elsewhere in a word.
function altered(a:string,b:string):{changes:string[];cost:number;deleted:{index:number;text:string}[]}{
  const x=Array.from(compact(a)),y=Array.from(compact(b)),cost=Array.from({length:x.length+1},()=>new Uint16Array(y.length+1));
  for(let i=0;i<=x.length;i++)cost[i][0]=i;for(let j=0;j<=y.length;j++)cost[0][j]=j;
  for(let i=1;i<=x.length;i++)for(let j=1;j<=y.length;j++)cost[i][j]=Math.min(cost[i-1][j]+1,cost[i][j-1]+1,cost[i-1][j-1]+Number(x[i-1]!==y[j-1]));
  const changes:string[]=[],deleted:{index:number;text:string}[]=[];let i=x.length,j=y.length;
  while(i||j){if(i&&j&&cost[i][j]===cost[i-1][j-1]+Number(x[i-1]!==y[j-1])){if(x[i-1]!==y[j-1])changes.push(x[i-1],y[j-1]);i--;j--;}else if(i&&cost[i][j]===cost[i-1][j]+1){changes.push(x[--i]);deleted.push({index:i,text:x[i]});}else changes.push(y[--j]);}
  return {changes,cost:cost[x.length][y.length],deleted};
}
export type ReconsideredReading={text:string;confidence:number;bbox:Box;alternatives:{text:string;confidence:number;truncated:boolean}[]};
// This is correlated Vision evidence, never a calibrated probability or source
// visibility proof. Numeric and punctuation/confusable edits remain withheld.
export function admitReconsideration(primary:ElementData,input:OcrReconsiderationData,blocked:(bbox:Box)=>boolean):ReconsideredReading|undefined{
  const parsed=OcrReconsideration.safeParse(input);if(!parsed.success)return;
  const data=parsed.data,ocr=primary.ocr;
  if(primary.method!=='vision_ocr'||primary.provenance!=='inferred'||primary.availability!=='available'||!ocr||!ocr.numeric_consensus||ocr.strike_status!=='not_detected'||primary.text.length>128||/[\p{N}]/u.test(primary.text)||!['visible','uncertain'].includes(primary.visibility??'')||!(ocr.confidence<.5||ocr.ambiguous))return;
  if(data.status!=='available'||!sameBox(data.band_bbox,primary.bbox)||!data.ink_pixels||data.threshold===undefined||blocked(primary.bbox)||data.contexts.length!==8)return;
  const hangul=(primary.text.match(/[\p{Script=Hangul}]/gu)??[]).length,latin=(primary.text.match(/[A-Za-z]/gu)??[]).length,mono=hangul>latin?'ko-KR':'en-US';
  const seen=new Set<string>(),readings:ReconsideredReading[]=[];
  for(const context of data.contexts){
    const languages=context.languages.join(','),key=[context.padding,context.scale,languages].join(':');
    if(seen.has(key)||![mono,'ko-KR,en-US'].includes(languages)||context.status!=='available'||context.observations.length!==1||!contains(context.crop_bbox,data.band_bbox)||blocked(context.crop_bbox))return;
    seen.add(key);const reading=context.observations[0];
    if(reading.confidence<.5||reading.ink_coverage!==1||!reading.token_bboxes.length||!reading.token_bboxes.every(b=>contains(context.crop_bbox,b))||!contains(context.crop_bbox,reading.bbox)||iou(primary.bbox,reading.bbox)<.5||/[\p{N}]/u.test(reading.text)||reading.alternatives.some(a=>compact(a.text)!==compact(reading.text)&&a.confidence>=reading.confidence-.15))return;
    readings.push({text:reading.text,confidence:reading.confidence,bbox:reading.bbox,alternatives:reading.alternatives.map(a=>({...a,truncated:false}))});
  }
  // Eight unique keys drawn from exactly 2 paddings x2 scales x2 language sets.
  const first=readings[0];if(readings.some(r=>compact(r.text)!==compact(first.text))||compact(first.text)===compact(primary.text))return;
  if(primary.text.trim().split(/\s+/u).length!==first.text.trim().split(/\s+/u).length)return;
  const {changes,cost,deleted}=altered(primary.text,first.text);if(cost>1)return;
  if(deleted.length){
    if(primary.text!==primary.text.normalize('NFC'))return;
    const map:{offset:number;text:string}[]=[];let offset=0;
    for(const c of primary.text){if(!/\s/u.test(c))map.push({offset,text:c});offset+=c.length;}
    for(const d of deleted){const scalar=map[d.index];if(!scalar||scalar.text!==d.text||!data.primary_empty_characters?.some(e=>e.offset===scalar.offset&&e.text===scalar.text&&e.ink_pixels===0&&e.bbox[2]>0&&e.bbox[3]>0&&e.bbox[2]<=primary.bbox[2]&&e.bbox[3]<=2*primary.bbox[3]&&e.bbox[0]+e.bbox[2]/2>=primary.bbox[0]&&e.bbox[0]+e.bbox[2]/2<=primary.bbox[0]+primary.bbox[2]&&e.bbox[1]+e.bbox[3]/2>=primary.bbox[1]&&e.bbox[1]+e.bbox[3]/2<=primary.bbox[1]+primary.bbox[3]))return;}
  }
  if(!changes.length||changes.some(c=>/[0Oo1Il|5S8B·•∙・‧ㆍ]/u.test(c)||!/[\p{Script=Latin}\p{Script=Hangul}]/u.test(c)))return;
  return {...first,bbox:primary.bbox,confidence:Math.min(...readings.map(r=>r.confidence))};
}
export function matchesReconsiderationPrimary(derived:ElementData,primary:ElementData):boolean{
  const r=derived.ocr?.reconsideration;
  return !!r&&primary.source_ref===r.primary_source_ref&&primary.text===r.primary_text&&primary.ocr?.confidence===r.primary_confidence&&sameBox(primary.bbox,r.primary_bbox)&&!primary.ocr?.reconsideration&&!!primary.ocr?.reconsideration_observation&&hash(primary.ocr.reconsideration_observation)===hash(r.observation);
}
