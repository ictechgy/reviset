import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,readFile,writeFile,rm,readdir} from 'node:fs/promises';
import {existsSync,writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {Page,Report,SCHEMA_VERSION,ENGINE_VERSION,SCHEMA_HASH,canonical,byteHash,type PageData,type RevisionData,type ReportData} from '../../packages/schema/index.js';
import {qualifyReferenceAppearance,attachReferenceAppearance} from '../../packages/render/reference-appearance.js';
import {matchPages} from '../../packages/matching/index.js';
import {diffRevisions} from '../../packages/diff/index.js';
import {QueryService} from '../../packages/query/index.js';
import {Store} from '../../packages/storage/index.js';
import {analyze} from '../../packages/engine/index.js';
import {makePptx,makePdf} from '../../scripts/generate-fixtures.js';
import {exportReport} from '../../packages/export/index.js';
const raster=(digit:string)=>({sha256:digit.repeat(64),width:3000,height:1688,renderer:'PDFKit.thumbnail.cropBox',environment:'frozen-helper-os-fonts-config-hash',page_box:'cropBox' as const,rotation:0,render_policy:'pdfkit-300dpi-max4096-source-color-profile-v1' as const});
function page(id:string,text='Unique topic'):PageData{return {page_id:id,asset_id:'sha256:'+'a'.repeat(64),page:1,width:960,height:540,coordinate_system:'normalized_top_left',source_transform:[1,0,0,-1,0,540],hidden:false,text,elements:[{observation_id:'obs_'+id,kind:'text',text,normalized_text:text,bbox:[.1,.1,.5,.1],reading_order:0,availability:'available',method:'ooxml_text',source_ref:id,provenance:'observed'}],notes:'Source notes',capabilities:{text:'available',notes:'available',hidden_slides:'available',animation:'unavailable',structure:'available',preview:'unavailable'},coverage_gaps:[]};}
function pair(key:string,digit='1'){
 const source=page('source_'+key),pdf={...page('pdf_'+key),asset_id:'sha256:'+'b'.repeat(64),notes:null,raster:raster(digit)},mapping=[{source_page_id:source.page_id,rendered_page_id:pdf.page_id,score:1}];
 return {source,pdf,mapping};
}
function revision(key:string,p:ReturnType<typeof pair>):RevisionData{return {revision_id:'rev_'+key,revision_occurrence_id:'occ_'+key,label:key,assets:[{asset_id:p.source.asset_id,format:'pptx',bytes:0},{asset_id:p.pdf.asset_id,format:'pdf',bytes:0}],status:'success',reference_appearance_policy:'qualified-full-bundle-v1',pages:[p.source,p.pdf],bundle_mapping:p.mapping,coverage_gaps:[],errors:[]};}
function report(revisions:RevisionData[]):ReportData{return {schema_version:SCHEMA_VERSION,engine_version:ENGINE_VERSION,schema_hash:SCHEMA_HASH,project_id:'project_reference',report_id:'report_reference',timeline_revision_id:'timeline_reference',mapping_revision_id:'mapping_reference',observation_environment:{},revisions,matches:[],candidates:[],mapping_decisions:[],mapping_relations:[],lineages:[],changes:[],coverage_gaps:[]};}

test('reference qualification rejects ambiguous, blank, incomplete, reused, uncertain and wrong geometry exports',()=>{
 const {source,pdf,mapping}=pair('q');assert.equal(qualifyReferenceAppearance([source],[pdf],mapping,false,false).qualified,true);
 for(const [a,b,m,ambiguous,reused] of [
  [[source],[pdf],mapping,true,false],[[source],[pdf],mapping,false,true],[[source],[pdf],[],false,false],
  [[{...source,text:''}],[{...pdf,text:''}],mapping,false,false],[[source],[{...pdf,text:'Different'}],mapping,false,false],
  [[source],[{...pdf,width:540,height:960}],mapping,false,false],[[source],[{...pdf,raster:undefined}],mapping,false,false],
  [[source],[{...pdf,raster:{...pdf.raster,rotation:90}}],mapping,false,false],
  [[source],[{...pdf,unresolved_text:'hidden word'}],mapping,false,false],[[source],[{...pdf,visible_text:'Different'}],mapping,false,false],
  [[source],[pdf,pdf],mapping,false,false],[[source],[pdf],[{...mapping[0],score:.94}],false,false]
 ] as [PageData[],PageData[],typeof mapping,boolean,boolean][])assert.equal(qualifyReferenceAppearance(a,b,m,ambiguous,reused).qualified,false);
 const hidden={...page('hidden'),hidden:true};assert.equal(qualifyReferenceAppearance([source,hidden],[pdf],mapping,false,false).qualified,true);
 const raw=canonical(pdf);attachReferenceAppearance([source,hidden],[pdf],mapping);assert.equal(canonical(pdf),raw);assert.equal(source.preview,undefined);assert.equal(source.raster,undefined);assert.equal(hidden.appearance,undefined);Page.parse(source);
});

test('provided appearance creates qualified PDF evidence without exact-source raster anchors or losing OOXML edits',()=>{
 const left=pair('a','1'),right=pair('b','2');right.source.asset_id='sha256:'+'c'.repeat(64);right.pdf.asset_id='sha256:'+'d'.repeat(64);
 for(const p of [left,right])attachReferenceAppearance([p.source],[p.pdf],p.mapping);
 // Give the other source a different text: equal reference pixels must never force an identity match.
 const different={...structuredClone(right.source),text:'Completely unrelated material'};assert.ok(matchPages([left.source],[different]).matches.every(m=>!m.reasons.includes('exact_native_raster')));
 const a=revision('a',left),b=revision('b',right),edge={from_page_id:left.source.page_id,to_page_id:right.source.page_id,score:1,status:'human_confirmed' as const,reasons:['source_pair']};
 const changes=diffRevisions({...a,pages:[left.source]},{...b,pages:[right.source]},[edge],[],()=> 'family');const visual=changes.find(c=>c.kind==='visual_region_changed')!;assert.ok(visual);assert.equal(visual.appearance_assessment,'inferred');assert.deepEqual(visual.evidence.map(e=>[e.asset_id,e.page_id,e.render_sha256,e.provenance]),[[left.pdf.asset_id,left.pdf.page_id,left.pdf.raster.sha256,'inferred'],[right.pdf.asset_id,right.pdf.page_id,right.pdf.raster.sha256,'inferred']]);assert.ok(!changes.some(c=>c.kind==='text_modified'));Report.parse(report([a,b]));
 const stored=report([a,b]);stored.matches=[edge];stored.lineages=[{entity_id:'family',page_ids:[left.source.page_id,right.source.page_id],status:'human_confirmed'}];stored.changes=changes.map((change,index)=>({...change,report_id:stored.report_id,change_id:'chg_synthetic_reference_'+index}));
 const rawStored=JSON.stringify(stored),query=new QueryService({} as Store,new Set([stored.project_id]),()=>stored),scope={project_id:stored.project_id,report_id:stored.report_id,from:a.revision_occurrence_id,to:b.revision_occurrence_id};
 for(const mode of ['history','range_net']){
  const events=query.changeSet({...scope,mode});assert.ok(events.some(c=>c.kind==='visual_region_changed'));assert.ok(!events.some(c=>c.kind==='page_added'||c.kind==='page_deleted'));
  const event=events.find(c=>c.kind==='visual_region_changed')!;assert.deepEqual(event.evidence.map(e=>[e.asset_id,e.page_id]),[[left.pdf.asset_id,left.pdf.page_id],[right.pdf.asset_id,right.pdf.page_id]]);
 }
 assert.equal(JSON.stringify(stored),rawStored,'Provided-PDF query qualification must leave the fixed report untouched');
 assert.ok(visual.coverage_gaps.every(g=>g.feature==='visual_comparison'),'Supplied-PDF visual uncertainty must not be labelled text uncertainty');
 const tampered=structuredClone(report([a,b]));tampered.revisions[0].pages[0].appearance!.asset_id=right.pdf.asset_id;assert.equal(Report.safeParse(tampered).success,false);
 const c=structuredClone(right);c.source.text='Unique topic 120';c.source.elements[0].text=c.source.text;c.source.elements[0].normalized_text=c.source.text;c.pdf.raster.sha256=left.pdf.raster.sha256;c.source.appearance!.raster!.sha256=left.pdf.raster.sha256;
 const sourceChange=diffRevisions({...a,pages:[left.source]},{...revision('c',c),pages:[c.source]},[{...edge,to_page_id:c.source.page_id}],[],()=> 'family');assert.ok(sourceChange.some(c=>c.kind==='text_modified'));assert.ok(sourceChange.some(c=>c.coverage_gaps.some(g=>g.reason==='pptx_source_changed_despite_identical_reference_pixels')));
 c.source.appearance!.raster!.environment='different-helper-os-fonts';const gap=diffRevisions({...a,pages:[left.source]},{...revision('d',c),pages:[c.source]},[{...edge,to_page_id:c.source.page_id}],[],()=> 'family');assert.ok(gap.some(c=>c.coverage_gaps.some(g=>g.reason==='revision_interval_render_appearance_not_comparable')));assert.ok(!gap.some(c=>c.kind==='visual_region_changed'));
 const unchanged=structuredClone(right);unchanged.source.asset_id=left.source.asset_id;const exportOnly=diffRevisions({...a,pages:[left.source]},{...revision('same_source',unchanged),pages:[unchanged.source]},[edge],[],()=> 'family');assert.ok(exportOnly.some(c=>c.coverage_gaps.some(g=>g.reason==='reference_pdf_changed_without_pptx_source_change')));assert.ok(!exportOnly.some(c=>c.kind==='visual_region_changed'));
 const invalidRenderer=structuredClone(right.source);delete invalidRenderer.appearance;invalidRenderer.raster={...right.pdf.raster,renderer:'Unverified renderer'};const rendererGap=diffRevisions({...a,pages:[left.source]},{...b,pages:[invalidRenderer]},[edge],[],()=> 'family');assert.ok(rendererGap.some(c=>c.coverage_gaps.some(g=>g.reason==='reference_appearance_unavailable_or_unverified_for_page')));assert.ok(!rendererGap.some(c=>c.kind==='visual_region_changed'));
 const missing=page('missing'),available=structuredClone(right.source);available.page_id='available';const mixed=diffRevisions({...a,pages:[missing,left.source]},{...b,pages:[available,c.source]},[{...edge,from_page_id:'missing',to_page_id:'available'},edge],[],()=> 'family');assert.ok(mixed.some(c=>c.coverage_gaps.some(g=>g.reason==='reference_appearance_unavailable_or_unverified_for_page')));assert.ok(mixed.some(c=>c.coverage_gaps.some(g=>g.reason==='revision_interval_render_appearance_not_comparable')));
 const reused=structuredClone(report([a,b]));reused.revisions[1].pages[1].asset_id=left.pdf.asset_id;reused.revisions[1].assets[1].asset_id=left.pdf.asset_id;reused.revisions[1].pages[0].appearance!.asset_id=left.pdf.asset_id;assert.equal(Report.safeParse(reused).success,false);
});

test('source mutation after identity capture aborts instead of saving a partial mismatched timeline',async()=>{
 const root=await mkdtemp(join(tmpdir(),'docver-source-mutation-')),store=new Store(join(root,'store'));try{
  const a=await makePptx([{key:'a',title:'Before source',body:'Original'}]),b=await makePptx([{key:'b',title:'Changed source',body:'Replacement'}]),path=join(root,'source.pptx');await writeFile(path,a);
  await assert.rejects(analyze({project_id:'project_mutation',title:'Mutation',mapping_decisions:[],revisions:[{label:'mutate',files:[path]}]},root,store,undefined,p=>{if(p.phase==='extract'&&p.label==='mutate')writeFileSync(path,b);},{pptxPreview:false}),{code:'SOURCE_CHANGED'});assert.equal(store.reports('project_mutation').length,0);
 }finally{store.close();await rm(root,{recursive:true,force:true});}
});

test('historical44/45 complete net events, selector IDs and evidence replay exact pre50 frozen golden bytes',async()=>{
 const fixture=JSON.parse(await readFile(new URL('../fixtures/lineage-44-45-golden.json',import.meta.url),'utf8'));assert.equal(fixture.source_head,'5c843896528bf392e850ec7057b61364ead349e8');
 for(const item of fixture.fixtures){Report.parse(item.report);const q=new QueryService({} as Store,new Set([item.report.project_id]),()=>item.report);
  for(const request of item.requests){assert.equal(canonical(q.changeSet(request.args)),canonical(request.events));for(const [index,event]of request.events.entries()){const {mode,...args}=request.args;assert.equal(canonical(q.query('get_evidence',{...args,change_id:event.change_id})),canonical(request.evidence[index]));}}
 }
});

test('historical50 supplied-PDF event bytes stay exact while current visual warnings use the correct scope',async()=>{
 const fixture=JSON.parse(await readFile(new URL('../fixtures/bundle-50-golden.json',import.meta.url),'utf8'));assert.equal(fixture.source_head,'a52b651b77be72037323c3e8ace8b0c28a02a80e');Report.parse(fixture.report);
 const old=new QueryService({} as Store,new Set([fixture.report.project_id]),()=>fixture.report);
 for(const request of fixture.requests){const events=old.changeSet(request.args);assert.equal(canonical(events),canonical(request.events));assert.equal(events[0].coverage_gaps[0].feature,'text');for(const [i,event]of events.entries()){const {mode,...args}=request.args;assert.equal(canonical(old.query('get_evidence',{...args,change_id:event.change_id})),canonical(request.evidence[i]));}}
 const current={...fixture.report,engine_version:ENGINE_VERSION},query=new QueryService({} as Store,new Set([current.project_id]),()=>current),events:ReturnType<QueryService['changeSet']>[]=fixture.requests.map((r:{args:unknown})=>query.changeSet(r.args));assert.ok(events.every(rows=>canonical(rows)===canonical(events[0])));assert.equal(events[0][0].coverage_gaps[0].feature,'visual_comparison');assert.equal(events[0][0].appearance_assessment,'inferred');assert.ok(events[0][0].evidence.every(e=>e.method==='provided_pdf_native_raster'&&e.asset_id!==current.revisions[0].pages[0].asset_id));assert.notEqual(events[0][0].change_id,fixture.requests[0].events[0].change_id);
});

test('historical51 complete supplied-PDF events and evidence replay exact immutable52 runtime for all selectors',async()=>{
 const fixture=JSON.parse(await readFile(new URL('../fixtures/bundle-51-golden.json',import.meta.url),'utf8'));assert.equal(fixture.source_head,'9a766aa64b6ada9d1e04aacc9eba07779a0ecdd1');assert.equal(fixture.report.engine_version,'0.3.0-native.bundle.51');Report.parse(fixture.report);
 const q=new QueryService({} as Store,new Set([fixture.report.project_id]),()=>fixture.report);assert.equal(fixture.requests.length,4);
 for(const request of fixture.requests){assert.equal(canonical(q.changeSet(request.args)),canonical(request.events));for(const [index,event]of request.events.entries()){const {mode,...args}=request.args;assert.equal(canonical(q.query('get_evidence',{...args,change_id:event.change_id})),canonical(request.evidence[index]));}}
});

test('actual supplied PDF reordered/hidden bundle skips LO, keeps raw parse cache separate, and persists exact reference through export/reopen',async()=>{
 const root=await mkdtemp(join(tmpdir(),'docver-reference-')),store=new Store(join(root,'store'));try{
  const specs=[{key:'alpha',title:'Alpha strategy',body:'Revenue 100',notes:'Source A'},{key:'bravo',title:'Bravo rollout',body:'Staff 200',notes:'Source B'},{key:'hidden',title:'Hidden appendix',body:'Retain original only',hidden:true,notes:'Hidden source'}],pptx=await makePptx(specs),pdf=await makePdf([specs[1],specs[0]]);const source=join(root,'source.pptx'),reference=join(root,'provided.pdf');await writeFile(source,pptx);await writeFile(reference,pdf);
  let firstBundleHadNoConvertedCache=false;const input={project_id:'project_bundle_real',title:'Reference source',mapping_decisions:[],revisions:[{label:'bundle-first',files:[source,reference]},{label:'standalone',files:[source]},{label:'bundle-after',files:[reference,source]}]};
  const r=(await analyze(input,root,store,undefined,p=>{if(p.phase==='extract'&&p.current===1)firstBundleHadNoConvertedCache=!existsSync(join(store.root,'cache/pptx'));})).report;
  assert.equal(firstBundleHadNoConvertedCache,true);assert.equal(r.revisions[1].pages.filter(p=>p.preview).length,3);
  for(const i of [0,2]){const rev=r.revisions[i],primary=rev.pages.filter(p=>p.asset_id==='sha256:'+byteHash(pptx));assert.equal(primary.filter(p=>p.appearance).length,2,JSON.stringify(rev.coverage_gaps));assert.ok(primary.every(p=>!p.preview&&!p.raster));assert.equal(primary[0].notes,'Source A');assert.equal(primary[2].hidden,true);assert.equal(primary[2].appearance,undefined);assert.equal(primary[0].appearance?.page,2);assert.equal(primary[1].appearance?.page,1);const payload=store.nativePage(r.project_id,r.report_id,primary[0].page_id);assert.equal(payload.reference?.page,2);assert.equal(payload.reference?.asset_id,'sha256:'+byteHash(pdf));}
  assert.equal(byteHash(await readFile(source)),byteHash(pptx));assert.equal(byteHash(await readFile(reference)),byteHash(pdf));assert.equal((await readdir(join(store.root,'cache/pptx'))).filter(f=>f.endsWith('.pdf')).length,1);
  const output=join(root,'export');await exportReport(new QueryService(store,new Set([r.project_id])),r.project_id,r.report_id,output);const exported=JSON.parse(await readFile(join(output,'report.json'),'utf8'));assert.equal(canonical(exported),canonical(r));const before=canonical(store.report(r.project_id,r.report_id));const ro=new Store(store.root,true);try{const q=new QueryService(ro,new Set([r.project_id]));const result=q.query('list_pages',{project_id:r.project_id,report_id:r.report_id,revision_id:r.revisions[0].revision_occurrence_id,max_output_tokens:8000});assert.ok(result.items.some(p=>p.appearance));assert.equal(canonical(ro.report(r.project_id,r.report_id)),before);}finally{ro.close();}
  const modified=await makePptx(specs.map((s,i)=>i===0?{...s,notes:'Changed independent source'}:s)),other=join(root,'other.pptx');await writeFile(other,modified);const rejected=(await analyze({...input,project_id:'project_stale_pdf',revisions:[{label:'a',files:[source,reference]},{label:'b',files:[other,reference]}]},root,store,undefined,undefined,{pptxPreview:false})).report;assert.ok(rejected.revisions.every(r=>!r.pages.some(p=>p.appearance)));assert.ok(rejected.revisions.every(r=>r.coverage_gaps.some(g=>g.reason==='reference_pdf_reused_for_different_pptx')));assert.ok(rejected.revisions.every(r=>!store.nativePage(rejected.project_id,rejected.report_id,r.pages[0].page_id).reference));assert.equal(canonical(store.report(r.project_id,r.report_id)),before);
 }finally{store.close();await rm(root,{recursive:true,force:true});}
});
