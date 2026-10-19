import {before,test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,readFile,writeFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
import pptxgen from 'pptxgenjs';
import {unzipSync,zipSync,strFromU8,strToU8} from 'fflate';
import {extractPptx,PPTX_TEXT_POLICY} from '../../packages/ingest/pptx.js';
import {Page,Report,SCHEMA_VERSION,SCHEMA_HASH,ENGINE_VERSION,byteHash,canonical,validBundleDecisionLog,type PageData} from '../../packages/schema/index.js';
import {createBundleDecision,applyBundleDecisions} from '../../packages/bundle/index.js';
import {similarity} from '../../packages/matching/index.js';
import {analyze} from '../../packages/engine/index.js';
import {Store} from '../../packages/storage/index.js';
import {QueryService} from '../../packages/query/index.js';
import {exportReport} from '../../packages/export/index.js';

const run=(text:string)=>'<a:r><a:t xml:space="preserve">'+text+'</a:t></a:r>';
const field=(text:string)=>'<a:fld id="{00000000-0000-0000-0000-000000000001}" type="datetime1"><a:t>'+text+'</a:t></a:fld>';
const p=(text:string)=>'<a:p>'+text+'</a:p>';
const shapeText='Before 2026-10-20 after\nLine & two\nliteral &#x1F600; actual 😀';
const noteText='Note 1\ncontinued\nSecond paragraph\n\nA & B literal &amp; C 😀';
let bytes:Uint8Array;
function replaceParagraph(xml:string,marker:string,replacement:string){
  let matches=0;
  const result=xml.replace(/<a:p(?:\s[^>]*)?>[\s\S]*?<\/a:p>/g,paragraph=>{
    if(!paragraph.includes('<a:t>'+marker+'</a:t>'))return paragraph;
    matches++;return replacement;
  });
  assert.equal(matches,1,'Fixture paragraph marker is unique: '+marker);return result;
}
before(async()=>{
  const deck=new (pptxgen as unknown as typeof pptxgen.default)();deck.layout='LAYOUT_WIDE';
  const slide=deck.addSlide();slide.addText('Shape marker',{x:1,y:.5,w:9,h:2,fontSize:24});
  slide.addTable([['Cell marker','Keep table']].map(row=>row.map(text=>({text}))),{x:1,y:3,w:9,h:1});
  slide.addText('Last marker',{x:1,y:5,w:9,h:1});slide.addNotes('Note marker');
  const parts=unzipSync(await deck.write({outputType:'nodebuffer'}) as Buffer);
  let xml=strFromU8(parts['ppt/slides/slide1.xml']);
  xml=replaceParagraph(xml,'Shape marker',p(run('Before ')+field('2026-10-20')+run(' after')+'<a:br/>'+run('Line &amp; two'))+p(run('literal &amp;#x1F600; actual &#x1F600;')));
  xml=replaceParagraph(xml,'Cell marker',p(run('Cell ')+field('100')+run(' won')));
  xml=replaceParagraph(xml,'Last marker',p(run('Last ')+field('tail')+run(' end')));
  parts['ppt/slides/slide1.xml']=strToU8(xml);
  const notePath='ppt/notesSlides/notesSlide1.xml';
  parts[notePath]=strToU8(replaceParagraph(strFromU8(parts[notePath]),'Note marker',p(run('Note ')+field('1')+'<a:br/>'+run('continued'))+p(run('Second paragraph'))+'<a:p/>'+p('<a:r><a:t>A &amp; B<![CDATA[ literal &amp; ]]>C &#x1F600;</a:t></a:r>')));
  bytes=zipSync(parts,{mtime:new Date(1980,0,1)});
});

test('PPTX retains interleaved run/field/break order and drawing/table occurrence identity',()=>{
  const original=new Uint8Array(bytes),[page]=extractPptx(bytes,'sha256:'+byteHash(bytes));Page.parse(page);
  assert.deepEqual(page.elements.map(e=>e.text),[shapeText,'Cell 100 won','Keep table','Last tail end']);
  assert.deepEqual(page.elements.map(e=>e.kind),['text','table_cell','table_cell','text']);
  assert.deepEqual(page.elements.map(e=>e.reading_order),[0,1,2,3]);
  assert.equal(page.text,[shapeText,'Cell 100 won','Keep table','Last tail end'].join('\n'));
  assert.equal(page.elements[1].table?.column,0);assert.equal(page.elements[2].table?.column,1);
  assert.deepEqual(bytes,original);assert.equal(canonical(extractPptx(bytes,page.asset_id)),canonical([page]));
});

test('PPTX notes preserve paragraph boundaries, empty lines, fields and literal CDATA entities',()=>{
  const [page]=extractPptx(bytes,'sha256:'+byteHash(bytes));assert.equal(page.notes,noteText);
  assert.ok(!page.notes!.includes('Slide number'));assert.equal(page.capabilities.notes,'available');
});

test('PPTX nested groups preserve child source order without claiming supported group geometry',()=>{
  const parts=unzipSync(bytes),path='ppt/slides/slide1.xml',xml=strFromU8(parts[path]);
  const table=xml.match(/<p:graphicFrame\b[\s\S]*?<\/p:graphicFrame>/)![0];
  const last=[...xml.matchAll(/<p:sp\b[\s\S]*?<\/p:sp>/g)].find(m=>m[0].includes('tail'))![0];
  const group='<p:grpSp><p:nvGrpSpPr><p:cNvPr id="900" name="Own synthetic group"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>'+table+last+'</p:grpSp>';
  parts[path]=strToU8(xml.replace(table,'').replace(last,'').replace('</p:spTree>',group+'</p:spTree>'));
  const [page]=extractPptx(zipSync(parts),'sha256:own-group');Page.parse(page);
  assert.deepEqual(page.elements.map(e=>e.text),[shapeText,'Cell 100 won','Keep table','Last tail end']);
  assert.ok(page.coverage_gaps.some(g=>g.reason==='unsupported_group_transform'));
});

test('empty drawing occurrences keep source order in mixed and all-empty parents',()=>{
  const parts=unzipSync(bytes),path='ppt/slides/slide1.xml',xml=strFromU8(parts[path]);
  parts[path]=strToU8(xml.replace(/<p:sp\b/,'<p:sp/><p:sp'));
  const [mixed]=extractPptx(zipSync(parts),'sha256:mixed-empty');Page.parse(mixed);
  assert.deepEqual(mixed.elements.map(e=>e.text),['',shapeText,'Cell 100 won','Keep table','Last tail end']);
  assert.equal(mixed.elements[0].kind,'shape');assert.ok(mixed.coverage_gaps.some(g=>g.reason==='layout_inheritance_or_group_transform_unsupported'));
  const allEmpty=xml.replace(/<p:sp\b[\s\S]*?<\/p:sp>/g,'<p:sp/>').replace(/<p:graphicFrame\b[\s\S]*?<\/p:graphicFrame>/g,'<p:graphicFrame/>');
  parts[path]=strToU8(allEmpty);const [empty]=extractPptx(zipSync(parts),'sha256:all-empty');Page.parse(empty);
  assert.deepEqual(empty.elements.map(e=>e.kind),['shape','unsupported','shape']);
  assert.deepEqual(empty.elements.map(e=>e.reading_order),[0,1,2]);
});

test('XML depth counts real tags rather than CDATA, comments, processing instructions or quoted delimiters',()=>{
  const parts=unzipSync(bytes),path='ppt/slides/slide1.xml',xml=strFromU8(parts[path]);
  const literal='<q>'.repeat(120)+'</fake>'.repeat(120)+'<!DOCTYPE html> <!ENTITY own "ok">';
  const paragraph=p('<a:r><a:t><![CDATA['+literal+']]></a:t></a:r>');
  const harmless='<!-- <!DOCTYPE html>'+'<fake>'.repeat(150)+'--><?own <!ENTITY own "ok"> '+ '</fake>'.repeat(150)+'?>'+ '<a:ext uri="> &lt;!-- &lt;? &lt;![CDATA["/>'.repeat(150);
  parts[path]=strToU8(xml.replace(/<a:p(?:\s[^>]*)?>[\s\S]*?<\/a:p>/,paragraph).replace('</p:spTree>',harmless+'</p:spTree>'));
  const [shallow]=extractPptx(zipSync(parts),'sha256:literal-tags');Page.parse(shallow);assert.ok(shallow.elements[0].text.startsWith(literal));
  const nested='<a:ext>'.repeat(130)+'</a:ext>'.repeat(130);
  parts[path]=strToU8(xml.replace('</p:spTree>','<![CDATA['+'</fake>'.repeat(300)+']]>'+nested+'</p:spTree>'));
  assert.throws(()=>extractPptx(zipSync(parts),'sha256:deep-real-tags'),{code:'XML_DEPTH'});
  parts[path]=strToU8(xml.replace(/<p:sld\b/,'<!DOCTYPE p:sld [<!ENTITY own "ok">]><p:sld'));
  assert.throws(()=>extractPptx(zipSync(parts),'sha256:actual-declaration'),{code:'XML_DTD'});
});

test('XML depth accepts100real levels and rejects101 with a typed limit error',()=>{
  const parts=unzipSync(bytes),path='ppt/slides/slide1.xml';
  const nested=(count:number)=>'<p:sld xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"><p:cSld><p:spTree>'+'<a:ext>'.repeat(count)+'</a:ext>'.repeat(count)+'</p:spTree></p:cSld></p:sld>';
  parts[path]=strToU8(nested(97));const pages=extractPptx(zipSync(parts),'sha256:depth100');assert.equal(pages.length,1);Page.parse(pages[0]);
  parts[path]=strToU8(nested(98));assert.throws(()=>extractPptx(zipSync(parts),'sha256:depth101'),{code:'XML_DEPTH'});
});

test('1MB malformed tags, quoted data openers and excess nesting fail within an isolated deadline',()=>{
  const extractor=new URL('../../packages/ingest/pptx.ts',import.meta.url).href;
  const program=`import assert from 'node:assert/strict';import {readFileSync} from 'node:fs';import {unzipSync,zipSync,strToU8} from 'fflate';import {extractPptx} from ${JSON.stringify(extractor)};const original=unzipSync(readFileSync(0)),bad=['<a'.repeat(500000),'<!--'.repeat(250000),...['<!--','<?','<![CDATA['].map(s=>'<p:sld xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" uri="'+s.repeat(Math.ceil(1000000/s.length))+'"/>')].map(source=>[source,'INVALID_XML']);bad.push(['<x>'.repeat(150000)+'</x>'.repeat(150000),'XML_DEPTH']);for(const [source,code]of bad){const parts={...original,'ppt/slides/slide1.xml':strToU8(source)};assert.throws(()=>extractPptx(zipSync(parts),'sha256:malformed'),{code});}console.log('All6bounded inputs rejected');`;
  const result=spawnSync(process.execPath,['--import','tsx','--input-type=module','-e',program],{input:bytes,encoding:'utf8',timeout:5000,maxBuffer:1024*1024});
  assert.ifError(result.error);assert.equal(result.status,0,result.stderr);assert.match(result.stdout,/All6bounded inputs rejected/);
});

test('changed extraction rejects stale bundle scores while old snapshots and reused observation IDs stay report-scoped',async()=>{
  const sourceAsset='sha256:'+byteHash(bytes),pdfAsset='sha256:'+'c'.repeat(64),fresh=extractPptx(bytes,sourceAsset)[0],old=structuredClone(fresh);
  // Model the independently reproduced baseline grouping without importing a
  // second parser into production or treating a new observation as old truth.
  const previous=[old.elements[0],old.elements[3],old.elements[1],old.elements[2]];
  const oldTexts=['Before  afterLine & two2026-10-20\nliteral &#x1F600; actual 😀','Last  endtail','Cell  won100','Keep table'];
  old.elements=previous.map((e,i)=>({...e,observation_id:fresh.elements[i].observation_id,reading_order:i,text:oldTexts[i],normalized_text:oldTexts[i]}));old.text=oldTexts.join('\n');
  const target:PageData={...structuredClone(fresh),page_id:'pdf_observed',asset_id:pdfAsset,elements:[],notes:null,hidden:null,source_transform:[1,0,0,-1,0,540],capabilities:{...fresh.capabilities,notes:'unavailable',hidden_slides:'unavailable'}};
  const revision={revision_id:'rev_order',revision_occurrence_id:'occ_order',label:'Own',assets:[{asset_id:sourceAsset,format:'pptx',bytes:bytes.length},{asset_id:pdfAsset,format:'pdf',bytes:100}],status:'success',pages:[old,target],coverage_gaps:[],errors:[],bundle_mapping:[],bundle_mapping_basis:[],reference_appearance_policy:'bundle-reference-v2'};
  const prior=Report.parse({schema_version:SCHEMA_VERSION,engine_version:ENGINE_VERSION,report_id:'rpt_prior_order',project_id:'prj_order_history',timeline_revision_id:'timeline_order',mapping_revision_id:'mapping_order',schema_hash:SCHEMA_HASH,observation_environment:{},revisions:[revision],matches:[],candidates:[],mapping_decisions:[],mapping_relations:[],bundle_decisions:[],lineages:[],changes:[],coverage_gaps:[]});
  const entry=createBundleDecision(prior,[],{revision_occurrence_id:'occ_order',source_asset_id:sourceAsset,rendered_asset_id:pdfAsset,source_page_id:old.page_id,rendered_page_id:target.page_id,action:'link',reason:'Prior confirmed association'});
  prior.bundle_decisions=[entry];applyBundleDecisions(prior.revisions[0],[entry],false);Report.parse(prior);const priorBody=canonical(prior);
  const changed=structuredClone(prior);changed.revisions[0].pages[0]=fresh;
  assert.notEqual(entry.score,similarity(fresh,target));assert.equal(validBundleDecisionLog(changed.revisions,[entry]),false);
  assert.throws(()=>applyBundleDecisions(changed.revisions[0],[entry],false),{code:'BUNDLE_SCORE'});
  const folder=await mkdtemp(join(tmpdir(),'docver-order-history-'));let store=new Store(folder);
  try{
    store.finishRun(store.beginRun(prior.project_id,'Old source observations'),prior);
    const current=structuredClone(prior);current.report_id='rpt_current_order';current.observation_environment.pptx_text_policy=PPTX_TEXT_POLICY;current.revisions[0].pages[0]=fresh;current.bundle_decisions=[];current.revisions[0].bundle_mapping=[];
    store.finishRun(store.beginRun(current.project_id,'New independent observations'),Report.parse(current));store.close();store=new Store(folder);
    const query=new QueryService(store,new Set([prior.project_id])),id=fresh.elements[1].observation_id;
    assert.equal(query.query('get_element',{project_id:prior.project_id,report_id:prior.report_id,observation_id:id}).items[0].text,'Last  endtail');
    assert.equal(query.query('get_element',{project_id:current.project_id,report_id:current.report_id,observation_id:id}).items[0].text,'Cell 100 won');
    assert.equal(canonical(store.report(prior.project_id,prior.report_id)),priorBody);
  }finally{store.close();await rm(folder,{recursive:true,force:true});}
});

test('ordered PPTX text policy is hash-bound and exact text survives snapshot/query/export/reopen',async()=>{
  const folder=await mkdtemp(join(tmpdir(),'docver-pptx-text-order-')),path=join(folder,'own.pptx'),storePath=join(folder,'store');
  let store=new Store(storePath);
  try{
    await writeFile(path,bytes);const before=byteHash(await readFile(path));
    const manifest={project_id:'prj_ordered_pptx',title:'Own ordered source',revisions:[{label:'v1',files:[path]}],mapping_decisions:[]};
    const report=(await analyze(manifest,folder,store,undefined,undefined,{ocr:'off',pptxPreview:false})).report;
    assert.equal(report.observation_environment.pptx_text_policy,PPTX_TEXT_POLICY);Report.parse(report);
    const repeated=(await analyze(manifest,folder,store,undefined,undefined,{ocr:'off',pptxPreview:false})).report;
    assert.equal(report.report_id,repeated.report_id);assert.equal(canonical(report),canonical(repeated));
    const originalBody=canonical(report);store.close();store=new Store(storePath);
    const saved=store.report(report.project_id,report.report_id);assert.equal(canonical(saved),originalBody);
    const query=new QueryService(store,new Set([report.project_id])),revision=saved.revisions[0],page=revision.pages[0];
    const fetched=query.query('get_page',{project_id:report.project_id,report_id:report.report_id,revision_id:revision.revision_occurrence_id,page_id:page.page_id,max_output_tokens:8000});
    assert.equal(fetched.items.map(item=>item.text).join('\n'),page.text);assert.equal(page.notes,noteText);
    const output=join(folder,'export');await exportReport(query,saved.project_id,saved.report_id,output);
    assert.equal(canonical(JSON.parse(await readFile(join(output,'report.json'),'utf8'))),originalBody);
    assert.equal(byteHash(await readFile(path)),before);
  }finally{store.close();await rm(folder,{recursive:true,force:true});}
});
