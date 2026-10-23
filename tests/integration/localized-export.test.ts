import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,readFile,readdir,rm,writeFile} from 'node:fs/promises';
import {join,relative} from 'node:path';
import {tmpdir} from 'node:os';
import {QueryService} from '../../packages/query/index.js';
import {Store} from '../../packages/storage/index.js';
import {canonical,ENGINE_VERSION,SCHEMA_HASH,SCHEMA_VERSION,type ReportData,type PageData,type RevisionData} from '../../packages/schema/index.js';
import {exportReport} from '../../packages/export/index.js';
import {WorkbookService} from '../../packages/workbook/service.js';

const raw='language.system {0} {1} %@ %% 한글 العربية 😀\n```\n![source](https://example.invalid)\n=HYPERLINK("https://example.invalid","raw")';
function documentFixture():ReportData {
  const page=(key:string,text:string):PageData=>({page_id:key,asset_id:'sha256:'+(key==='a'?'a':'b').repeat(64),page:1,width:960,height:540,coordinate_system:'normalized',source_transform:[],hidden:false,text,visible_text:text,notes:raw,
    capabilities:{text:'available',notes:'available',hidden_slides:'available',animation:'unavailable',structure:'available',preview:'unavailable'},coverage_gaps:[],elements:[]});
  const revision=(key:string,p:PageData):RevisionData=>({revision_id:'rev_'+key,revision_occurrence_id:'occ_'+key,label:raw,assets:[{asset_id:p.asset_id,format:'pptx',bytes:0}],status:'success',pages:[p],coverage_gaps:[],errors:[],bundle_mapping:[]});
  const a=revision('a',page('a',raw+' 100')),b=revision('b',page('b',raw+' 101'));
  b.pages.push({...page('c',raw),page:2});
  return {schema_version:SCHEMA_VERSION,engine_version:ENGINE_VERSION,schema_hash:SCHEMA_HASH,report_id:'rpt_localized_export',project_id:'prj_localized_export',timeline_revision_id:'timeline',mapping_revision_id:'mapping',observation_environment:{fixture:'explicit-language-export'},
    revisions:[a,b],matches:['b','c'].map(to_page_id=>({from_page_id:'a',to_page_id,score:1,status:'human_confirmed',reasons:[raw]})),candidates:[],mapping_decisions:[],mapping_relations:[{relation_id:'rel_localized_split',kind:'split',from_occurrence:'occ_a',to_occurrence:'occ_b',from_page_ids:['a'],to_page_ids:['b','c'],reason:raw}],lineages:[{entity_id:'family',page_ids:['a','b','c'],status:'human_confirmed'}],
    changes:[{schema_version:SCHEMA_VERSION,report_id:'rpt_localized_export',change_id:'chg_localized',entity_id:'family',from_revision:a.revision_id,to_revision:b.revision_id,from_occurrence:a.revision_occurrence_id,to_occurrence:b.revision_occurrence_id,kind:'text_modified',before:a.pages[0].text,after:b.pages[0].text,text_assessment:'observed',appearance_assessment:'observed',lineage:{status:'human_confirmed',score:1,reasons:[raw]},evidence:[],coverage_gaps:[{feature:'fixture',reason:raw}],evidence_uri:'docver://projects/prj_localized_export/reports/rpt_localized_export/changes/chg_localized'}],coverage_gaps:[]};
}
async function files(folder:string){return (await readdir(folder,{recursive:true,withFileTypes:true})).filter(entry=>entry.isFile()).map(entry=>join(entry.parentPath,entry.name)).sort();}

