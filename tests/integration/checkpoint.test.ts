import { test, before, after } from 'node:test';
import { execFileSync } from 'node:child_process';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, writeFile, rm, mkdir, chmod } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, dirname, resolve } from 'node:path';
import { unzipSync, zipSync, strFromU8, strToU8 } from 'fflate';
import PDFDocument from 'pdfkit';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';
import { generateFixtures, makePptx, makePdf } from '../../scripts/generate-fixtures.js';
import { scenarios } from '../ground-truth/scenarios.js';
import { Store } from '../../packages/storage/index.js';
import { analyze } from '../../packages/engine/index.js';
import { Manifest, FixtureMetadata, Report, Bbox, canonical, byteHash, type ReportData } from '../../packages/schema/index.js';
import { QueryService, type QueryName, type QueryResult } from '../../packages/query/index.js';
import { exportReport } from '../../packages/export/index.js';
import { ingest } from '../../packages/ingest/index.js';
import { extractPptx } from '../../packages/ingest/pptx.js';
import { renderPdf, convertPptx } from '../../packages/render/index.js';
let root:string,store:Store,paths:string[];
const reports=new Map<string,ReportData>();
before(async()=>{
  root=await mkdtemp(join(tmpdir(),'docver-tests-'));paths=await generateFixtures(join(root,'fixtures'));store=new Store(join(root,'store'));
  for(const path of paths) {const manifest=Manifest.parse(JSON.parse(await readFile(path,'utf8')));reports.set(manifest.title,(await analyze(manifest,dirname(path),store)).report);}
});
after(async()=>{store?.close();if(root)await rm(root,{recursive:true,force:true});});
for(const scenario of scenarios) test(`ground truth: ${scenario.name}`,async()=>{
  const r=reports.get(scenario.name)!;assert.ok(Report.safeParse(r).success);
  assert.equal(r.revisions.length,scenario.versions.length);assert.ok(r.revisions.every(v=>v.status==='success'));
  const numeric=r.changes.filter(c=>c.kind==='text_modified'&&c.before?.includes('매출 전망'));
  if(scenario.expected.revenue.length) {
    assert.deepEqual(numeric.map(c=>c.before!.match(/예상 매출 (.*?)억/)![1]),scenario.expected.revenue.slice(0,-1).filter((v,i)=>v!==scenario.expected.revenue[i+1]));
    assert.deepEqual(numeric.map(c=>c.after!.match(/예상 매출 (.*?)억/)![1]),scenario.expected.revenue.slice(1).filter((v,i)=>v!==scenario.expected.revenue[i]));
    assert.equal(new Set(numeric.map(c=>c.entity_id)).size,1);
    for(const c of numeric) for(const e of c.evidence){Bbox.parse(e.bbox);assert.notDeepEqual(e.bbox,[0,0,1,1]);assert.ok(e.quote.includes('매출'));assert.ok(e.observation_id);}
  }
  if(scenario.expected.temporary) {
    assert.equal(r.changes.filter(c=>c.kind==='page_added'&&c.after?.includes('일회성 실험')).length,1);
    assert.equal(r.changes.filter(c=>c.kind==='page_deleted'&&c.before?.includes('일회성 실험')).length,1);
    assert.ok(r.changes.some(c=>c.kind==='page_moved'&&c.entity_id===numeric[0].entity_id));
  }
  if(scenario.expected.ambiguity) assert.ok(r.candidates.some(c=>c.status==='needs_review'));
  if(scenario.expected.hidden) {
    assert.equal(r.changes.filter(c=>['page_added','page_deleted'].includes(c.kind)&&((c.before??'')+(c.after??'')).includes('비공개 부록')).length,0);
    const hiddenIds=r.revisions.flatMap(v=>v.pages.filter(p=>p.hidden).map(p=>p.page_id));
    assert.equal(r.lineages.filter(l=>hiddenIds.some(p=>l.page_ids.includes(p))).length,1);
    assert.ok(r.changes.some(c=>c.coverage_gaps.some(g=>g.reason==='not_observed_in_export')));
  }
  if(scenario.expected.scan){const scanPages=r.revisions.flatMap(v=>v.pages).filter(p=>p.ocr?.mode==='scan');assert.ok(scanPages.length>0);assert.ok(scanPages.some(p=>p.ocr?.status==='available'&&p.ocr_text?.includes('120')));assert.ok(r.coverage_gaps.some(g=>g.reason==='no_text_layer_ocr_not_run'||g.feature==='ocr'));assert.ok(numeric.every(c=>c.text_assessment==='inferred'&&c.coverage_gaps.some(g=>g.reason==='ocr_inferred_text_requires_source_review')));}
  if(scenario.expected.inconsistent){assert.ok(r.coverage_gaps.some(g=>g.reason==='bundle_inconsistent'));assert.equal(r.revisions[0].bundle_mapping.length,2);}
  assert.equal(r.changes.filter(c=>c.kind==='page_deleted'&&c.lineage.reasons.some(x=>x.includes('notes'))).length,0);
});
test('single-file inputs and source bytes preserved; generated assets deterministic',async()=>{
  for(const path of paths) {
    const metadata=FixtureMetadata.parse(JSON.parse(await readFile(join(dirname(path),'fixture.json'),'utf8')));
    for(const [file,hash] of Object.entries(metadata.assets))assert.equal('sha256:'+byteHash(await readFile(join(dirname(path),file))),hash);
  }
  const spec=scenarios[0].versions[0].slides;
  assert.equal(byteHash(await makePptx(spec)),byteHash(await makePptx(spec)));
  assert.equal(byteHash(await makePdf(spec)),byteHash(await makePdf(spec)));
});
test('same canonical conditions reuse snapshot; new run IDs; reorder creates a new snapshot',async()=>{
  const path=paths[0],input=Manifest.parse(JSON.parse(await readFile(path,'utf8'))),original=reports.get('forward')!;
  const a=await analyze(input,dirname(path),store),b=await analyze(input,dirname(path),store);
  assert.equal(a.report.report_id,original.report_id);assert.equal(canonical(a.report),canonical(b.report));assert.notEqual(a.analysis_run_id,b.analysis_run_id);
  const relocated=join(root,'relocated');await mkdir(relocated);
  const renamed={...input,revisions:await Promise.all(input.revisions.map(async(v,i)=>({...v,files:await Promise.all(v.files.map(async(f,n)=>{const name=`alias-${i}-${n}.${f.split('.').at(-1)}`;await writeFile(join(relocated,name),await readFile(join(dirname(path),f)));return name;}))})))};
  assert.equal((await analyze(renamed,relocated,store)).report.report_id,original.report_id);
  const reordered=await analyze({...input,revisions:[...input.revisions].reverse()},dirname(path),store);
  assert.notEqual(reordered.report.report_id,original.report_id);assert.equal(store.report(input.project_id,original.report_id).report_id,original.report_id);
});
test('manual mapping decisions supersede inference in a new immutable report',async()=>{
  const path=paths[0],input=Manifest.parse(JSON.parse(await readFile(path,'utf8'))),original=reports.get('forward')!,m=original.matches[0];
  const result=await analyze({...input,mapping_decisions:[{from_page_id:m.from_page_id,to_page_id:m.to_page_id,action:'link',reason:'synthetic reviewer confirms content'}]},dirname(path),store);
  assert.notEqual(result.report.report_id,original.report_id);assert.ok(result.report.matches.some(x=>x.from_page_id===m.from_page_id&&x.status==='human_confirmed'));
  assert.equal(store.report(input.project_id,original.report_id).mapping_decisions.length,0);
  await assert.rejects(analyze({...input,mapping_decisions:[{from_page_id:'pg_unknown',to_page_id:m.to_page_id,action:'link',reason:'invalid'}]},dirname(path),store),{code:'MAPPING_NOT_FOUND'});
});
test('history keeps temporary events; range_net reports only endpoint changes',()=>{
  const r=reports.get('lifecycle-five')!,q=new QueryService(store,new Set([r.project_id])),common={project_id:r.project_id,report_id:r.report_id,max_output_tokens:8000};
  const rows=all(q,'list_changes',{...common,mode:'history'});assert.equal(rows.filter((c:any)=>['page_added','page_deleted'].includes(c.kind)).length,2);
  const net=all(q,'list_changes',{...common,mode:'range_net',from:r.revisions[0].revision_occurrence_id,to:r.revisions.at(-1)!.revision_occurrence_id});
  assert.equal(net.filter((c:any)=>['page_added','page_deleted'].includes(c.kind)).length,0);
  assert.equal(net.filter((c:any)=>c.kind==='text_modified').length,1);
});
function all(q:QueryService,name:QueryName,args:Record<string,unknown>):any[] {
  const rows:any[]=[];let cursor:string|undefined;
  for(let i=0;i<1000;i++) {const r=q.query(name,{...args,...(cursor?{cursor}:{})});rows.push(...r.items);if(!r.next_cursor)return rows;cursor=r.next_cursor;}
  throw new Error('Cursor did not terminate');
}
test('query/export parity; page → element → evidence; cursor report/query binding and latest pinning',async()=>{
  const r=reports.get('forward')!,q=new QueryService(store,new Set([r.project_id])),scope={project_id:r.project_id,report_id:r.report_id,max_output_tokens:8000};
  const rows=all(q,'list_changes',{...scope,limit:1});assert.deepEqual(rows.map(c=>c.change_id),r.changes.map(c=>c.change_id));
  assert.equal(new Set(rows.map(c=>c.change_id)).size,rows.length);
  const first=q.query('list_changes',{...scope,limit:1});
  assert.throws(()=>q.query('list_changes',{...scope,report_id:store.report(r.project_id,'latest').report_id,cursor:first.next_cursor}),{code:'CURSOR_REPORT_MISMATCH'});
  assert.throws(()=>q.query('list_changes',{...scope,kind:'text_modified',cursor:first.next_cursor}),{code:'CURSOR_QUERY_MISMATCH'});
  const latest=q.query('list_changes',{project_id:r.project_id,report_id:'latest',limit:1,max_output_tokens:8000});
  assert.doesNotThrow(()=>q.query('list_changes',{project_id:r.project_id,report_id:latest.report_id,cursor:latest.next_cursor,max_output_tokens:8000}));
  for(const v of r.revisions) {
    const page=q.query('list_pages',{...scope,revision_id:v.revision_occurrence_id}).items[0];
    const e=q.query('get_page',{...scope,revision_id:v.revision_occurrence_id,page_id:page.page_id}).items[0];
    const element=q.query('get_element',{...scope,observation_id:e.observation_id}).items[0];
    const evidence=q.query('get_evidence',{...scope,observation_id:e.observation_id}).items[0];
    assert.equal(element.text,evidence.quote);assert.deepEqual(element.bbox,evidence.bbox);
  }
  const folder=join(root,'export');await exportReport(q,r.project_id,r.report_id,folder);
  const exported=(await readFile(join(folder,'changes.jsonl'),'utf8')).trim().split('\n').map(line=>JSON.parse(line));
  assert.deepEqual(exported,r.changes);assert.equal(JSON.parse(await readFile(join(folder,'report.json'),'utf8')).report_id,r.report_id);
  const history=await readFile(join(folder,'history.md'),'utf8');assert.ok(history.includes('120억'));assert.ok(history.includes('110억'));
  for(const match of history.matchAll(/\]\((content\/[^)]+)\)/g))await readFile(join(folder,match[1]));
});
test('Markdown history keeps inferred text and appearance qualifiers beside confirmed page mappings',async()=>{
  const r=structuredClone(reports.get('forward')!);r.project_id='prj_export_qualifiers';r.report_id='rpt_export_qualifiers';r.coverage_gaps=[];r.changes=r.changes.filter(c=>c.kind==='text_modified').slice(0,1);
  const c=r.changes[0];assert.ok(c);c.report_id=r.report_id;c.lineage.status='human_confirmed';c.text_assessment='inferred';c.appearance_assessment='inferred';c.coverage_gaps=[{feature:'ocr',reason:'ocr_inferred_text_requires_source_review'}];c.evidence=c.evidence.map(e=>({...e,method:'vision_ocr',provenance:'inferred'}));
  store.finishRun(store.beginRun(r.project_id,'Markdown qualifier regression'),r);const folder=join(root,'qualified-export');await exportReport(new QueryService(store,new Set([r.project_id])),r.project_id,r.report_id,folder);
  const md=await readFile(join(folder,'history.md'),'utf8');assert.match(md,/human_confirmed/);assert.match(md,/문구 판정: 추정 · 표시 판정: 추정/);assert.match(md,/방법: vision_ocr · 출처: 추정/);assert.match(md,/이 변경의 관측 한계:[\s\S]*ocr_inferred_text_requires_source_review/);assert.deepEqual(JSON.parse(await readFile(join(folder,'report.json'),'utf8')).changes,r.changes);
});
test('response byte budget and scope restrictions',()=>{
  const r=reports.get('forward')!,q=new QueryService(store,new Set([r.project_id])),scope={project_id:r.project_id,report_id:r.report_id};
  const response=q.query('list_changes',{...scope,max_output_tokens:1400});assert.ok(Buffer.byteLength(JSON.stringify(response))<=1400);assert.ok(response.truncated);assert.ok(response.omitted_fields.length);
  assert.throws(()=>q.query('get_report',{...scope,project_id:'prj_other'}),{code:'PROJECT_SCOPE'});
  assert.throws(()=>q.query('get_report',{...scope,path:'/etc/passwd'}));
  assert.throws(()=>q.query('get_report',{...scope,report_id:'../../etc/passwd'}));
  assert.throws(()=>q.query('get_page',{...scope,revision_id:r.revisions[0].revision_occurrence_id,page_id:r.revisions[1].pages[0].page_id}),{code:'PAGE_NOT_FOUND'});
});
test('repeated files have distinct occurrence and observation IDs',async()=>{
  const folder=dirname(paths[0]),file='v1.pptx';
  const {report:r}=await analyze({project_id:'prj_repeat',title:'Repeat',revisions:[{label:'A',files:[file]},{label:'B',files:[file]}],mapping_decisions:[]},folder,store);
  assert.equal(r.revisions[0].revision_id,r.revisions[1].revision_id);assert.notEqual(r.revisions[0].revision_occurrence_id,r.revisions[1].revision_occurrence_id);
  assert.notEqual(r.revisions[0].pages[0].page_id,r.revisions[1].pages[0].page_id);assert.equal(r.changes.length,0);
});
test('corrupt and unsupported files fail independently; successful neighboring revisions retained',async()=>{
  const folder=join(root,'broken');await mkdir(folder);await writeFile(join(folder,'broken.pdf'),'%PDF-broken');await writeFile(join(folder,'legacy.ppt'),'legacy');
  await assert.rejects(ingest(join(folder,'legacy.ppt')),{code:'UNSUPPORTED_FORMAT'});
  await writeFile(join(folder,'broken.pptx'),'not a zip');await assert.rejects(ingest(join(folder,'broken.pptx')),{code:'INVALID_PPTX'});
  const protectedDoc=new PDFDocument({userPassword:'secret',ownerPassword:'owner-secret'}),chunks:Buffer[]=[];
  protectedDoc.on('data',b=>chunks.push(b));const done=new Promise<Buffer>(res=>protectedDoc.on('end',()=>res(Buffer.concat(chunks))));protectedDoc.text('Protected');protectedDoc.end();
  await writeFile(join(folder,'protected.pdf'),await done);await assert.rejects(ingest(join(folder,'protected.pdf')),{code:'ENCRYPTED_PDF'});
  const {report:r}=await analyze({project_id:'prj_broken',title:'Partial',revisions:[{label:'good',files:[join(dirname(paths[0]),'v1.pptx')]},{label:'bad',files:['broken.pdf']},{label:'good2',files:[join(dirname(paths[0]),'v3.pptx')]}],mapping_decisions:[]},folder,store);
  assert.deepEqual(r.revisions.map(v=>v.status),['success','failed','success']);assert.equal(r.revisions[1].errors[0].code,'INVALID_PDF');
  assert.equal(r.changes.filter(c=>c.kind!=='coverage_gap').length,0);assert.equal(r.matches.length,0);
});
test('PPTX package order, XML entities, external references, and geometry bounds',async()=>{
  const raw=await readFile(join(dirname(paths[0]),'v1.pptx')),parts=unzipSync(raw);
  let main=strFromU8(parts['ppt/presentation.xml']);
  const ids=[...main.matchAll(/<p:sldId\s[^>]*\/>/g)].map(x=>x[0]);
  main=main.replace(ids.join(''),[...ids].reverse().join(''));parts['ppt/presentation.xml']=strToU8(main);
  const reversed=extractPptx(zipSync(parts),'sha256:test');assert.ok(reversed[0].text.includes('운영 위험'));
  const slide=strFromU8(parts['ppt/slides/slide1.xml']);parts['ppt/slides/slide1.xml']=strToU8('<!DOCTYPE sld [<!ENTITY x SYSTEM "file:///etc/passwd">]>'+slide);
  assert.throws(()=>extractPptx(zipSync(parts),'sha256:test'),{code:'XML_DTD'});
  const external=unzipSync(raw);
  external['_rels/.rels']=strToU8(strFromU8(external['_rels/.rels']).replace(/Target="ppt\/presentation.xml"/, 'Target="https://invalid.example/forbidden.xml" TargetMode="External"'));
  assert.throws(()=>extractPptx(zipSync(external),'sha256:test'),{code:'EXTERNAL_RELATIONSHIP'});
  assert.throws(()=>Bbox.parse([0.9,0,0.2,0.2]));
});
test('PDF preview PNG works without LibreOffice; converter absence and timeout explicit',async()=>{
  const pdf=await readFile(join(dirname(paths[0]),'v2.pdf'));
  const image=await renderPdf(pdf,2,640);assert.equal(image.subarray(1,4).toString(),'PNG');await writeFile(join(root,'preview.png'),image);
  await assert.rejects(convertPptx(join(dirname(paths[0]),'v1.pptx'),join(root,'no-converter')),{code:'CONVERTER_UNAVAILABLE'});
  const fake=join(root,'fake-converter');if(process.platform==='darwin')execFileSync('/usr/bin/clang',['-x','c','-','-o',fake],{input:'#include <unistd.h>\nint main(void){sleep(5);return 0;}\n'});else{await writeFile(fake,'#!/bin/sh\nexec sleep 5\n');await chmod(fake,0o700);}
  await assert.rejects(convertPptx(join(dirname(paths[0]),'v1.pptx'),fake,50),{code:'CONVERTER_TIMEOUT'});
});
test('real MCP stdio handshake, schemas, fixed reports, resources, read-only storage',async()=>{
  const r=reports.get('forward')!,dbPath=join(root,'store','docver.sqlite');
  const before=byteHash(await readFile(dbPath));
  const transport=new StdioClientTransport({command:process.execPath,args:['--import','tsx',resolve('apps/mcp/main.ts'),'--store',join(root,'store'),'--project',r.project_id],stderr:'pipe'});
  let stderr='';transport.stderr?.on('data',b=>stderr+=b.toString());
  const client=new Client({name:'checkpoint-tests',version:'1.0.0'});
  try {
    await client.connect(transport);
    const tools=await client.listTools();assert.deepEqual(tools.tools.map(t=>t.name).sort(),['list_projects','list_reports','get_report','list_revisions','list_pages','get_page','get_element','list_changes','get_entity_history','get_evidence','list_page_relations'].sort());for(const t of tools.tools){assert.equal(t.annotations?.readOnlyHint,true);assert.ok(t.inputSchema);assert.ok(t.outputSchema);}
    const relations=await client.callTool({name:'list_page_relations',arguments:{project_id:r.project_id,report_id:r.report_id,max_output_tokens:4000,limit:1}});assert.notEqual(relations.isError,true);assert.ok(Buffer.byteLength(JSON.stringify(relations))<=4000);
    const bounded=await client.callTool({name:'list_changes',arguments:{project_id:r.project_id,report_id:r.report_id,max_output_tokens:4000}});
    assert.notEqual(bounded.isError,true);assert.ok(Buffer.byteLength(JSON.stringify(bounded))<=4000);
    const results:any[]=[];let cursor:string|undefined;
    do {
      const response=await client.callTool({name:'list_changes',arguments:{project_id:r.project_id,report_id:r.report_id,kind:'text_modified',limit:1,max_output_tokens:8000,...(cursor?{cursor}:{})}});
      assert.notEqual(response.isError,true,JSON.stringify(response));const structured=response.structuredContent as QueryResult;results.push(...structured.items);cursor=structured.next_cursor??undefined;
    } while(cursor);
    assert.deepEqual(results.map(c=>c.change_id),r.changes.filter(c=>c.kind==='text_modified').map(c=>c.change_id));
    const entityId=results[0].entity_id;
    const historyRows:any[]=[];let historyCursor:string|undefined;
    do {
      const history=await client.callTool({name:'get_entity_history',arguments:{project_id:r.project_id,report_id:r.report_id,entity_id:entityId,limit:1,max_output_tokens:8000,...(historyCursor?{cursor:historyCursor}:{})}});assert.notEqual(history.isError,true);assert.ok(Buffer.byteLength(JSON.stringify(history))<=8000);
      const page=history.structuredContent as QueryResult;historyRows.push(...page.items);historyCursor=page.next_cursor??undefined;
    }while(historyCursor);
    assert.equal(historyRows.length,3);assert.deepEqual(historyRows.map(p=>p.revision_occurrence_id),r.revisions.map(v=>v.revision_occurrence_id));
    const resource=await client.readResource({uri:`docver://projects/${r.project_id}/reports/${r.report_id}/manifest`});assert.ok(resource.contents.length);
    const changeResource=await client.readResource({uri:r.changes[0].evidence_uri});assert.ok(JSON.parse(String('text' in changeResource.contents[0]?changeResource.contents[0].text:'')).items[0].change_id);
    const denied=await client.callTool({name:'get_report',arguments:{project_id:'prj_other',report_id:r.report_id}});assert.equal(denied.isError,true);
    await assert.rejects(client.readResource({uri:'file:///etc/passwd'}));
    const unsupported=await client.callTool({name:'execute_shell',arguments:{command:'echo forbidden'}});assert.equal(unsupported.isError,true);
  } finally {await client.close();}
  assert.equal(byteHash(await readFile(dbPath)),before);assert.equal(stderr,'');
  const readOnly=new Store(join(root,'store'),true);try {assert.throws(()=>readOnly.db.exec("DELETE FROM reports"));}finally{readOnly.close();}
});

