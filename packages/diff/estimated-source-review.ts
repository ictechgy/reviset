import {normalize,type ElementData} from '../schema/index.js';
import {isEstimatedPdfSource} from '../ingest/pdf-text-geometry.js';
import {numericSlots,numericPattern,numericNotationSupported} from '../ingest/numeric-slots.js';
const compact=(text:string)=>normalize(text).replace(/\s/gu,'').toLowerCase();
const context=(text:string)=>compact(numericPattern(text)).replace(/#\/#/gu,'#');
const intersects=(a:ElementData,b:ElementData)=>Math.min(a.bbox[0]+a.bbox[2],b.bbox[0]+b.bbox[2])>Math.max(a.bbox[0],b.bbox[0])&&Math.min(a.bbox[1]+a.bbox[3],b.bbox[1]+b.bbox[3])>Math.max(a.bbox[1],b.bbox[1]);

// Estimated boxes can raise a review warning or withhold an edit. They never
// establish source coverage or clear the source's unresolved geometry.
export function reviewEstimatedSource(ocr:ElementData,elements:ElementData[]){
  const runs=elements.filter(e=>isEstimatedPdfSource(e)&&intersects(e,ocr)).sort((a,b)=>a.reading_order-b.reading_order);
  if(runs.length>256||runs.reduce((n,e)=>n+e.text.length,0)>16384)return {runs:runs.slice(0,32),disagrees:true,numericConflict:false,budgetExceeded:true};
  const joined=runs.map(e=>e.text).join(''),spaced=runs.map(e=>e.text).join(' '),candidates=[...runs.map(e=>e.text),joined,spaced],values=numericSlots(ocr.text),pattern=context(ocr.text);
  const numericConflict=values.length===1&&candidates.some(text=>numericNotationSupported(text)&&context(text)===pattern&&numericSlots(text).length===1&&numericSlots(text)[0]!==values[0]);
  return {runs,disagrees:runs.length>0&&compact(joined)!==compact(ocr.text),numericConflict,budgetExceeded:false};
}
