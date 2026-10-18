import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp,readFile,writeFile,rm,readdir } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join,resolve } from 'node:path';
import PDFDocument from 'pdfkit';
import pptxgen from 'pptxgenjs';
import { createCanvas } from '@napi-rs/canvas';
import { zipSync,unzipSync,strToU8 } from 'fflate';
import { extractPdf } from '../../packages/ingest/pdf.js';
import { extractPptx } from '../../packages/ingest/pptx.js';
import { recognizePdf,captureNativePages } from '../../packages/ingest/ocr.js';
import { convertPptx,validateRenderPackage } from '../../packages/render/index.js';
import { preparePptxPreview } from '../../packages/render/pptx-preview.js';
import { officeExecutable,visionExecutable,visionInfo,runTool } from '../../packages/runtime/tools.js';
import { byteHash,id,normalize,comparisonText,SCHEMA_VERSION,SCHEMA_HASH,ENGINE_VERSION,type PageData,type RevisionData,type ReportData } from '../../packages/schema/index.js';
import { matchPages } from '../../packages/matching/index.js';
import { diffRevisions } from '../../packages/diff/index.js';
import { DesktopService } from '../../packages/desktop/service.js';
import { Store } from '../../packages/storage/index.js';
import { QueryService,type QueryResult } from '../../packages/query/index.js';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';

const native={skip:process.platform!=='darwin'||!visionExecutable()};
const office={skip:!officeExecutable()};
async function pdf(draw:(d:PDFKit.PDFDocument)=>void):Promise<Buffer>{const d=new PDFDocument({size:[960,540],margin:0}),chunks:Buffer[]=[];d.on('data',b=>chunks.push(b));const done=new Promise<Buffer>(resolve=>d.on('end',()=>resolve(Buffer.concat(chunks))));draw(d);d.end();return done;}
function scan(text:string):Buffer{const c=createCanvas(1920,1080),ctx=c.getContext('2d');ctx.fillStyle='white';ctx.fillRect(0,0,c.width,c.height);ctx.fillStyle='black';ctx.font='48px AppleGothic';ctx.fillText('계약 검토 · Contract review',120,140);ctx.font='40px AppleGothic';ctx.fillText(text,120,300);return c.toBuffer('image/png');}
const scanned=(text:string)=>pdf(d=>d.image(scan(text),0,0,{width:960,height:540}));
const rev=(p:PageData,key:string):RevisionData=>({revision_id:key,revision_occurrence_id:key,label:key,assets:[{asset_id:p.asset_id,format:'pdf',bytes:0}],status:'success',pages:[p],coverage_gaps:p.coverage_gaps,errors:[],bundle_mapping:[]});
function changes(a:PageData,b:PageData){const m=matchPages([a],[b]);assert.equal(m.matches.length,1);return diffRevisions(rev(a,'v1'),rev(b,'v2'),m.matches,m.candidates,()=> 'entity');}

test('native tiled Korean/English OCR retains signs and amounts and caches exact evidence',native,async()=>{
  const folder=await mkdtemp(join(tmpdir(),'docver-ocr-test-'));
  try{
    const bytes=await scanned('금액 -1,234.50 / +1.25% / 120억'),r=await recognizePdf(bytes,1,{cacheRoot:folder});
    const text=normalize(r.lines.map(l=>l.text).join(' '));
    for(const expected of ['계약','Contract','-1,234.50','+1.25%','120억'])assert.ok(text.replace(/\s/gu,'').includes(expected),text);
    assert.equal(r.language_correction,false);assert.deepEqual(r.languages,['ko-KR','en-US']);assert.ok(r.lines.filter(l=>/[0-9]/.test(l.text)).every(l=>l.numeric_consensus),JSON.stringify(r.lines.map(l=>({text:l.text,readings:l.numeric_readings,consensus:l.numeric_consensus}))));
    const cache=join(folder,'ocr'),files=(await readdir(cache)).filter(p=>p.endsWith('.json'));let file='';for(const name of files)if(JSON.parse(await readFile(join(cache,name),'utf8')).value.ocr_performed)file=name;assert.ok(file);const original=await readFile(join(cache,file));
    assert.deepEqual(await recognizePdf(bytes,1,{cacheRoot:folder}),r);assert.deepEqual(await readFile(join(cache,file)),original);
    await writeFile(join(cache,file),'corrupt');assert.deepEqual(await recognizePdf(bytes,1,{cacheRoot:folder}),r);
  }finally{await rm(folder,{recursive:true,force:true});}
});

