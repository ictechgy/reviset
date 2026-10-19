import {normalize} from '../schema/index.js';
// Keep numeric slot boundaries aligned with Vision.swift. Complete fractions
// are one slot; mixed integer + vulgar fraction stays two. Units remain literal
// in the masked pattern so an inferred amount cannot silently change its unit.
const token=/(?:(?<![\p{L}\p{N}])[+＋−-]\s*)?(?:[0-9０-９]+\s*[/⁄／]\s*[0-9０-９]+|[¼½¾⅐⅑⅒⅓⅔⅕⅖⅗⅘⅙⅚⅛⅜⅝⅞↉]|[0-9０-９]+(?:[.,，．][0-9０-９]+)*)/gu;
export const numericSlots=(text:string)=>Array.from(text.matchAll(token),m=>m[0].normalize('NFKC').replace(/−/gu,'-').replace(/⁄/gu,'/').replace(/\s/gu,''));
export const numericPattern=(text:string)=>normalize(text).replace(token,'#');
