import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,writeFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {zipSync,unzipSync,strToU8} from 'fflate';
import pptxgen from 'pptxgenjs';
import {getDocument} from 'pdfjs-dist/legacy/build/pdf.mjs';
import {materializeOfficeInsets} from '../../packages/render/pptx-default-insets.js';
import {convertPptx,renderPdf} from '../../packages/render/index.js';
import {officeExecutable} from '../../packages/runtime/tools.js';
import {pdfOptions} from '../../packages/ingest/pdf.js';
import {byteHash} from '../../packages/schema/index.js';
const p='http://schemas.openxmlformats.org/presentationml/2006/main',a='http://schemas.openxmlformats.org/drawingml/2006/main';
const slide=(body:string)=>`<p:sld xmlns:p="${p}" xmlns:a="${a}"><p:cSld><p:spTree>${body}</p:spTree></p:cSld></p:sld>`;
const shape=(attrs='',metadata='')=>`<p:sp><p:nvSpPr><p:nvPr>${metadata}</p:nvPr></p:nvSpPr><p:txBody><a:bodyPr${attrs}/><a:p><a:r><a:t>Original &amp; text</a:t></a:r></a:p></p:txBody></p:sp>`;
function packageXml(xml:string,extra:Record<string,Uint8Array>={}){return zipSync({'ppt/slides/slide1.xml':strToU8(xml),'ppt/media/original.bin':new Uint8Array([1,2,3,4]),...extra},{mtime:new Date(1980,0,1)});}
const xmlOf=(bytes:Uint8Array)=>new TextDecoder().decode(unzipSync(bytes)['ppt/slides/slide1.xml']);
test('renderer defaults preserve source bytes, explicit margins, XML namespaces and placeholder inheritance',()=>{
  const original=packageXml(slide(shape(' anchor="ctr"'))),saved=original.slice(),first=materializeOfficeInsets(original);
  assert.equal(first.changed_properties,4);assert.deepEqual(original,saved);assert.match(xmlOf(first.bytes),/lIns="91440"/);assert.match(xmlOf(first.bytes),/tIns="45720"/);
  assert.deepEqual(unzipSync(first.bytes)['ppt/media/original.bin'],new Uint8Array([1,2,3,4]));
  assert.equal(byteHash(first.bytes),byteHash(materializeOfficeInsets(original).bytes),'Prepared bytes are deterministic');
  const again=materializeOfficeInsets(first.bytes);assert.equal(again.changed_properties,0);assert.strictEqual(again.bytes,first.bytes);
  const explicit=packageXml(slide(shape(" lIns='0' tIns='123' rIns='456' bIns='789'")));assert.strictEqual(materializeOfficeInsets(explicit).bytes,explicit);
  const placeholder=packageXml(slide(shape('', '<p:ph type="body" idx="2"/>')));assert.strictEqual(materializeOfficeInsets(placeholder).bytes,placeholder);
  const aliases=slide('<p:grpSp>'+shape()+'</p:grpSp>').replace(/(<\/?)p:/g,'$1pres:').replace(/(<\/?)a:/g,'$1draw:').replace('xmlns:p=', 'xmlns:pres=').replace('xmlns:a=', 'xmlns:draw=');
  assert.equal(materializeOfficeInsets(packageXml(aliases)).changed_properties,4);
  const defaultNamespace=slide(shape()).replace(/(<\/?)p:/g,'$1').replace('xmlns:p=', 'xmlns=');assert.equal(materializeOfficeInsets(packageXml(defaultNamespace)).changed_properties,4);
  const strict=slide(shape()).replace(p,'http://purl.oclc.org/ooxml/presentationml/main').replace(a,'http://purl.oclc.org/ooxml/drawingml/main');assert.equal(materializeOfficeInsets(packageXml(strict)).changed_properties,4);
  const rebound=packageXml(slide(shape()).replace('<p:txBody>','<p:txBody xmlns:a="urn:other">'));assert.strictEqual(materializeOfficeInsets(rebound).bytes,rebound);
  const table=packageXml(slide('<a:tbl><a:tr><a:tc><a:txBody><a:bodyPr/></a:txBody></a:tc></a:tr></a:tbl>'));assert.strictEqual(materializeOfficeInsets(table).bytes,table);
});
test('ambiguous, signed, malformed and extension-only package content is never rewritten',()=>{
  for(const xml of [slide(shape()).replace('</p:sp>','<p:txBody><a:bodyPr/></p:txBody></p:sp>'),slide('<p:extLst>'+shape()+'</p:extLst>'),slide(shape()).replace('</p:sld>',''),'<not-a-slide>'+shape()+'</not-a-slide>']){
    const bytes=packageXml(xml);assert.strictEqual(materializeOfficeInsets(bytes).bytes,bytes);
  }
  const extras:Record<string,Uint8Array>[]=[{'_xmlsignatures/sig1.xml':strToU8('<signature/>')},{'PPT/slides/slide1.xml':strToU8(slide(shape()))}];
  for(const extra of extras){
    const bytes=packageXml(slide(shape()),extra);assert.strictEqual(materializeOfficeInsets(bytes).bytes,bytes);
  }
  const ignored=slide('<!-- <p:sp><p:txBody><a:bodyPr/></p:txBody></p:sp> --><a:extLst><![CDATA[<a:bodyPr/>]]></a:extLst>'+shape());
  assert.equal(materializeOfficeInsets(packageXml(ignored)).changed_properties,4);
  const deep=packageXml(slide(shape()+'<p:extLst>'+'<x>'.repeat(105)+'</x>'.repeat(105)+'</p:extLst>'));assert.strictEqual(materializeOfficeInsets(deep).bytes,deep);
});
test('actual Impress text starts at the standard 0.1-inch margin and implicit/explicit defaults render equally',{skip:!officeExecutable()},async()=>{
  const folder=await mkdtemp(join(tmpdir(),'docver-insets-'));
  try{
    const deck=new (pptxgen as unknown as typeof pptxgen.default)();deck.layout='LAYOUT_WIDE';deck.addSlide().addText('Standard inset position',{x:1,y:1,w:5,h:1,fontFace:'Arial',fontSize:32,margin:0,breakLine:false});
    const input=Buffer.from(await deck.write({outputType:'nodebuffer'}) as Buffer),parts=unzipSync(input),xml=new TextDecoder().decode(parts['ppt/slides/slide1.xml']);
    const implicit=xml.replace(/<a:bodyPr\b([^>]*)>/g,(_whole,attrs:string)=>'<a:bodyPr'+attrs.replace(/\s+[lrtb]Ins="[^"]*"/g,'')+'>');
    parts['ppt/slides/slide1.xml']=strToU8(implicit);const bytes=zipSync(parts),sourceHash=byteHash(bytes),path=join(folder,'implicit.pptx');await writeFile(path,bytes);
    const actual=await convertPptx(path,undefined,120000,undefined,bytes),task=getDocument({...pdfOptions,data:new Uint8Array(actual)});
    try{const doc=await task.promise,page=await doc.getPage(1),content=await page.getTextContent(),text=content.items.find(item=>'str'in item&&item.str==='Standard inset position');assert.ok(text&&'transform'in text);assert.ok(Math.abs(text.transform[4]-79.2)<.03,`Expected72pt+7.2pt standard inset, actual ${text.transform[4]}`);}finally{await task.destroy();}
    const explicit=implicit.replace(/<a:bodyPr\b/, '<a:bodyPr lIns="91440" rIns="91440" tIns="45720" bIns="45720"');parts['ppt/slides/slide1.xml']=strToU8(explicit);const expected=await convertPptx(path,undefined,120000,undefined,zipSync(parts));
    assert.equal(byteHash(await renderPdf(actual,1,1440)),byteHash(await renderPdf(expected,1,1440)));assert.equal(byteHash(bytes),sourceHash);
  }finally{await rm(folder,{recursive:true,force:true});}
});
