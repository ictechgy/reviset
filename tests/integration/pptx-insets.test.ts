import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,writeFile,rm,readFile,realpath} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {execFileSync} from 'node:child_process';
import {zipSync,unzipSync,strToU8} from 'fflate';
import pptxgen from 'pptxgenjs';
import {getDocument} from 'pdfjs-dist/legacy/build/pdf.mjs';
import {materializeOfficeInsets} from '../../packages/render/pptx-default-insets.js';
import {convertPptx,convertPptxDetailed,renderPdf} from '../../packages/render/index.js';
import {prepareOfficeInput,officeInputEnvironment} from '../../packages/render/office-input.js';
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
  const partial=materializeOfficeInsets(packageXml(slide(shape(" lIns='0'"))));assert.equal(partial.changed_properties,3);assert.match(xmlOf(partial.bytes),/lIns='0'/);
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
  const nestedExtension=packageXml(slide('<p:extLst><p:ext uri="test"><x:payload xmlns:x="urn:custom"><p:grpSp>'+shape()+'</p:grpSp></x:payload></p:ext></p:extLst>'));
  assert.strictEqual(materializeOfficeInsets(nestedExtension).bytes,nestedExtension,'Nested groups do not reopen an opaque extension branch');
});
test('OPC signature indicators exclude arbitrary signature paths and XML-encoded relationship/content types',()=>{
  const type='http://schemas.openxmlformats.org/package/2006/relationships/digital-signature/origin';
  for(const encoded of [type,type.replace('digital-signature','digital&#45;signature')]){
    const rel=`<pkg:Relationships xmlns:pkg="http://schemas.openxmlformats.org/package/2006/relationships"><pkg:Relationship Id="sig" Type="${encoded}" Target="custom/origin.sigs"/></pkg:Relationships>`;
    const original=packageXml(slide(shape()),{'_rels/.rels':strToU8(rel),'custom/origin.sigs':new Uint8Array(),'custom/signature.xml':strToU8('<metadata-only-signature-indicator/>')});
    const actual=materializeOfficeInsets(original);assert.strictEqual(actual.bytes,original);assert.equal(actual.skip_reason,'signed_package');
  }
  const contentTypes='<c:Types xmlns:c="http://schemas.openxmlformats.org/package/2006/content-types"><c:Override PartName="/custom/signature.xml" ContentType="application/vnd.openxmlformats-package.digital&#45;signature-xmlsignature+xml"/></c:Types>';
  const original=packageXml(slide(shape()),{'[Content_Types].xml':strToU8(contentTypes)});assert.strictEqual(materializeOfficeInsets(original).bytes,original);
});
test('derived UTF8 part, total and ZIP bytes stay within budgets and preserve a rewritten BOM',()=>{
  const xml=slide(shape()).replace('Original &amp; text','한글😀'.repeat(30)),original=packageXml(xml),size=strToU8(xml).length;
  const part=materializeOfficeInsets(original,{partBytes:size+51});assert.strictEqual(part.bytes,original);assert.equal(part.skip_reason,'derivation_budget_exceeded');
  const total=materializeOfficeInsets(original,{totalBytes:size+4+51});assert.strictEqual(total.bytes,original);assert.equal(total.skip_reason,'derivation_budget_exceeded');
  const media=packageXml(xml,{'ppt/media/original.bin':new Uint8Array(1000)}),zip=materializeOfficeInsets(media,{zipBytes:media.length+50});assert.strictEqual(zip.bytes,media);assert.equal(zip.skip_reason,'derivation_budget_exceeded');
  const bom=materializeOfficeInsets(packageXml('\ufeff'+xml));assert.equal(bom.changed_properties,4);assert.deepEqual([...unzipSync(bom.bytes)['ppt/slides/slide1.xml'].slice(0,3)],[239,187,191]);
});
test('renderer input helper verifies provenance and supports responsive cancellation and timeouts',async()=>{
  const folder=await realpath(await mkdtemp(join(tmpdir(),'docver-input-helper-')));
  try{
    const original=packageXml(slide(shape())),source=join(folder,'input.pptx');await writeFile(source,original);
    const prepared=await prepareOfficeInput(folder,byteHash(original),30000),bytes=await readFile(prepared.path),environment=await officeInputEnvironment();
    assert.equal(prepared.metadata.changed_properties,4);assert.equal(prepared.metadata.policy,environment.policy);assert.match(environment.helper_fingerprint,/^[a-f0-9]{64}$/);
    assert.equal(prepared.metadata.source_sha256,byteHash(original));assert.equal(prepared.metadata.input_sha256,byteHash(bytes));assert.equal(byteHash(await readFile(source)),byteHash(original));
    assert.equal(byteHash(bytes),byteHash(materializeOfficeInsets(original).bytes));
    const controller=new AbortController();let heartbeats=0;
    const pulse=setInterval(()=>heartbeats++,2),cancel=setTimeout(()=>controller.abort(),25);
    try{await assert.rejects(()=>prepareOfficeInput(folder,byteHash(original),30000,controller.signal),(error:any)=>error.code==='CANCELLED'||error.name==='AbortError');assert.ok(heartbeats>0,'Preparation must yield to cancellation/UI work');}
    finally{clearInterval(pulse);clearTimeout(cancel);}
    await assert.rejects(()=>prepareOfficeInput(folder,byteHash(original),1),(error:any)=>error.code==='TOOL_TIMEOUT');
  }finally{await rm(folder,{recursive:true,force:true});}
});
test('actual Impress text starts at the standard 0.1-inch margin and implicit/explicit defaults render equally',{skip:!officeExecutable()},async()=>{
  const folder=await mkdtemp(join(tmpdir(),'docver-insets-'));
  try{
    const deck=new (pptxgen as unknown as typeof pptxgen.default)();deck.layout='LAYOUT_WIDE';deck.addSlide().addText('Standard inset position',{x:1,y:1,w:5,h:1,fontFace:'Arial',fontSize:32,margin:0,breakLine:false});
    deck.addSlide().addText('Preview diagnostic neighbor',{x:1,y:1,w:5,h:1,fontFace:'Arial',fontSize:24,margin:0});
    const input=Buffer.from(await deck.write({outputType:'nodebuffer'}) as Buffer),parts=unzipSync(input),xml=new TextDecoder().decode(parts['ppt/slides/slide1.xml']);
    const implicit=xml.replace(/<a:bodyPr\b([^>]*)>/g,(_whole,attrs:string)=>'<a:bodyPr'+attrs.replace(/\s+[lrtb]Ins="[^"]*"/g,'')+'>');
    parts['ppt/slides/slide1.xml']=strToU8(implicit);const bytes=zipSync(parts),sourceHash=byteHash(bytes),path=join(folder,'implicit.pptx');await writeFile(path,bytes);
    const converted=await convertPptxDetailed(path,undefined,120000,undefined,bytes),actual=converted.pdf,task=getDocument({...pdfOptions,data:new Uint8Array(actual)});
    assert.equal(converted.input.source_sha256,sourceHash);assert.equal(converted.input.changed_properties,4);assert.notEqual(converted.input.input_sha256,sourceHash);
    try{const doc=await task.promise,page=await doc.getPage(1),content=await page.getTextContent(),text=content.items.find(item=>'str'in item&&item.str==='Standard inset position');assert.ok(text&&'transform'in text);assert.ok(Math.abs(text.transform[4]-79.2)<.03,`Expected72pt+7.2pt standard inset, actual ${text.transform[4]}`);}finally{await task.destroy();}
    const explicit=implicit.replace(/<a:bodyPr\b/, '<a:bodyPr lIns="91440" rIns="91440" tIns="45720" bIns="45720"');parts['ppt/slides/slide1.xml']=strToU8(explicit);const expected=await convertPptx(path,undefined,120000,undefined,zipSync(parts));
    assert.equal(byteHash(await renderPdf(actual,1,1440)),byteHash(await renderPdf(expected,1,1440)));assert.equal(byteHash(bytes),sourceHash);
    // Actual Impress conversion, with a deterministic fake native observer to
    // isolate cache/protocol projection rather than claim raster recognition.
    const helper=join(folder,'fake-native.mjs'),cache=join(folder,'cache');await import('node:fs/promises').then(fs=>fs.mkdir(cache));await writeFile(join(cache,'pptx'),'Not a directory');
    const native={version:'preview-fault',revision:3,languages:['ko-KR','en-US'],language_correction:false,ocr_performed:false,renderer:'fixture',verification:'fixture',viewport_width:960,viewport_height:540,rotation:0,width:960,height:540,render_sha256:'a'.repeat(64),lines:[]};
    await writeFile(helper,`#!${process.execPath}\nif(process.argv.includes('--info'))console.log(JSON.stringify({version:'fixture',os:'fixture',revision:3,languages:['ko-KR','en-US'],language_correction:false,font_inventory_sha256:'a'.repeat(64),font_families:['Arial']}));else{let input='';for await(const b of process.stdin)input+=b;const q=JSON.parse(input),valid=${JSON.stringify(native)};console.log(JSON.stringify({pages:q.pages.map(page=>({page,result:page===2?{...valid,width:0}:valid}))}));}`,{mode:0o755});
    const child=`import assert from 'node:assert/strict';import {readFile} from 'node:fs/promises';import {preparePptxPreview} from ${JSON.stringify(new URL('../../packages/render/pptx-preview.ts',import.meta.url).href)};import {extractPptx} from ${JSON.stringify(new URL('../../packages/ingest/pptx.ts',import.meta.url).href)};import {Page,byteHash} from ${JSON.stringify(new URL('../../packages/schema/index.ts',import.meta.url).href)};const bytes=await readFile(${JSON.stringify(path)}),pages=extractPptx(bytes,'sha256:'+byteHash(bytes)),pdf=await preparePptxPreview(${JSON.stringify(path)},bytes,pages,${JSON.stringify(cache)});assert.ok(pdf?.length);for(const page of pages){Page.parse(page);assert.ok(page.coverage_gaps.some(g=>g.reason==='optional_cache_write_failed_render_retained'));assert.equal(page.preview.input_preparation.source_sha256,byteHash(bytes));assert.equal(page.preview.input_preparation.changed_properties,4);}assert.ok(pages[0].raster);assert.equal(pages[1].raster,undefined);assert.ok(pages[1].coverage_gaps.some(g=>g.reason==='NATIVE_RESULT_SCHEMA_INVALID'));console.log('PASS preview cache isolation, specific diagnostics and per-asset input provenance');`;
    assert.match(execFileSync(process.execPath,['--import','tsx','--input-type=module','-e',child],{encoding:'utf8',env:{...process.env,DOCVER_VISION:helper},timeout:30000}),/PASS preview cache isolation/);
  }finally{await rm(folder,{recursive:true,force:true});}
});