test('large page text is paginated and can be recovered exactly in bounded element chunks',async()=>{
  const folder=join(root,'large');await mkdir(folder);const body='큰 페이지 원문 123.45억 '.repeat(1000);
  await writeFile(join(folder,'large.pptx'),await makePptx([{key:'large',title:'큰 페이지',body}]));
  const {report:r}=await analyze({project_id:'prj_large',title:'Large',revisions:[{label:'Large',files:['large.pptx']}],mapping_decisions:[]},folder,store);
  const q=new QueryService(store,new Set([r.project_id])),scope={project_id:r.project_id,report_id:r.report_id,max_output_tokens:2000};
  const page=r.revisions[0].pages[0];
  const rows=all(q,'get_page',{...scope,revision_id:r.revisions[0].revision_occurrence_id,page_id:page.page_id});
  const summary=rows.find((v:any)=>v.truncated);assert.ok(summary);assert.ok(summary.omitted_fields.includes('text'));
  let text='',offset=0;
  do {const item=q.query('get_element',{...scope,observation_id:summary.observation_id,text_offset:offset,text_length:100}).items[0];text+=item.text;offset=Number(item.next_text_offset);if(item.next_text_offset===null)break;}while(offset<body.length);
  assert.equal(text.length,body.length,'reconstructed length');assert.equal(byteHash(Buffer.from(text)),byteHash(Buffer.from(body)),'reconstructed content hash');
});
test('an insertion does not mark following pages as moved; pre-cancelled analysis records failure',async()=>{
  const folder=join(root,'insertion');await mkdir(folder);const slides=scenarios[0].versions[0].slides;
  await writeFile(join(folder,'before.pptx'),await makePptx(slides));await writeFile(join(folder,'after.pptx'),await makePptx([slides[0],{key:'new',title:'일회성 실험',body:'추가된 검토 페이지'},...slides.slice(1)]));
  const input={project_id:'prj_insertion',title:'Insertion',revisions:[{label:'Before',files:['before.pptx']},{label:'After',files:['after.pptx']}],mapping_decisions:[]};
  const {report:r}=await analyze(input,folder,store);assert.equal(r.changes.filter(c=>c.kind==='page_moved').length,0);assert.equal(r.changes.filter(c=>c.kind==='page_added').length,1);
  const controller=new AbortController();controller.abort();await assert.rejects(analyze(input,folder,store,controller.signal),{name:'AbortError'});
});
