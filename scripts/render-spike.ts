import pptxgen from 'pptxgenjs';
import PDFDocument from 'pdfkit';
import { createCanvas, loadImage } from '@napi-rs/canvas';
import { mkdir, writeFile, readFile } from 'node:fs/promises';
import { resolve, join } from 'node:path';
import { FONT } from './generate-fixtures.js';
import { renderPdf, convertPptx } from '../packages/render/index.js';
import { ingest } from '../packages/ingest/index.js';
import { byteHash, DocverError } from '../packages/schema/index.js';
const folder=resolve(process.argv[2]??'artifacts/render-spike');await mkdir(folder,{recursive:true});
const deck=new (pptxgen as unknown as typeof pptxgen.default)();deck.layout='LAYOUT_WIDE';
const reference=new PDFDocument({autoFirstPage:false,info:{Title:'Independent PDFKit synthetic reference'}}),chunks:Buffer[]=[];
reference.on('data',b=>chunks.push(b));const referenceDone=new Promise<Buffer>(res=>reference.on('end',()=>res(Buffer.concat(chunks))));
reference.registerFont('korean',FONT);
const sourceImages:string[]=[];
for(let i=0;i<6;i++) {
  const slide=deck.addSlide();slide.hidden=i>=3;
  slide.addText(`한글 렌더 검증 ${i+1}`,{x:0.6,y:0.4,w:9,h:0.6,fontFace:'AppleGothic',fontSize:26,margin:0});
  slide.addText('Mixed fonts 100 → 120 → 110',{x:0.6,y:1.1,w:9,h:0.6,fontFace:'Arial',fontSize:20,margin:0});
  slide.addShape(deck.ShapeType.rect,{x:0.6,y:2,w:2,h:1,fill:{color:'4361EE',transparency:35},line:{color:'1B2451'}});
  slide.addText('회전 텍스트',{x:3,y:2,w:2,h:0.7,fontFace:'AppleGothic',fontSize:20,rotate:30});
  slide.addTable([['분기','매출'],['Q1','100'],['Q2','120']].map(row=>row.map(text=>({text}))),{x:0.6,y:3.5,w:4,h:1.5,fontFace:'AppleGothic',fontSize:16,border:{pt:1,color:'AAAAAA'}});
  slide.addChart(deck.ChartType.bar,[{name:'매출',labels:['Q1','Q2','Q3'],values:[100,120,110]}],{x:6,y:2,w:5,h:3.4,showLegend:false,showTitle:false});
  const image=createCanvas(160,80),ctx=image.getContext('2d');ctx.fillStyle='#4361ee';ctx.fillRect(0,0,160,80);ctx.fillStyle='#fff';ctx.fillRect(15+i,15,60,40);
  const imageBytes=image.toBuffer('image/png'),imagePath=join(folder,`source-${i+1}.png`);await writeFile(imagePath,imageBytes);sourceImages.push(imagePath);
  slide.addImage({data:'image/png;base64,'+imageBytes.toString('base64'),x:10,y:0.4,w:2,h:1});
  slide.addNotes('이 합성 메모는 PDF에 관측되지 않는다.');
  if(i<3) {
    reference.addPage({size:[960,540],margin:0});
    reference.font('korean').fontSize(26).text(`한글 렌더 검증 ${i+1}`,43.2,28.8);
    reference.font('Helvetica').fontSize(20).text('Mixed fonts 100 -> 120 -> 110',43.2,79.2);
    reference.save().fillOpacity(0.65).rect(43.2,144,144,72).fill('#4361EE').restore();
    reference.save().translate(216,144).rotate(30).font('korean').fontSize(20).text('회전 텍스트',0,0).restore();
    for(let row=0;row<3;row++)for(let col=0;col<2;col++) {reference.rect(43.2+col*144,252+row*36,144,36).stroke('#AAAAAA');reference.font('korean').fontSize(16).text([['분기','매출'],['Q1','100'],['Q2','120']][row][col],48+col*144,260+row*36);}
    for(let j=0;j<3;j++) reference.rect(450+j*90,380-[100,120,110][j],50,[100,120,110][j]).fill('#4361EE');
    reference.image(imageBytes,720,28.8,{width:144,height:72});
  }
}
reference.end();const ref=await referenceDone;
await deck.writeFile({fileName:join(folder,'deck.pptx')});await writeFile(join(folder,'reference.pdf'),ref);
const extracted=await ingest(join(folder,'deck.pptx'));
for(let i=1;i<=3;i++)await writeFile(join(folder,`reference-${i}.png`),await renderPdf(ref,i));
const report:any={created_at:new Date().toISOString(),environment:{node:process.version,platform:process.platform,arch:process.arch,font:FONT,font_sha256:byteHash(await readFile(FONT))},
  fixtures:{slides:6,visible:3,hidden:3,features:{korean:6,mixed_fonts:6,shapes:6,transparency:6,tables:6,charts:6,rotated_text:6,hidden_slides:3},source_images:sourceImages.map(p=>p.split('/').at(-1))},
  reference:{authoring_tool:'PDFKit 0.20.2',method:'Independent construction from the same synthetic design; not an Office-rendered reference',sha256:byteHash(ref),
    limitations:['PDFKit drawing differs in text shaping, table/chart defaults and font choices','This is not a validated pixel-fidelity ground truth']},
  structure:{pages:extracted.pages.length,hidden_pages:extracted.pages.filter(p=>p.hidden).length,text_elements:extracted.pages.flatMap(p=>p.elements).filter(e=>e.kind==='text').length,
    table_chart_semantics:'unsupported',rotation_bbox:'approximate'},converter:{status:'not_run'},pixel_comparison:{status:'unverified',reason:'Independent Office-rendered reference not available'}};
try {
  const executable=process.env.DOCVER_SOFFICE??'soffice';
  const converted=await convertPptx(join(folder,'deck.pptx'),executable);await writeFile(join(folder,'converted.pdf'),converted);
  report.converter={status:'success',executable};
  const actual=await renderPdf(converted,1),expected=await renderPdf(ref,1);await writeFile(join(folder,'converted-1.png'),actual);
  const a=await loadImage(actual),b=await loadImage(expected),c=createCanvas(960,540),ctx=c.getContext('2d');
  ctx.drawImage(a,0,0,960,540);const pa=ctx.getImageData(0,0,960,540).data;ctx.clearRect(0,0,960,540);ctx.drawImage(b,0,0,960,540);const pb=ctx.getImageData(0,0,960,540).data;
  let error=0;for(let i=0;i<pa.length;i++)error+=Math.abs(pa[i]-pb[i]);
  report.pixel_comparison={status:'descriptive_only',mean_absolute_channel_error:error/pa.length,visual_fidelity:'unverified; reference not validated'};
} catch(e) {report.converter={status:'unavailable_or_failed',code:e instanceof DocverError?e.code:'UNKNOWN',message:(e as Error).message};}
await writeFile(join(folder,'report.json'),JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify({folder,structure:report.structure,converter:report.converter,pixel_comparison:report.pixel_comparison},null,2));