test('scan changes are inferred, link to raster evidence, and never invent original raw text',native,async()=>{
  const a=(await extractPdf(await scanned('예상 매출 100억'),'sha256:scan-a',{ocr:'auto'}))[0],b=(await extractPdf(await scanned('예상 매출 120억'),'sha256:scan-b',{ocr:'auto'}))[0];
  assert.equal(a.text,'');assert.equal(b.text,'');assert.equal(a.ocr?.mode,'scan');assert.ok(comparisonText(a).includes('100억'));assert.ok(comparisonText(b).includes('120억'));
  const found=changes(a,b).filter(c=>c.kind==='text_modified');assert.equal(found.length,1);assert.equal(found[0].text_assessment,'inferred');assert.ok(found[0].coverage_gaps.some(g=>g.reason==='ocr_inferred_text_requires_source_review'));assert.ok(found[0].evidence.every(e=>e.method==='vision_ocr'&&e.observation_id));
});

test('mixed raster content supplements live text without duplication or certifying hidden glyphs',native,async()=>{
  const bytes=await pdf(d=>{d.fontSize(28).text('Observed header',55,25,{lineBreak:false});d.image(scan('이미지 매출 120억'),0,100,{width:960,height:440});});
  const p=(await extractPdf(bytes,'sha256:mixed',{ocr:'auto'}))[0];
  assert.ok(p.elements.some(e=>e.method==='pdf_text'&&e.text==='Observed header'));assert.ok(p.elements.some(e=>e.method==='vision_ocr'&&e.text.includes('120억')));
  assert.equal(p.elements.filter(e=>e.text==='Observed header').length,1);assert.ok(p.text.includes('Observed header'));assert.ok(!p.text.includes('120억'));assert.equal(p.ocr?.mode,'supplement');
  const hidden=await pdf(d=>{d.image(scan('예상 매출 120억'),0,0,{width:960,height:540});d.addContent('3 Tr');d.fontSize(24).text('Revenue 999',50,80,{lineBreak:false});});
  const q=(await extractPdf(hidden,'sha256:prior',{ocr:'auto'}))[0];assert.equal(q.ocr?.mode,'scan');assert.ok(q.text.includes('999'));assert.ok(q.elements.find(e=>e.method==='pdf_text')?.visibility==='hidden_render_mode');assert.ok(comparisonText(q).includes('120억'));assert.ok(!comparisonText(q).includes('999'));
});

test('OCR agreement never clears operator strike or occlusion uncertainty',native,async()=>{
  const bytes=await pdf(d=>{d.fontSize(28).text('Revenue 1.5',50,100,{lineBreak:false});d.moveTo(50,110).lineTo(210,110).lineWidth(1).stroke('red');});
  const p=(await extractPdf(bytes,'sha256:struck',{ocr:'auto'}))[0];assert.ok(p.elements[0].visibility!=='visible');assert.ok(p.unresolved_text?.includes('Revenue'));assert.ok(p.ocr);assert.ok(p.coverage_gaps.some(g=>g.feature==='ocr_verification'));
});

