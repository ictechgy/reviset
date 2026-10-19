import {normalize} from '../schema/index.js';
// Keep numeric slot boundaries aligned with Vision.swift. Complete fractions
// are one slot; mixed integer + vulgar fraction stays two. Units remain literal
// in the masked pattern so an inferred amount cannot silently change its unit.
const token=/(?:(?<![\p{L}\p{N}])[+＋−-]\s*)?(?:[0-9０-９]+\s*[/⁄／]\s*[0-9０-９]+|[¼½¾⅐⅑⅒⅓⅔⅕⅖⅗⅘⅙⅚⅛⅜⅝⅞↉]|[0-9０-９]+(?:[.,，．][0-9０-９]+)*)/gu;
function tokens(text:string){return Array.from(text.matchAll(token),m=>{const value=m[0].normalize('NFKC').replace(/−/gu,'-').replace(/⁄/gu,'/').replace(/\s/gu,'');return {value,kind:value.includes('/')?'fraction':'decimal',start:m.index,end:m.index+m[0].length};});}
export const numericSlots=(text:string)=>tokens(text).map(t=>t.value);
export function numericNotationSupported(text:string):boolean{
  if(/(?=\p{N})[^0-9０-９]/u.test(text.replace(/[¼½¾⅐⅑⅒⅓⅔⅕⅖⅗⅘⅙⅚⅛⅜⅝⅞↉]/gu,'')))return false;
  if(!/[/⁄／]/u.test(text))return true;
  const values=tokens(text);let next=0;
  for(const match of text.matchAll(/[/⁄／]/gu)){
    while(next<values.length&&values[next].end<=match.index)next++;
    if(match.index>0&&match.index+1<text.length&&/\s/u.test(text[match.index-1])&&/\s/u.test(text[match.index+1])&&next>0&&next<values.length&&values[next].start>match.index&&/^[\p{L}\p{Sc}%％\s]*$/u.test(text.slice(values[next-1].end,match.index))&&/^\s*$/u.test(text.slice(match.index+1,values[next].start)))continue;
    let before=match.index-1,after=match.index+1;
    while(before>=0&&/\s/u.test(text[before]))before--;
    while(after<text.length&&/\s/u.test(text[after]))after++;
    const low=before>=0?text.charCodeAt(before):0,left=before>=0?text.slice(before-(low>=0xdc00&&low<=0xdfff?1:0),before+1):undefined,right=after<text.length?String.fromCodePoint(text.codePointAt(after)!):undefined,digit=(c:string|undefined)=>!!c&&/^[0-9０-９]$/u.test(c);
    if(digit(right)&&!digit(left))return false;
    if(left&&/^\p{N}$/u.test(left)&&(!right||!/[\p{L}\p{N}]/u.test(right)))return false;
  }
  return true;
}
export const numericShape=(text:string)=>numericNotationSupported(text)?tokens(text).map(t=>t.kind).join(','):null;
export function numericPattern(text:string):string{
  let result='',end=0;
  for(const t of tokens(text)){result+=text.slice(end,t.start)+(t.kind==='fraction'?'#/#':'#');end=t.end;}
  return normalize(result+text.slice(end));
}
