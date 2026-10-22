import { mkdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { strToU8, zipSync } from 'fflate';

const escape = (value:string) => value.replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;');
// Synthetic source workbooks, independent of the ingest/report implementation.
// They contain no macros, links, executable objects or private/business data.
export async function generateWorkbookDemo(folder:string) {
  await mkdir(folder,{recursive:true});
  const files:string[]=[];
  for(const version of [1,2,3]) {
    const rows:(string|number)[][]=version===1?[["SKU001","한글 검토",100,2],["SKU002","기본 패키지",50,1]]:
      version===2?[["SKU003","중간 검토에만 있음",30,1],["SKU001","한글 검토",120,2],["SKU002","기본 패키지",50,1]]:
      [["SKU002","기본 패키지",50,1],["SKU001","한글 검토",110,2]];
    const columns=['A','B','C','D','E'];
    const textCell=(address:string,value:string)=>`<c r="${address}" t="inlineStr"><is><t>${escape(value)}</t></is></c>`;
    const header='<row r="1">'+['SKU','항목','단가','수량','합계'].map((v,i)=>textCell(columns[i]+'1',v)).join('')+'</row>';
    const body=rows.map((row,i)=>{
      const number=i+2,cells=row.map((v,j)=>typeof v==='string'?textCell(columns[j]+number,v):`<c r="${columns[j]+number}"><v>${v}</v></c>`).join('');
      const sum=Number(row[2])*Number(row[3]),formula=version===3&&row[0]==='SKU001'?'':`<f>C${number}*D${number}</f>`;
      return `<row r="${number}">${cells}<c r="E${number}">${formula}<v>${sum}</v></c></row>`;
    }).join('');
    const sheet=`<?xml version="1.0" encoding="UTF-8"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><cols><col min="1" max="1" width="14" customWidth="1"/><col min="2" max="2" width="30" customWidth="1"/></cols><sheetData>${header}${body}</sheetData></worksheet>`;
    const main='http://schemas.openxmlformats.org/spreadsheetml/2006/main',rels='http://schemas.openxmlformats.org/officeDocument/2006/relationships',packageRels='http://schemas.openxmlformats.org/package/2006/relationships';
    const parts:Record<string,Uint8Array>={
      '[Content_Types].xml':strToU8('<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>'),
      '_rels/.rels':strToU8(`<Relationships xmlns="${packageRels}"><Relationship Id="rBook" Type="${rels}/officeDocument" Target="xl/workbook.xml"/></Relationships>`),
      'xl/workbook.xml':strToU8(`<workbook xmlns="${main}" xmlns:r="${rels}"><workbookPr date1904="0"/><sheets><sheet name="견적서" sheetId="1" r:id="rSheet"/></sheets><calcPr calcId="0" fullCalcOnLoad="1"/></workbook>`),
      'xl/_rels/workbook.xml.rels':strToU8(`<Relationships xmlns="${packageRels}"><Relationship Id="rSheet" Type="${rels}/worksheet" Target="worksheets/sheet1.xml"/></Relationships>`),
      'xl/worksheets/sheet1.xml':strToU8(sheet),
    };
    const name=`v${version}.xlsx`;await writeFile(join(folder,name),zipSync(parts,{mtime:new Date(1980,0,1)}));files.push(name);
  }
  const manifest={title:'견적서 · 합성 3버전',revisions:files.map((path,i)=>({label:['초안 100','검토 120 · 중간 항목','배포 110 · 수식→상수'][i],path}))};
  await writeFile(join(folder,'manifest.json'),JSON.stringify(manifest,null,2)+'\n');return manifest;
}