test('native OCR follows rotated cropped PDF coordinates rather than guessing source boxes',native,async()=>{
  for(const rotation of [0,90,180,270]){
    const positions:Record<number,[number,number]>={0:[100,100],90:[100,400],180:[800,400],270:[800,100]};
    const bytes=await pdf(d=>{(d.page.dictionary.data as any).Rotate=rotation;(d.page.dictionary.data as any).CropBox=[20,30,940,510];const [x,y]=positions[rotation];d.save().translate(x,y).rotate(-rotation).fontSize(28).text('Revenue 123.50',0,0,{lineBreak:false}).restore();});
    const page=(await extractPdf(bytes,'sha256:rotation-'+rotation,{ocr:'all'}))[0];assert.equal(page.ocr?.status,'available');
    const rendered=await recognizePdf(bytes,1);const raw=page.elements.find(e=>e.method==='pdf_text')!,line=rendered.lines.find(l=>l.text.includes('123.50'));assert.ok(line,JSON.stringify({rotation,lines:rendered.lines}));
    const a=raw.bbox,b=line.bbox,intersection=Math.max(0,Math.min(a[0]+a[2],b[0]+b[2])-Math.max(a[0],b[0]))*Math.max(0,Math.min(a[1]+a[3],b[1]+b[3])-Math.max(a[1],b[1]));
    assert.ok(intersection/(b[2]*b[3])>0.7,JSON.stringify({rotation,raw:a,ocr:b}));assert.ok(!page.coverage_gaps.some(g=>g.reason==='native_raster_viewport_geometry_disagrees'));
  }
});

test('rendered OCR supplies inferred comparison for unsupported text paint without mutating raw uncertainty',native,async()=>{
  const make=(value:string)=>pdf(d=>{d.addContent('2 Tr');d.fontSize(28).text('Revenue '+value,70,100,{lineBreak:false});});
  const a=(await extractPdf(await make('100'),'sha256:outlined-a',{ocr:'auto'}))[0],b=(await extractPdf(await make('120'),'sha256:outlined-b',{ocr:'auto'}))[0];
  assert.ok(a.unresolved_text?.includes('100'));assert.ok(b.unresolved_text?.includes('120'));assert.equal(a.comparison_basis,'raster_ocr');
  const delta=changes(a,b).filter(c=>c.kind==='text_modified');assert.equal(delta.length,1);assert.equal(delta[0].text_assessment,'inferred');
  const duplicate={...b,raster:{...b.raster!,sha256:a.raster!.sha256},ocr:{...b.ocr!,render_sha256:a.ocr!.render_sha256}};assert.equal(changes(a,duplicate).filter(c=>c.kind==='text_modified').length,0);
});

test('a missing OCR region is a visual observation gap, never a precise numeric deletion',native,async()=>{
  const a=(await extractPdf(await scanned('예상 매출 100억'),'sha256:present',{ocr:'auto'}))[0],b=(await extractPdf(await scanned(''),'sha256:missing-region',{ocr:'auto'}))[0];
  const delta=changes(a,b);assert.equal(delta.filter(c=>c.kind==='text_modified').length,0);assert.ok(delta.some(c=>c.coverage_gaps.some(g=>g.reason==='ocr_region_missing_or_numeric_ambiguity_withheld')));assert.ok(delta.some(c=>c.kind==='visual_region_changed'&&c.evidence.every(e=>e.method==='native_raster'&&e.render_sha256)));
});

test('a supported numeric region remains comparable beside unreadable content',()=>{
  const make=(key:string,value:string):PageData=>({page_id:key,asset_id:key,page:1,width:960,height:540,coordinate_system:'normalized',source_transform:[],hidden:false,text:'Revenue '+value+'\nuncertain body',visible_text:'Revenue '+value,unresolved_text:'uncertain body',elements:[{observation_id:key,kind:'text',text:'Revenue '+value,normalized_text:'Revenue '+value,bbox:[0.1,0.1,0.3,0.08],reading_order:0,availability:'available',method:'pdf_text',source_ref:'header',provenance:'observed',visibility:'visible'}],notes:null,capabilities:{text:'available',notes:'unavailable',hidden_slides:'unavailable',animation:'unavailable',structure:'unavailable',preview:'available'},coverage_gaps:[{feature:'pdf_visibility',reason:'unknown_body'}]});
  const delta=changes(make('a','100'),make('b','120')),numeric=delta.filter(c=>c.kind==='text_modified');assert.equal(numeric.length,1);assert.equal(numeric[0].text_scope,'region');assert.equal(numeric[0].text_assessment,'observed');assert.equal(numeric[0].before,'Revenue 100');assert.ok(delta.some(c=>c.kind==='coverage_gap'));
});