test('document export language changes human copy while all JSON, raw source and MCP reads stay identical',async()=>{
  const root=await mkdtemp(join(tmpdir(),'reviset-export-languages-'));
  try {
    const report=documentFixture(),before=canonical(report),query=new QueryService({} as Store,new Set([report.project_id]),()=>report);
    const args={project_id:report.project_id,report_id:report.report_id,revision_id:'occ_a',page_id:'a',section:'source',max_output_tokens:8000};
    const reading=canonical(query.query('get_page_content',args));
    for(const language of ['en','ko'] as const)assert.equal(await exportReport(query,report.project_id,report.report_id,join(root,language),language),report.report_id);
    await exportReport(query,report.project_id,report.report_id,join(root,'legacy'));
    const en=await readFile(join(root,'en/history.md'),'utf8'),ko=await readFile(join(root,'ko/history.md'),'utf8');
    assert.match(en,/^# Change history/u);assert.match(ko,/^# 변경 이력/u);
    assert.match(en,/- split · rel_localized_split · 1 page → 2 pages\n/u);assert.doesNotMatch(en,/1 pages/u);
    assert.match(ko,/- split · rel_localized_split · 1쪽 → 2쪽\n/u);
    const quoted=raw.split('\n').map(line=>'> '+line).join('\n');
    for(const folder of ['en','ko']){
      const history=await readFile(join(root,folder,'history.md'),'utf8');assert.ok(history.includes(quoted));
      for(const path of await files(join(root,folder)))if(path.endsWith('.md')&&path.includes('/content/'))assert.ok((await readFile(path,'utf8')).includes(quoted));
    }
    for(const path of await files(join(root,'en'))){
      const name=relative(join(root,'en'),path);
      if(!name.endsWith('.md'))assert.deepEqual(await readFile(path),await readFile(join(root,'ko',name)),name+' canonical export changed with language');
    }
    for(const path of await files(join(root,'ko'))){const name=relative(join(root,'ko'),path);assert.deepEqual(await readFile(path),await readFile(join(root,'legacy',name)),'legacy default '+name);}
    assert.equal(canonical(report),before);assert.equal(canonical(query.query('get_page_content',args)),reading);
    await assert.rejects(exportReport(query,report.project_id,report.report_id,join(root,'invalid'),'fr' as 'en'),{code:'INVALID_EXPORT_LANGUAGE'});
    assert.ok(!(await readdir(root)).includes('invalid'));
  }finally{await rm(root,{recursive:true,force:true});}
});

test('workbook locale exports coexist without changing content IDs, JSON, source bytes or release reasons',async()=>{
  const root=await mkdtemp(join(tmpdir(),'reviset-workbook-export-languages-')),store=new Store(join(root,'library'));
  try {
    const service=new WorkbookService(store),paths=[];
    for(const number of [100,101]){
      const path=join(root,number+'.csv'),text='id,value,amount\na,"'+raw.replace(/"/gu,'""')+'",'+number+'\n';await writeFile(path,text);paths.push(path);
    }
    const draft=await service.create(raw,paths.map((path,index)=>({path,label:'language.system '+index}))),stage=await service.run(draft.project_id);await service.commit(draft.project_id,stage);
    service.publish(draft.project_id,stage.report_id,raw,raw);
    const report=canonical(service.report(draft.project_id,stage.report_id)),releases=canonical(service.releases(draft.project_id)),folder=join(root,'out');
    const en=await service.export(draft.project_id,stage.report_id,folder,'en');
    const machinePaths=(await files(folder)).filter(path=>!path.endsWith('.md'));
    assert.deepEqual(machinePaths,[...en.files.filter(path=>!path.endsWith('.md')),...draft.revisions.map(revision=>join(folder,revision.asset_id.slice(7)+'.'+revision.format))].sort());
    // Freeze bytes before a second export can quarantine and replace changed content at the same paths.
    const machineBytes=new Map(await Promise.all(machinePaths.map(async path=>[relative(folder,path),await readFile(path)] as const)));
    for(const [index,revision] of draft.revisions.entries())assert.deepEqual(machineBytes.get(revision.asset_id.slice(7)+'.'+revision.format),await readFile(paths[index]),'copied source bytes');
    const englishPath=en.files.find(path=>path.endsWith('.md'))!,english=await readFile(englishPath,'utf8');
    const assertFrozenBytes=async()=>{
      assert.deepEqual((await files(folder)).filter(path=>!path.endsWith('.md')),machinePaths);
      for(const [name,bytes] of machineBytes)assert.deepEqual(await readFile(join(folder,name)),bytes,name+' changed after another language export');
      assert.equal(await readFile(englishPath,'utf8'),english,'English Markdown changed after another language export');
    };
    const ko=await service.export(draft.project_id,stage.report_id,folder,'ko');
    await assertFrozenBytes();
    assert.equal(en.export_id,ko.export_id);assert.equal(en.report_id,ko.report_id);
    assert.deepEqual(en.files.filter(path=>!path.endsWith('.md')),ko.files.filter(path=>!path.endsWith('.md')));
    const korean=await readFile(ko.files.find(path=>path.endsWith('.ko.md'))!,'utf8');
    assert.match(english,/^# Workbook version comparison/u);assert.match(korean,/^# 스프레드시트 버전 비교/u);
    const quoted=raw.split('\n').map(line=>'> '+line).join('\n');assert.ok(english.includes(quoted));assert.ok(korean.includes(quoted));
    assert.equal(canonical(service.report(draft.project_id,stage.report_id)),report);assert.equal(canonical(service.releases(draft.project_id)),releases);
    assert.deepEqual((await service.export(draft.project_id,stage.report_id,folder)).files,en.files);
    await assertFrozenBytes();
    await assert.rejects(service.export(draft.project_id,stage.report_id,join(root,'invalid'),'fr' as 'en'),{code:'INVALID_EXPORT_LANGUAGE'});
    assert.ok(!(await readdir(root)).includes('invalid'));
  }finally{store.close();await rm(root,{recursive:true,force:true});}
});
