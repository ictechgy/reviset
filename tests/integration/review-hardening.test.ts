import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,readFile,writeFile,readdir,rm,symlink,lstat} from 'node:fs/promises';
import {join} from 'node:path';import {tmpdir} from 'node:os';
import {publishContent,publishContentSync} from '../../packages/runtime/atomic-content.js';
import {byteHash,Manifest,SCHEMA_HASH} from '../../packages/schema/index.js';
import {extractPdf,PDF_TEXT_GEOMETRY_POLICY} from '../../packages/ingest/pdf.js';
import {BoundedCache} from '../../packages/query/bounded-cache.js';
function pdf(unit:number,rotation:number){
 const stream='BT /F1 20 Tf 1 0 0 1 60 300 Tm (Revenue 100) Tj ET\n',objects=['<< /Type /Catalog /Pages 2 0 R >>','<< /Type /Pages /Kids [3 0 R] /Count 1 >>',`<< /Type /Page /Parent 2 0 R /MediaBox [0 0 600 400] /UserUnit ${unit} /Rotate ${rotation} /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>`,'<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',`<< /Length ${Buffer.byteLength(stream)} >>\nstream\n${stream}endstream`];let text='%PDF-1.7\n',offsets=[0];for(const [i,obj]of objects.entries()){offsets.push(Buffer.byteLength(text));text+=`${i+1} 0 obj\n${obj}\nendobj\n`;}const xref=Buffer.byteLength(text);text+=`xref\n0 ${objects.length+1}\n0000000000 65535 f \n`+offsets.slice(1).map(n=>String(n).padStart(10,'0')+' 00000 n \n').join('')+`trailer\n<< /Size ${objects.length+1} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF\n`;return Buffer.from(text);
}
test('PDF source text extent and visible state are invariant across UserUnit and page rotation',async()=>{
 assert.equal(PDF_TEXT_GEOMETRY_POLICY,'viewport-scaled-run-advance-v2');
 for(const rotation of [0,90,180,270]){
  let reference:number[]|undefined;
  for(const unit of [1,.5,2,10]){
   const bytes=pdf(unit,rotation),page=(await extractPdf(bytes,'sha256:'+byteHash(bytes),{ocr:'off'}))[0],element=page.elements.find(e=>e.method==='pdf_text')!;
   assert.equal(element.text,'Revenue 100');assert.equal(element.visibility,'visible',JSON.stringify({unit,rotation,element}));assert.equal(page.unresolved_text,'');
   if(!reference)reference=element.bbox;else element.bbox.forEach((v,i)=>assert.ok(Math.abs(v-reference![i])<1e-10,JSON.stringify({unit,rotation,reference,actual:element.bbox})));
  }
 }
});
test('canonical content publishes complete private files, repairs truncation with preserved evidence and refuses symlinks',async()=>{
 const root=await mkdtemp(join(tmpdir(),'docver-publish-'));try{
  const bytes=Buffer.from('complete verified original '.repeat(1000)),sha=byteHash(bytes);
  for(const sync of [false,true]){
   const target=join(root,sync?'sync':'async');await writeFile(target,'truncated original');
   if(sync)publishContentSync(target,bytes,sha);else await publishContent(target,bytes,sha);
   assert.deepEqual(await readFile(target),bytes);const quarantines=(await readdir(root)).filter(n=>n.startsWith((sync?'sync':'async')+'.corrupt-'));assert.equal(quarantines.length,1);assert.equal(await readFile(join(root,quarantines[0]),'utf8'),'truncated original');
   const before=(await lstat(target)).ino;if(sync)publishContentSync(target,bytes,sha);else await publishContent(target,bytes,sha);assert.equal((await lstat(target)).ino,before,'matching canonical file is unchanged');
  }
  const target=join(root,'fresh');await publishContent(target,bytes,sha);assert.equal((await lstat(target)).mode&0o777,0o600);assert.equal((await readdir(root)).filter(n=>n.endsWith('.tmp')).length,0);
  const outside=join(root,'outside'),linked=join(root,'linked');await writeFile(outside,'outside evidence');await symlink(outside,linked);await assert.rejects(publishContent(linked,bytes,sha),{code:'ASSET_CORRUPT'});assert.equal(await readFile(outside,'utf8'),'outside evidence');assert.ok((await lstat(linked)).isSymbolicLink());
 }finally{await rm(root,{recursive:true,force:true});}
});
test('cache keeps LRU and serialized-byte bounds; huge entries cannot evict retained valid entries',()=>{
 const cache=new BoundedCache<string>(2,16);cache.set('a','one');cache.set('b','two');assert.equal(cache.get('a'),'one');cache.set('c','three');assert.equal(cache.get('b'),undefined);assert.equal(cache.get('a'),'one');cache.set('huge','x'.repeat(100));assert.equal(cache.get('huge'),undefined);assert.equal(cache.get('a'),'one');assert.equal(cache.get('c'),'three');
});
test('CLI manifest admission matches desktop100revision cap without changing stored Report schema',()=>{
 const revision={label:'v',files:['synthetic.pdf']};assert.ok(Manifest.safeParse({project_id:'prj_admission',title:'test',revisions:Array.from({length:100},()=>revision)}).success);assert.equal(Manifest.safeParse({project_id:'prj_admission',title:'test',revisions:Array.from({length:101},()=>revision)}).success,false);assert.match(SCHEMA_HASH,/^[a-f0-9]{64}$/);
});