test('rasterized strike is inferred from pixels while underline stays readable',native,async()=>{
  const line=(strike:boolean,underline=false)=>pdf(d=>{const c=createCanvas(1920,1080),ctx=c.getContext('2d');ctx.fillStyle='white';ctx.fillRect(0,0,1920,1080);ctx.font='48px Arial';ctx.fillStyle='black';ctx.fillText('Revenue 100',120,300);if(strike){ctx.strokeStyle='red';ctx.lineWidth=3;ctx.beginPath();ctx.moveTo(120,underline?315:282);ctx.lineTo(420,underline?315:282);ctx.stroke();}d.image(c.toBuffer('image/png'),0,0,{width:960,height:540});});
  const a=(await extractPdf(await line(false),'sha256:clean',{ocr:'auto'}))[0],b=(await extractPdf(await line(true),'sha256:raster-strike',{ocr:'auto'}))[0],u=(await extractPdf(await line(true,true),'sha256:underline',{ocr:'auto'}))[0];
  assert.ok(b.elements.some(e=>e.visibility==='struck_inferred'&&e.visibility_evidence?.some(v=>v.method==='raster_horizontal_strike_candidate')),JSON.stringify(b.elements));assert.ok(!u.elements.some(e=>e.visibility==='struck_inferred'));assert.ok(changes(a,b).some(c=>c.kind==='text_struck_through'&&c.appearance_assessment==='inferred'));
});

test('native batches distinguish OCR and render-only and changed evidence excludes stable numbers',native,async()=>{
  const bytes=await pdf(d=>{d.fontSize(24).text('Revenue 500',50,70,{lineBreak:false});d.text('Cost 100',50,150,{lineBreak:false});}),observations=await captureNativePages(bytes,[1],[]);
  assert.equal(observations.get(1)?.ocr_performed,false);assert.equal(observations.get(1)?.lines.length,0);
  const a=(await extractPdf(bytes,'sha256:cost-a',{ocr:'auto'}))[0],b=(await extractPdf(await pdf(d=>{d.fontSize(24).text('Revenue 500',50,70,{lineBreak:false});d.text('Cost 120',50,150,{lineBreak:false});}),'sha256:cost-b',{ocr:'auto'}))[0];
  const delta=changes(a,b).find(c=>c.kind==='text_modified')!;assert.ok(delta);assert.deepEqual(delta.evidence.map(e=>e.quote),['Cost 100','Cost 120']);
});

test('native page lookup reads its transactional index without parsing a full report',native,async()=>{
  const folder=await mkdtemp(join(tmpdir(),'docver-index-')),service=new DesktopService(join(folder,'library'));
  try{const file=join(folder,'source.pdf');await writeFile(file,await pdf(d=>d.fontSize(24).text('Indexed page 123',50,80)));const project=await service.create('Index',[{label:'v1',files:[file]}]);const {report}=await service.run(project.project_id);const p=report.revisions[0].pages[0];
    service.store.report=()=>{throw new Error('Full report load must not be called')};const result=service.pageData(project.project_id,report.report_id,p.page_id);assert.equal(result.page.page_id,p.page_id);assert.equal(result.page.text,p.text);assert.ok(result.page.raster);
    assert.equal(service.store.db.prepare('SELECT count(*) AS n FROM native_pages WHERE report_id=?').get(report.report_id)?.n,1);
  }finally{service.close();await rm(folder,{recursive:true,force:true});}
});

