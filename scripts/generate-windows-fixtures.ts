import {mkdir,writeFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import PDFDocument from 'pdfkit';
import pptxgen from 'pptxgenjs';
import {generateWorkbookDemo} from './generate-workbook-demo.js';
import {odsFixture} from '../tests/workbook-fixtures.js';

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
await writeFile(join(folder,'workbooks/v4.csv'),'SKU,항목,단가,수량,합계\nSKU001,한글 검토,130,2,260\n');
await writeFile(join(folder,'workbooks/v5.ods'),odsFixture('<table:table table:name="견적서"><table:table-row><table:table-cell office:value-type="string"><text:p>SKU001</text:p></table:table-cell><table:table-cell office:value-type="float" office:value="140" table:formula="of:=70*2"><text:p>140</text:p></table:table-cell></table:table-row></table:table>'));
await writeFile(join(folder,'windows-smoke.json'),JSON.stringify({documents:{title:'Windows document control',revisions:[{label:'Draft 100',files:['v1.pdf']},{label:'Review 120',files:['v2.pdf']},{label:'PPTX structure 110',files:['v3.pptx']}]},workbook:{title:'Windows workbook control',revisions:[1,2,3].map(i=>({label:'XLSX '+i,path:`workbooks/v${i}.xlsx`})).concat([{label:'CSV 130',path:'workbooks/v4.csv'},{label:'ODS 140',path:'workbooks/v5.ods'}])}},null,2)+'\n');
console.log(JSON.stringify({folder,source:'independent synthetic files; no macros, links, private data or external instructions'}));
