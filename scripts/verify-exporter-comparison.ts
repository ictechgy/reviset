import assert from 'node:assert/strict';
import {readFile,writeFile,mkdir,readdir} from 'node:fs/promises';
import {resolve,join} from 'node:path';
import {createHash} from 'node:crypto';
import PDFDocument from 'pdfkit';
import {extractPdf} from '../packages/ingest/pdf.js';
import {extractPptx} from '../packages/ingest/pptx.js';
import {matchPages} from '../packages/matching/index.js';
import {diffRevisions} from '../packages/diff/index.js';
import {byteHash,ENGINE_VERSION,comparisonText,normalize,type PageData,type RevisionData,type MatchData} from '../packages/schema/index.js';

// Local, pinned fixture replay. No downloads, renderer launch, or OCR is needed.
// Document strings are written only to the caller-selected private evidence folder.
const corpus=resolve(process.argv[2]??'output/office-reference');
const convertedRun=resolve(process.argv[3]??join(corpus,'runs/342a89d3'));
const out=resolve(process.argv[4]??'.omx/artifacts/pdf-exporter-hardening-20261023/replay-01');
await mkdir(out,{recursive:true});
const manifestBytes=await readFile(join(corpus,'manifest.json'));
if(byteHash(manifestBytes)!=='4209c193deb0e6f24a2806aa152395364e558e131b0bd3419e0151cae636bd19')throw new Error('Pinned manifest hash mismatch');
const manifest=JSON.parse(manifestBytes.toString());
const previous=JSON.parse(await readFile(join(convertedRun,'result.json'),'utf8'));
const digest=(value:unknown)=>createHash('sha256').update(JSON.stringify(value)).digest('hex');
async function sourceSnapshot(){
  const paths=[...await readdir('packages',{recursive:true})].filter(path=>path.endsWith('.ts')).map(path=>join('packages',path));
  paths.push('scripts/verify-exporter-comparison.ts');paths.sort();
  return Object.fromEntries(await Promise.all(paths.map(async path=>[path,byteHash(await readFile(path))])));
}
const sourceBefore=await sourceSnapshot();
const compact=(text:string)=>normalize(text).replace(/\s/gu,'');
const revision=(pages:PageData[],key:string):RevisionData=>({revision_id:'rev_'+key,revision_occurrence_id:'occ_'+key,label:key,assets:[{asset_id:pages[0].asset_id,format:'pdf',bytes:0}],status:'success',pages,coverage_gaps:[],errors:[],bundle_mapping:[]});
const summarize=(changes:ReturnType<typeof diffRevisions>)=>({kinds:Object.fromEntries([...new Set(changes.map(c=>c.kind))].map(kind=>[kind,changes.filter(c=>c.kind===kind).length])),gaps:[...new Set(changes.flatMap(c=>c.coverage_gaps.map(g=>g.reason)))],changes});
async function controlledPdf(value:string,split=false):Promise<Buffer>{
  const pdf=new PDFDocument({size:[600,400],margin:0,compress:false,info:{Title:'Locally authored exporter comparison control',CreationDate:new Date('2026-01-01T00:00:00Z'),ModDate:new Date('2026-01-01T00:00:00Z')}}),chunks:Buffer[]=[];
  const result=new Promise<Buffer>((done,fail)=>{pdf.on('data',chunk=>chunks.push(Buffer.from(chunk)));pdf.on('end',()=>done(Buffer.concat(chunks)));pdf.on('error',fail);});
  pdf.font('Helvetica').fontSize(20);
  if(split)pdf.text('Revenue ',60,100,{continued:true}).font('Helvetica-Bold').text(value);
  else pdf.text('Revenue '+value,60,100);
  pdf.end();return result;
}
const rows=[];
for(const item of manifest.cases.filter((c:any)=>c.format==='pptx')){
  if(!/^[a-z0-9-]+$/.test(item.id)||[item.source,item.expected_pdf].some(path=>typeof path!=='string'||path.split('/').includes('..')))throw new Error('Unsafe manifest path');
  const [source,reference,converted]=await Promise.all([readFile(join(corpus,item.source)),readFile(join(corpus,item.expected_pdf)),readFile(join(convertedRun,item.id,'converted.pdf'))]);
  if(byteHash(source)!==item.source_sha256||byteHash(reference)!==item.expected_sha256)throw new Error('Pinned original mismatch: '+item.id);
  const sourcePages=extractPptx(source,'sha256:'+byteHash(source));
  const expected=await extractPdf(reference,'sha256:'+byteHash(reference),{ocr:'off'}),actual=await extractPdf(converted,'sha256:'+byteHash(converted),{ocr:'off'});
  if(expected.length!==item.expected_pages||actual.length!==item.expected_pages)throw new Error('Page count mismatch');
  if(sourcePages.length!==expected.length)throw new Error('Ordinal qualification requires source slide and PDF page counts to match');
  const matched=matchPages(expected,actual),forced:MatchData[]=expected.map((p,i)=>({from_page_id:p.page_id,to_page_id:actual[i].page_id,score:1,status:'human_confirmed',reasons:['qualification_same_pptx_known_page_ordinal']}));
  const before=revision(expected,'powerpoint_'+item.id),after=revision(actual,'libreoffice_'+item.id);
  const auto=summarize(diffRevisions(before,after,matched.matches,matched.candidates,()=> 'family'));
  const ordinal=summarize(diffRevisions(before,after,forced,[],()=> 'family'));
  const pages=expected.map((p,i)=>({page:i+1,source_compact:compact(sourcePages[i].text),reference_compact:compact(p.text),converted_compact:compact(actual[i].text),reference_comparison:comparisonText(p),converted_comparison:comparisonText(actual[i]),compact_equal:compact(p.text)===compact(actual[i].text),source_reference_equal:compact(sourcePages[i].text)===compact(p.text),source_converted_equal:compact(sourcePages[i].text)===compact(actual[i].text),reference_elements:p.elements.length,converted_elements:actual[i].elements.length,reference_visibility:Object.fromEntries([...new Set(p.elements.map(e=>e.visibility))].map(v=>[v??'undefined',p.elements.filter(e=>e.visibility===v).length])),converted_visibility:Object.fromEntries([...new Set(actual[i].elements.map(e=>e.visibility))].map(v=>[v??'undefined',actual[i].elements.filter(e=>e.visibility===v).length]))}));
  const row={id:item.id,pages:expected.length,source_sha256:byteHash(source),reference_sha256:byteHash(reference),converted_sha256:byteHash(converted),auto_matches:matched.matches.length,auto_candidates:matched.candidates.length,auto,ordinal,page_assessments:pages};
  await writeFile(join(out,item.id+'.json'),JSON.stringify({...row,reference_pages:expected,converted_pages:actual},null,2));
  rows.push({...row,auto:{kinds:auto.kinds,gaps:auto.gaps},ordinal:{kinds:ordinal.kinds,gaps:ordinal.gaps}});
  console.log(JSON.stringify({id:item.id,pages:expected.length,auto_matches:matched.matches.length,auto_kinds:auto.kinds,ordinal_kinds:ordinal.kinds,compact_equal_pages:pages.filter(p=>p.compact_equal).length}));
}
const controls=[];
for(const spec of [{id:'split-same-number',before:'100',after:'100',splitBefore:false,splitAfter:true,expectEdit:false},{id:'numeric-edit',before:'100',after:'101',splitBefore:false,splitAfter:false,expectEdit:true},{id:'numeric-edit-with-split',before:'100',after:'101',splitBefore:false,splitAfter:true,expectEdit:true},{id:'numeric-token-boundary',before:'1 00',after:'100',splitBefore:false,splitAfter:false,expectEdit:true}]){
  const left=await controlledPdf(spec.before,spec.splitBefore),right=await controlledPdf(spec.after,spec.splitAfter);
  await writeFile(join(out,'control-'+spec.id+'-before.pdf'),left);await writeFile(join(out,'control-'+spec.id+'-after.pdf'),right);
  const a=await extractPdf(left,'sha256:'+byteHash(left),{ocr:'off'}),b=await extractPdf(right,'sha256:'+byteHash(right),{ocr:'off'}),matched=matchPages(a,b);
  const changes=summarize(diffRevisions(revision(a,'control_before_'+spec.id),revision(b,'control_after_'+spec.id),[{from_page_id:a[0].page_id,to_page_id:b[0].page_id,score:1,status:'human_confirmed',reasons:['locally_authored_control']}],[],()=> 'family'));
  const row={...spec,scope:'Locally authored PDFKit controls, actual PDF bytes parsed, ordinal association known',before_sha256:byteHash(left),after_sha256:byteHash(right),auto_matches:matched.matches.length,reference_pages:a,converted_pages:b,...changes};
  controls.push(row);await writeFile(join(out,'control-'+spec.id+'.json'),JSON.stringify(row,null,2));console.log(JSON.stringify({control:spec.id,expect_edit:spec.expectEdit,kinds:changes.kinds}));
}
const sourceAfter=await sourceSnapshot();assert.deepEqual(sourceAfter,sourceBefore,'Production or harness source changed during qualification');
const qualification={engine:ENGINE_VERSION,source_snapshot:sourceBefore,source_snapshot_sha256:digest(sourceBefore),source_unchanged:true,manifest_sha256:byteHash(manifestBytes),upstream_commit:'faeca2bc29598744a62f787076d9e340e5095b8b',converted_source_head:previous.head,converted_engine:previous.engine,converted_run:convertedRun,scope:'Existing independent upstream-declared PowerPoint and previous LibreOffice outputs; current PDF extraction and diff; OCR off; source PPTX bytes identical; forced ordinal associations isolate representation effects and are qualification-only',case_count:rows.length,page_count:rows.reduce((n,r)=>n+r.pages,0),rows,rows_sha256:digest(rows),controls:controls.map(({reference_pages,converted_pages,changes,...row})=>row)};
await writeFile(join(out,'qualification.json'),JSON.stringify(qualification,null,2));
if(process.argv.includes('--require-no-representation-edits')){
  assert.equal(rows.length,10);assert.equal(qualification.page_count,26);
  for(const row of rows){assert.equal(row.auto_matches,row.pages);assert.equal(row.auto.kinds.text_modified??0,0,row.id+' automatic representation-only text edit');assert.equal(row.ordinal.kinds.text_modified??0,0,row.id+' ordinal representation-only text edit');}
  for(const control of controls)assert.equal((control.kinds.text_modified??0)>0,control.expectEdit,control.id+' edit preservation');
  await writeFile(join(out,'regression-gate.json'),JSON.stringify({passed:true,public_decks:10,public_pages:26,false_text_edits:0,real_pdf_controls:4,source_snapshot_sha256:qualification.source_snapshot_sha256},null,2));
}