test('OCR alternative evidence is complete, bounded and keeps emoji across chunk boundaries',native,async()=>{
  const folder=await mkdtemp(join(tmpdir(),'docver-ocr-chunks-')),service=new DesktopService(join(folder,'library'));
  try{const file=join(folder,'source.pdf');await writeFile(file,await pdf(d=>d.fontSize(24).text('Contract evidence',50,80)));const project=await service.create('OCR chunks',[{label:'v1',files:[file]}]);const result=await service.run(project.project_id,undefined,undefined,false),report=result.report,e=report.revisions[0].pages[0].elements[0];
    const alternative=('한글 대안 😀 금액 ').repeat(600)+' -1,234.56 끝  ';e.method='vision_ocr';e.provenance='inferred';e.ocr={confidence:0.5,confidence_scope:'line',numeric_consensus:false,ambiguous:true,alternatives:[{text:e.text,confidence:0.5,truncated:false},{text:alternative,confidence:0.4,truncated:false}]};report.report_id=id('rpt',['constructed-contract-fixture',report]);service.commit(project.project_id,result);
    const query=service.queryService(project.project_id);let restored='',offset:number|null=0;
    while(offset!==null){const response=query.query('get_element',{project_id:project.project_id,report_id:report.report_id,observation_id:e.observation_id,text_length:1,ocr_alternative_index:1,ocr_alternative_offset:offset,ocr_alternative_length:701,max_output_tokens:8000});assert.ok(Buffer.byteLength(JSON.stringify(response))<=8000);const value=response.items[0].ocr_alternative as {text:string;next_text_offset:number|null};assert.ok(!/[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]/.test(value.text));restored+=value.text;offset=value.next_text_offset;}
    assert.equal(restored,alternative);assert.ok(service.store.report(project.project_id,report.report_id).revisions[0].pages[0].elements[0].ocr?.alternatives[1].text===alternative);
    const database=join(service.root,'docver.sqlite'),before=byteHash(await readFile(database)),client=new Client({name:'ocr-evidence-test',version:'1.0.0'}),transport=new StdioClientTransport({command:process.execPath,args:['--import','tsx',resolve('apps/mcp/main.ts'),'--store',service.root,'--project',project.project_id],stderr:'pipe'});
    try{await client.connect(transport);let mcpText='',next:number|null=0;while(next!==null){const response=await client.callTool({name:'get_element',arguments:{project_id:project.project_id,report_id:report.report_id,observation_id:e.observation_id,text_length:1,ocr_alternative_index:1,ocr_alternative_offset:next,ocr_alternative_length:200,max_output_tokens:8000}});assert.notEqual(response.isError,true);assert.ok(Buffer.byteLength(JSON.stringify(response))<=8000);const row=(response.structuredContent as QueryResult).items[0].ocr_alternative as {text:string;next_text_offset:number|null};assert.ok(row);mcpText+=row.text;next=row.next_text_offset;}assert.equal(mcpText,alternative);}finally{await client.close();}assert.equal(byteHash(await readFile(database)),before);
  }finally{service.close();await rm(folder,{recursive:true,force:true});}
});

test('OOXML entity decoding preserves literal character references and actual Unicode separately',async()=>{
  const deck=new (pptxgen as unknown as typeof pptxgen.default)();deck.addSlide().addText('literal &#x1F600; and actual 😀',{x:1,y:1,w:8,h:1});const bytes=await deck.write({outputType:'nodebuffer'}) as Buffer;
  const text=extractPptx(bytes,'sha256:entities')[0].text;assert.equal(text,'literal &#x1F600; and actual 😀');
});

