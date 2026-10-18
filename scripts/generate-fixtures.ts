import pptxgen from 'pptxgenjs';
import PDFDocument from 'pdfkit';
import { createCanvas } from '@napi-rs/canvas';
import { unzipSync, zipSync, strFromU8, strToU8 } from 'fflate';
import { existsSync } from 'node:fs';
import { mkdir, writeFile, readFile } from 'node:fs/promises';
import { resolve, join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { byteHash } from '../packages/schema/index.js';
import { scenarios, type SlideSpec } from '../tests/ground-truth/scenarios.js';
export const FONT=process.env.DOCVER_FIXTURE_FONT??'/System/Library/Fonts/Supplemental/AppleGothic.ttf';
export async function makePptx(slides:SlideSpec[]):Promise<Buffer> {
  const deck=new (pptxgen as unknown as typeof pptxgen.default)();deck.layout='LAYOUT_WIDE';deck.author='Document Version Tracker synthetic fixture';deck.subject='Seed 20261018';deck.title='Synthetic fixture';
  for(const spec of slides) {
    const slide=deck.addSlide();slide.hidden=spec.hidden??false;
    slide.addText(spec.title,{x:0.9,y:0.6,w:11.5,h:0.8,fontSize:28,fontFace:'AppleGothic',margin:0,breakLine:false});
    slide.addText(spec.body,{x:0.9,y:2,w:11.5,h:1.2,fontSize:22,fontFace:'AppleGothic',margin:0});
    if(spec.notes) slide.addNotes(spec.notes);
  }
  const raw=await deck.write({outputType:'nodebuffer'}) as Buffer;
  const parts=unzipSync(raw);
  for(const name of Object.keys(parts)) if(name==='docProps/core.xml') parts[name]=strToU8(strFromU8(parts[name]).replace(/<dcterms:(created|modified)[^>]*>[^<]*</g,(_,tag)=>`<dcterms:${tag} xsi:type="dcterms:W3CDTF">2026-10-18T00:00:00Z<`));
  return Buffer.from(zipSync(Object.fromEntries(Object.entries(parts).map(([name,data])=>[name,[data,{mtime:new Date('2026-10-18T00:00:00Z')}]])),{level:6}));
}
export async function makePdf(slides:SlideSpec[],scan=false):Promise<Buffer> {
  if(!existsSync(FONT)) throw new Error('Set DOCVER_FIXTURE_FONT to a Korean-capable TTF font path');
  const doc=new PDFDocument({autoFirstPage:false,compress:true,info:{Title:'Synthetic fixture',Author:'Document Version Tracker',CreationDate:new Date('2026-10-18T00:00:00Z'),ModDate:new Date('2026-10-18T00:00:00Z')}});
  const chunks:Buffer[]=[];doc.on('data',b=>chunks.push(b));
  const completed=new Promise<Buffer>((res,rej)=>{doc.on('end',()=>res(Buffer.concat(chunks)));doc.on('error',rej);});
  doc.registerFont('fixture',FONT);
  for(const s of slides.filter(s=>!s.hidden)) {
    doc.addPage({size:[960,540],margin:0});
    if(scan) {
      const canvas=createCanvas(960,540),ctx=canvas.getContext('2d');ctx.fillStyle='white';ctx.fillRect(0,0,960,540);ctx.fillStyle='black';ctx.font='28px sans-serif';ctx.fillText(s.title,65,65);ctx.font='22px sans-serif';ctx.fillText(s.body,65,170);
      doc.image(canvas.toBuffer('image/png'),0,0,{width:960,height:540});
    } else {
      doc.font('fixture').fontSize(28).text(s.title,65,44,{width:828,height:60,lineBreak:false});
      doc.fontSize(22).text(s.body,65,144,{width:828,height:110,lineBreak:false});
    }
  }
  doc.end();return completed;
}
export async function generateFixtures(root:string):Promise<string[]> {
  await mkdir(root,{recursive:true});const manifests:string[]=[];
  for(const scenario of scenarios) {
    const folder=join(root,scenario.name);await mkdir(folder,{recursive:true});
    const revisions:{label:string;files:string[]}[]=[],assets:Record<string,string>={};
    for(const [i,v] of scenario.versions.entries()) {
      const files:string[]=[];
      for(const format of v.formats) {
        const file=`v${i+1}.${format}`;
        const slides=v.wrongBundle&&format==='pdf'?[{key:'wrong',title:'다른 문서',body:'이 PDF는 원본과 일치하지 않음'}]:v.slides;
        const bytes=format==='pptx'?await makePptx(slides):await makePdf(slides,v.scan);
        await writeFile(join(folder,file),bytes);files.push(file);assets[file]='sha256:'+byteHash(bytes);
      }
      revisions.push({label:`Version ${i+1}`,files});
    }
    const manifest={project_id:'prj_'+scenario.name.replaceAll('-','_'),title:scenario.name,revisions,mapping_decisions:[]};
    const manifestPath=join(folder,'manifest.json');await writeFile(manifestPath,JSON.stringify(manifest,null,2)+'\n');manifests.push(manifestPath);
    await writeFile(join(folder,'fixture.json'),JSON.stringify({seed:20261018,generator_version:'1.0.0',generators:{pptx:'PptxGenJS 4.0.1',pdf:'PDFKit 0.20.2',font:FONT,font_sha256:byteHash(await readFile(FONT))},
      assets,expected:scenario.expected,mapping:scenario.versions.map((v,i)=>({version:i+1,pages:v.slides.map((s,n)=>({key:s.key,source_page:n+1,hidden:s.hidden??false}))})),
      allowed_loss:['PDF notes/animation/hidden slides unavailable','scan has no original text layer; OCR remains inferred'],reference:'Independent semantic construction; not an office-renderer fidelity oracle'},null,2)+'\n');
  }
  return manifests;
}
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href) {
  const paths=await generateFixtures(resolve(process.argv[2]??'tests/fixtures/generated'));console.log(JSON.stringify({generated:paths.length,manifests:paths},null,2));
}