import {Store} from '../../packages/storage/index.js';
import {DesktopService,DESKTOP_PROJECTS_TABLE} from '../../packages/desktop/service.js';
import {QueryService} from '../../packages/query/index.js';
import {exportReport} from '../../packages/export/index.js';
import {matchPages,MAX_ASSIGNMENT_COSTS,MATCHING_WORK_POLICY} from '../../packages/matching/index.js';
import {matchPages as preservedMatcher} from '../../packages/matching/legacy-bundle-51.js';
import {ENGINE_VERSION,SCHEMA_VERSION,Report,type ReportData,type PageData,type RevisionData} from '../../packages/schema/index.js';
function sourcePage(id:string,text='Revenue 100',asset='sha256:'+'a'.repeat(64)):PageData{return {page_id:id,asset_id:asset,page:1,width:960,height:540,coordinate_system:'normalized_top_left',source_transform:[1,0,0,1,0,0],hidden:false,text,elements:[{observation_id:'obs_'+id,kind:'text',text,normalized_text:text,bbox:[.1,.1,.5,.1],reading_order:0,availability:'available',method:'fixture_source',source_ref:id,provenance:'observed'}],notes:'',capabilities:{text:'available',notes:'available',hidden_slides:'available',animation:'unavailable',structure:'available',preview:'unavailable'},coverage_gaps:[]};}
function readingReport(reportId:string):ReportData{
 const revisions:RevisionData[]=['a','b'].map((v,i)=>({revision_id:'rev_'+v,revision_occurrence_id:'occ_'+v,label:v,assets:[{asset_id:'sha256:'+(i?'b':'a').repeat(64),format:'pdf',bytes:0}],status:'success',pages:[sourcePage('page_'+v,'Revenue '+(i?120:100),'sha256:'+(i?'b':'a').repeat(64))],coverage_gaps:[],errors:[],bundle_mapping:[]}));
 return Report.parse({schema_version:SCHEMA_VERSION,engine_version:ENGINE_VERSION,schema_hash:SCHEMA_HASH,report_id:reportId,project_id:'prj_review',timeline_revision_id:'timeline',mapping_revision_id:'mapping',observation_environment:{fixture:'review',matching_work_policy:MATCHING_WORK_POLICY},revisions,matches:[{from_page_id:'page_a',to_page_id:'page_b',score:1,status:'human_confirmed',reasons:['original']}],candidates:[],mapping_decisions:[],mapping_relations:[],lineages:[{entity_id:'family',page_ids:['page_a','page_b'],status:'human_confirmed'}],changes:[],coverage_gaps:[]});
}
test('dense matching preserves historical square ties and uncertainty; work exhaustion cannot become absent-page evidence',()=>{
 for(const n of [1,2,8,32]){const a=Array.from({length:n},(_,i)=>sourcePage('a'+i,'Same repeated heading','sha256:'+'a'.repeat(64))),b=Array.from({length:n},(_,i)=>sourcePage('b'+i,'Same repeated heading','sha256:'+'b'.repeat(64)));assert.deepEqual(matchPages(a,b),preservedMatcher(a,b));}
 const a=Array.from({length:1000},(_,i)=>sourcePage('a'+i,'Repeated page','sha256:'+'a'.repeat(64))),b=Array.from({length:1000},(_,i)=>sourcePage('b'+i,'Repeated page','sha256:'+'b'.repeat(64))),dense=matchPages(a,b,[],[],{maxCosts:MAX_ASSIGNMENT_COSTS});assert.equal(dense.matches.length,1000);assert.ok(dense.matches.every(m=>m.status==='needs_review'));assert.ok(dense.candidates.length<=17000);assert.ok(dense.candidates.some(m=>m.from_page_id==='a999'));
 assert.throws(()=>matchPages([sourcePage('x','Revenue quarterly outlook'),sourcePage('y','Revenue quarterly changes')],[sourcePage('m','Revenue quarterly outlook','other'),sourcePage('n','Revenue quarterly changed','other')],[],[],{maxCosts:1}),{code:'MATCHING_LIMIT'});
});
test('MCP immutable report cache resolves latest afresh and enforces scope before cache; range filters and selectors remain independent',async()=>{
 const root=await mkdtemp(join(tmpdir(),'docver-query-cache-')),store=new Store(root);try{
  const first=readingReport('report_first');store.finishRun(store.beginRun(first.project_id,'first'),first);let reads=0;const read=store.report.bind(store);store.report=(p,r)=>{reads++;return read(p,r);};const scope=new Set([first.project_id]),q=new QueryService(store,scope);
  assert.equal(q.snapshot(first.project_id,'latest').report_id,first.report_id);assert.equal(q.snapshot(first.project_id,first.report_id).report_id,first.report_id);assert.equal(reads,1);
  const args={project_id:first.project_id,report_id:first.report_id,from:'occ_a',to:'occ_b',mode:'range_net'};const original=q.changeSet(args);assert.equal(original.length,1);assert.equal(q.changeSet({...args,text:'not present'}).length,0);assert.deepEqual(q.changeSet(args),original);assert.deepEqual(q.changeSet({...args,from:'rev_a',to:'rev_b'}),original);
  assert.throws(()=>q.changeSet({...args,from:'occ_b',to:'occ_a'}),{code:'RANGE_ORDER'});scope.clear();assert.throws(()=>q.snapshot(first.project_id,first.report_id),{code:'PROJECT_SCOPE'});scope.add(first.project_id);
  const second=readingReport('report_second');store.finishRun(store.beginRun(second.project_id,'second'),second);assert.equal(q.snapshot(first.project_id,'latest').report_id,second.report_id);assert.equal(q.snapshot(first.project_id,first.report_id).report_id,first.report_id);assert.equal(reads,2);
 }finally{store.close();await rm(root,{recursive:true,force:true});}
});
test('one malformed or identity-mismatched draft cannot hide healthy projects or rewrite existing evidence',async()=>{
 const root=await mkdtemp(join(tmpdir(),'docver-corrupt-row-')),service=new DesktopService(root);try{
  const file=join(root,'synthetic.pdf');await writeFile(file,'synthetic');const healthy=await service.create('Healthy',[{label:'v1',files:[file]}]);
  for(const [id,body]of [['prj_broken','{broken'],['prj_wrong_id',JSON.stringify(healthy)]])service.store.db.prepare(`INSERT INTO ${DESKTOP_PROJECTS_TABLE} VALUES (?,?,?)`).run(id,body,'2026-10-21');
  assert.deepEqual(service.projects().map(p=>p.project_id),[healthy.project_id]);assert.deepEqual(service.unreadableProjects.map(p=>p.project_id).sort(),['prj_broken','prj_wrong_id']);assert.throws(()=>service.project('prj_broken'),{code:'DRAFT_UNREADABLE'});assert.throws(()=>service.project('prj_wrong_id'),{code:'DRAFT_UNREADABLE'});assert.equal(service.store.db.prepare(`SELECT body FROM ${DESKTOP_PROJECTS_TABLE} WHERE id=?`).get('prj_broken')?.body,'{broken');
 }finally{service.close();await rm(root,{recursive:true,force:true});}
});
test('full Markdown export keeps hostile content inert and distinct same-prefix assets recoverable',async()=>{
 const root=await mkdtemp(join(tmpdir(),'docver-export-literal-'));try{
  const r=readingReport('report_export'),v=r.revisions[0],malicious='<img src="https://example.invalid/pixel">\n![remote](https://example.invalid/pixel)\n```\n# forged heading\n````\n<script>alert(1)</script>';
  v.label=malicious;v.pages[0].text=malicious;v.pages[0].elements[0].text=malicious;const asset='sha256:'+'a'.repeat(8)+'c'.repeat(56);v.assets.push({asset_id:asset,format:'pdf',bytes:0});v.pages.push({...sourcePage('page_collision',malicious,asset)});
  const q=new QueryService({} as Store,new Set([r.project_id]),()=>r),folder=join(root,'export');await exportReport(q,r.project_id,r.report_id,folder);const paths=await readdir(join(folder,'content/occ_a'));assert.equal(paths.length,2);assert.ok(paths.every(n=>n.length>75));const text=await readFile(join(folder,'content/occ_a',paths[0]),'utf8');
  let fence='';for(const line of text.split('\n')){if(!line.startsWith('> '))continue;const value=line.slice(2),marker=/^(`{3,})(?:text)?$/.exec(value);if(marker){if(!fence)fence=marker[1];else if(marker[1]===fence)fence='';}if(value.includes('example.invalid')||value.includes('<script>')||value==='# forged heading')assert.ok(fence,'untrusted source must remain in a fenced code block');}assert.equal(fence,'');assert.equal(JSON.parse(await readFile(join(folder,'report.json'),'utf8')).revisions[0].pages[0].text,malicious);
 }finally{await rm(root,{recursive:true,force:true});}
});