test('historical range queries retain their engine instead of silently adopting new regional inference',async()=>{
  const folder=await mkdtemp(join(tmpdir(),'docver-legacy-range-')),store=new Store(folder);
  try{const make=(value:string)=>pdf(d=>{d.fontSize(24).text('Revenue '+value,50,70,{lineBreak:false});d.addContent('2 Tr');d.text('Uncertain body',50,180,{lineBreak:false});}),a=(await extractPdf(await make('100'),'sha256:legacy-a'))[0],b=(await extractPdf(await make('120'),'sha256:legacy-b'))[0];
    let snapshot:ReportData={schema_version:SCHEMA_VERSION,engine_version:'0.1.0-native.1',report_id:'rpt_legacy',project_id:'prj_legacy',timeline_revision_id:'timeline_test',mapping_revision_id:'mapping_test',schema_hash:SCHEMA_HASH,observation_environment:{fixture:'historical-contract'},revisions:[rev(a,'v1'),rev(b,'v2')],matches:[{from_page_id:a.page_id,to_page_id:b.page_id,score:1,status:'inferred',reasons:['fixture']}],candidates:[],mapping_decisions:[],lineages:[{entity_id:'entity',page_ids:[a.page_id,b.page_id],status:'inferred'}],changes:[],coverage_gaps:[]};
    const q=new QueryService(store,new Set(['prj_legacy']),()=>snapshot),args={project_id:'prj_legacy',report_id:'rpt_legacy',mode:'range_net',from:'v1',to:'v2'};
    assert.equal(q.changeSet(args).filter(c=>c.kind==='text_modified').length,0);snapshot={...snapshot,engine_version:ENGINE_VERSION};assert.equal(q.changeSet(args).filter(c=>c.kind==='text_modified'&&c.text_scope==='region').length,1);
    snapshot={...snapshot,engine_version:'unknown historical engine'};assert.throws(()=>q.changeSet(args),{code:'ENGINE_VERSION_UNAVAILABLE'});assert.deepEqual(q.changeSet({...args,mode:'history'}),[]);
  }finally{store.close();await rm(folder,{recursive:true,force:true});}
});

test('raster document tables retain inferred rows, columns and original-source distinction',native,async(t)=>{
  if(!(await visionInfo())?.document_structure){t.skip('Document structure requires macOS26+');return;}
  const c=createCanvas(1600,1000),ctx=c.getContext('2d');ctx.fillStyle='white';ctx.fillRect(0,0,1600,1000);ctx.strokeStyle='black';ctx.lineWidth=3;
  for(const x of [100,700,1300]){ctx.beginPath();ctx.moveTo(x,150);ctx.lineTo(x,750);ctx.stroke();}for(const y of [150,350,550,750]){ctx.beginPath();ctx.moveTo(100,y);ctx.lineTo(1300,y);ctx.stroke();}
  ctx.fillStyle='black';ctx.font='44px AppleGothic';for(const [text,x,y] of [['분기',140,260],['매출',740,260],['Q1',140,460],['100',740,460],['Q2',140,660],['120',740,660]] as [string,number,number][])ctx.fillText(text,x,y);
  const bytes=await pdf(d=>d.image(c.toBuffer('image/png'),0,0,{width:960,height:540})),p=(await extractPdf(bytes,'sha256:table-scan',{ocr:'auto'}))[0];
  assert.equal(p.ocr?.structure_status,'available');assert.ok((p.ocr?.table_count??0)>=1);const cells=p.elements.filter(e=>e.table?.origin==='vision_table_inferred');assert.ok(cells.some(e=>e.text.includes('100'))&&cells.some(e=>e.text.includes('120')));assert.ok(cells.every(e=>e.provenance==='inferred'&&e.table?.assessment==='inferred'));
});

test('render safety rejects unused external and nested workbook relationships before conversion',()=>{
  const external=strToU8('<Relationships><Relationship TargetMode="External" Target="http://127.0.0.1/private"/></Relationships>');
  assert.throws(()=>validateRenderPackage(zipSync({'unused/_rels/link.rels':external})),{code:'EXTERNAL_RELATIONSHIP'});
  assert.throws(()=>validateRenderPackage(zipSync({'unused/_rels/link.rels':strToU8('<Relationships><Relationship TargetMode="Exte&#114;nal" Target="f&#105;le:///private/picture.png"/></Relationships>')})),{code:'EXTERNAL_RELATIONSHIP'});
  assert.doesNotThrow(()=>validateRenderPackage(zipSync({'unused/_rels/link.rels':strToU8('<Relationships><Relationship Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink" TargetMode="External" Target="https://example.test/"/></Relationships>')})));
  const xlsx=zipSync({'xl/_rels/workbook.xml.rels':external});assert.throws(()=>validateRenderPackage(zipSync({'ppt/embeddings/test.xlsx':xlsx})),{code:'EXTERNAL_RELATIONSHIP'});
  assert.throws(()=>validateRenderPackage(zipSync({'ppt/embeddings/oleObject1.bin':new Uint8Array([0])})),{code:'ACTIVE_CONTENT'});
});

