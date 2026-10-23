import {mkdir,writeFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import PDFDocument from 'pdfkit';
import pptxgen from 'pptxgenjs';
import {generateWorkbookDemo} from './generate-workbook-demo.js';
import {odsFixture} from '../tests/workbook-fixtures.js';
import {unzipSync,zipSync,strToU8,strFromU8} from 'fflate';
import {readFile} from 'node:fs/promises';

const folder=resolve(process.argv[2]??'tests/fixtures/generated/windows');
await mkdir(folder,{recursive:true});
for(const [version,value] of [[1,100],[2,120]] as const){
  const pdf=new PDFDocument({size:[720,405],margin:40}),chunks:Buffer[]=[];
  const done=new Promise<Buffer>((ok,fail)=>{pdf.on('data',(b:Buffer)=>chunks.push(b));pdf.on('end',()=>ok(Buffer.concat(chunks)));pdf.on('error',fail);});
  pdf.fontSize(26).text('Revenue '+value,40,50);pdf.fontSize(14).text('Windows native comparison control',40,110);pdf.end();
  await writeFile(join(folder,`v${version}.pdf`),await done);
}
const deck=new (pptxgen as unknown as typeof pptxgen.default)();deck.layout='LAYOUT_WIDE';
deck.addSlide().addText('Revenue 110',{x:1,y:1,w:10,h:1,fontSize:28});
await deck.writeFile({fileName:join(folder,'v3.pptx')});
await generateWorkbookDemo(join(folder,'workbooks'));
const longValue='한글😀{0}% opaque '.repeat(600),longFormula='CONCAT("'+'한글😀{0}%'.repeat(900)+'")',longLiteral='='+longFormula;
const csvQuote=(text:string)=>'"'+text.replaceAll('"','""')+'"';
await writeFile(join(folder,'workbooks/v4.csv'),'SKU,항목,단가,수량,합계\nSKU001,한글 검토,130,2,260\nLONG,'+csvQuote(longValue)+','+csvQuote(longLiteral)+',1,0\n');
const xlsxPath=join(folder,'workbooks/v2.xlsx'),xlsx=unzipSync(await readFile(xlsxPath)),sheetKey='xl/worksheets/sheet1.xml';
const sheetXML=strFromU8(xlsx[sheetKey]);
if((sheetXML.match(/<c r="D4">/gu)??[]).length!==1)throw new Error('Expected one synthetic D4 cell');
xlsx[sheetKey]=strToU8(sheetXML.replace(/<c r="D4">[\s\S]*?<\/c>/u,'<c r="D4" t="str"><f>'+longFormula.replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;')+'</f><v>stored only; not recalculated</v></c>'));
await writeFile(xlsxPath,zipSync(xlsx,{mtime:new Date(1980,0,1)}));
await writeFile(join(folder,'workbooks/v5.ods'),odsFixture('<table:table table:name="견적서"><table:table-row><table:table-cell office:value-type="string"><text:p>SKU001</text:p></table:table-cell><table:table-cell office:value-type="float" office:value="140" table:formula="of:=70*2"><text:p>140</text:p></table:table-cell></table:table-row></table:table>'));
await writeFile(join(folder,'windows-smoke.json'),JSON.stringify({documents:{title:'Windows document control',revisions:[{label:'Draft 100',files:['v1.pdf']},{label:'Review 120',files:['v2.pdf']},{label:'PPTX structure 110',files:['v3.pptx']}]},workbook:{title:'Windows workbook control',revisions:[1,2,3].map(i=>({label:'XLSX '+i,path:`workbooks/v${i}.xlsx`})).concat([{label:'CSV 130',path:'workbooks/v4.csv'},{label:'ODS 140',path:'workbooks/v5.ods'}])},expected_long_sources:{csv_b3:longValue,csv_c3:longLiteral,xlsx_d4_formula:longFormula}},null,2)+'\n');
console.log(JSON.stringify({folder,source:'independent synthetic files; no macros, links, private data or external instructions'}));
