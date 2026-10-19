import {normalize} from '../schema/index.js';
// Keep numeric slot boundaries aligned with Vision.swift. Complete fractions
// are one slot; mixed integer + vulgar fraction stays two. Units remain literal
// in the masked pattern so an inferred amount cannot silently change its unit.
const token=/(?:(?<![\p{L}\p{N}])[+＋−－-]\p{White_Space}*)?(?:[0-9０-９]+\p{White_Space}*[/⁄／]\p{White_Space}*[0-9０-９]+|[¼½¾⅐⅑⅒⅓⅔⅕⅖⅗⅘⅙⅚⅛⅜⅝⅞↉]|[0-9０-９]+(?:[.,，．][0-9０-９]+)*)/gu;
function tokens(text:string){return Array.from(text.matchAll(token),m=>{const value=m[0].normalize('NFKC').replace(/−/gu,'-').replace(/⁄/gu,'/').replace(/\p{White_Space}/gu,'');return {value,kind:value.includes('/')?'fraction':'decimal',start:m.index,end:m.index+m[0].length};});}
export const numericSlots=(text:string)=>tokens(text).map(t=>t.value);
export function numericNotationSupported(text:string):boolean{
  if(/(?=\p{N})[^0-9０-９]/u.test(text.replace(/[¼½¾⅐⅑⅒⅓⅔⅕⅖⅗⅘⅙⅚⅛⅜⅝⅞↉]/gu,'')))return false;
  // Default-ignorable scalars (including invisible letters), numeric combining marks and unsupported slash glyphs
  // cannot be verified as a different collection of independent digit slots.
  if(/\p{N}/u.test(text)&&(/\p{Default_Ignorable_Code_Point}|(?=\p{Cc})[^\p{White_Space}]|[∕⧸╱⟋]/u.test(text)||/[\p{N}/⁄／]\p{M}|\p{M}[/⁄／\p{N}]/u.test(text)))return false;
  if(!/[/⁄／]/u.test(text))return true;
  const values=tokens(text),dates=Array.from(text.matchAll(/(?<![0-9０-９.,，．/⁄／])[0-9０-９]{1,4}\p{White_Space}*[/⁄／]\p{White_Space}*[0-9０-９]{1,2}\p{White_Space}*[/⁄／]\p{White_Space}*[0-9０-９]{1,4}(?![0-9０-９.,，．/⁄／])/gu),m=>({start:m.index,end:m.index+m[0].length}));
  let next=0,date=0;
  for(const match of text.matchAll(/[/⁄／]/gu)){
    const at=match.index;
    while(next<values.length&&values[next].end<=at)next++;
    while(date<dates.length&&dates[date].end<=at)date++;
    // A slash must belong to a complete fraction/date token, an explicit
    // spaced list delimiter, or a literal unit/text expression. No repair.
    if(next<values.length&&values[next].start<at&&at<values[next].end&&values[next].kind==='fraction')continue;
    if(date<dates.length&&dates[date].start<at&&at<dates[date].end)continue;
    const left=next>0?text.slice(values[next-1].end,at):null,right=next<values.length?text.slice(at+1,values[next].start):null;
    if(at>0&&/\p{White_Space}/u.test(text[at-1])&&/\p{White_Space}/u.test(text[at+1]??'')&&left!==null&&right!==null&&/^[\p{L}\p{Sc}%％\p{White_Space}]*$/u.test(left)&&/^[\p{White_Space}\p{Sc}]*$/u.test(right))continue;
    const numericLeft=left!==null&&(/^[\p{L}\p{Sc}%％\p{White_Space}+＋−.,，．-]*$/u.test(left)||!/\p{L}/u.test(left)),numericRight=right!==null&&!/\p{L}/u.test(right);
    // Labels such as1/day and100원/월 retain their literal denominator.
    if(numericLeft&&/^\p{L}+(?=$|[^\p{L}\p{N}\p{M}])/u.test(text.slice(at+1)))continue;
    if(numericLeft||numericRight)return false;
  }
  return true;
}
export const numericShape=(text:string)=>numericNotationSupported(text)?tokens(text).map(t=>t.kind).join(','):null;
export function numericPattern(text:string):string{
  let result='',end=0;
  for(const t of tokens(text)){result+=text.slice(end,t.start)+(t.kind==='fraction'?'#/#':'#');end=t.end;}
  return normalize(result+text.slice(end));
}