test('real LibreOffice preserves hidden slide indexes, renders objects and normalizes volatile metadata',office,async()=>{
  const folder=await mkdtemp(join(tmpdir(),'docver-office-test-'));
  try{
    const deck=new (pptxgen as unknown as typeof pptxgen.default)();deck.layout='LAYOUT_WIDE';
    for(let n=1;n<=5;n++){const slide=deck.addSlide();slide.hidden=n===2||n===4;slide.addText('한글 계약 '+n,{x:1,y:0.5,w:8,h:1,fontFace:'AppleGothic',fontSize:24});slide.addTable([['분기','매출'],['Q1',String(n*100)]].map(row=>row.map(text=>({text}))),{x:1,y:2,w:5,h:1,fontFace:'AppleGothic'});slide.addImage({data:'image/png;base64,'+scan('이미지').toString('base64'),x:7,y:2,w:4,h:2});}
    const bytes=await deck.write({outputType:'nodebuffer'}) as Buffer,path=join(folder,'한글 deck.pptx');await writeFile(path,bytes);
    const pages=extractPptx(bytes,'sha256:'+byteHash(bytes));assert.deepEqual(pages.filter(p=>p.hidden).map(p=>p.page),[2,4]);
    const first=await preparePptxPreview(path,bytes,pages,join(folder,'cache'));assert.ok(first);assert.equal(pages.length,5);assert.ok(pages.every(p=>p.preview?.page===p.page&&p.capabilities.preview==='available'));assert.ok(pages.every(p=>!p.preview?.warnings.some(w=>w.startsWith('rendered_text_differs'))));
    const second=await convertPptx(path);assert.equal(byteHash(first),byteHash(second));
    const rendered=await extractPdf(first,'sha256:derived');assert.equal(rendered.length,5);for(let i=0;i<5;i++)assert.ok(rendered[i].text.includes(String(i+1)),rendered[i].text);
    const missing=unzipSync(bytes);missing['ppt/slides/slide1.xml']=strToU8(new TextDecoder().decode(missing['ppt/slides/slide1.xml']).replaceAll('AppleGothic','Docver Missing Font'));
    const altered=zipSync(missing),file2=join(folder,'missing.pptx');await writeFile(file2,altered);const alteredPages=extractPptx(altered,'sha256:missing');await preparePptxPreview(file2,altered,alteredPages,join(folder,'cache'));
    assert.ok(alteredPages[0].preview?.warnings.some(w=>w==='font_substitution_possible:Docver Missing Font'));
  }finally{await rm(folder,{recursive:true,force:true});}
});

test('native subprocess timeout terminates the complete process group',async()=>{
  const folder=await mkdtemp(join(tmpdir(),'docver-tool-test-'));
  try{const file=join(folder,'pid'),script='import os,time,signal; p=os.fork(); signal.signal(signal.SIGTERM,signal.SIG_IGN) if not p else open('+JSON.stringify(file)+',"w").write(str(p)); time.sleep(30)';
    await assert.rejects(runTool('/usr/bin/python3',['-c',script],{timeout:1500}),{code:'TOOL_TIMEOUT'});
    const pid=Number(await readFile(file,'utf8'));assert.throws(()=>process.kill(pid,0),{code:'ESRCH'});
  }finally{await rm(folder,{recursive:true,force:true});}
});
