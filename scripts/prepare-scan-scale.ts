import PDFDocument from 'pdfkit';
import { createCanvas } from '@napi-rs/canvas';
import { mkdir,writeFile } from 'node:fs/promises';
import { resolve,join } from 'node:path';
import { byteHash } from '../packages/schema/index.js';
const folder=resolve('artifacts/scan-scale-fixture'),count=Number(process.argv[2]??300);if(!Number.isInteger(count)||count<1||count>1000)throw new Error('Count must be 1..1000');await mkdir(folder,{recursive:true});
const assets:Record<string,string>={};
for(const version of [1,2]){
  const doc=new PDFDocument({autoFirstPage:false,compress:true}),chunks:Buffer[]=[];doc.on('data',b=>chunks.push(b));const done=new Promise<Buffer>(resolve=>doc.on('end',()=>resolve(Buffer.concat(chunks))));
  for(let page=1;page<=count;page++){
    const c=createCanvas(1600,900),ctx=c.getContext('2d');ctx.fillStyle='white';ctx.fillRect(0,0,1600,900);ctx.fillStyle='black';ctx.font='42px AppleGothic';
    const key=[Math.floor((page-1)/676),Math.floor((page-1)/26)%26,(page-1)%26].map(n=>String.fromCharCode(65+n)).join('');
    ctx.fillText('사업 검토 · Document '+key,100,130);ctx.font='46px AppleGothic';ctx.fillText('예상 매출 '+(version===2&&page===Math.ceil(count/2)?'120':'100')+'억',100,300);
    doc.addPage({size:[960,540],margin:0});doc.image(c.toBuffer('image/png'),0,0,{width:960,height:540});
  }
  doc.end();const bytes=await done,name=`v${version}.pdf`;await writeFile(join(folder,name),bytes);assets[name]='sha256:'+byteHash(bytes);
}
await writeFile(join(folder,'ground-truth.json'),JSON.stringify({pages:[count,count],changed_page:Math.ceil(count/2),before:'100억',after:'120억',assets,source:'Independent synthetic raster scans, no text layer; AppleGothic, Korean/English'},null,2));console.log(JSON.stringify({folder,pages:[count,count],assets}));
