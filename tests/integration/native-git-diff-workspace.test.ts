import {nativeSwiftSources, prepareLegacyNativeLocalization} from '../../scripts/native-swift-sources.js';
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, rm, writeFile, readFile,mkdir,copyFile,symlink} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {execFileSync,spawnSync} from 'node:child_process';
import {diffWorkbooks, WorkbookRevision} from '../../packages/workbook/diff.js';
import {boundedWorkbookCell} from '../../packages/workbook/query.js';

test('native Git-inspired workspace preserves query/event scope, source semantics, bounded diffs and existing layouts', {skip:process.platform !== 'darwin', timeout:75_000}, async () => {
  const root=await mkdtemp(join(tmpdir(), 'reviset-git-workspace-'));
  try {
    await prepareLegacyNativeLocalization(root);
    const executable=join(root,'probe');
    execFileSync('swiftc', ['-warnings-as-errors','-swift-version','5','-parse-as-library','-target','arm64-apple-macos14.0',...nativeSwiftSources.filter(source=>source!=='apps/macos/App.swift'),'tests/native/LocalizationTestSupport.swift','tests/native/GitDiffWorkspace.swift','-o',executable,'-framework','SwiftUI','-framework','AppKit'], {timeout:45_000,stdio:'pipe'});
    const revision=(id:string,format:'xlsx'|'ods',value:string,formula:string,withDate=false,keyed=true)=>WorkbookRevision.parse({
      revision_occurrence_id:id,label:id,index:id==='before'?0:1,asset_id:'sha256:'+'a'.repeat(64),format,date_system:format==='ods'?'iso8601':'1900',calc_flags:{},coverage_gaps:[],calculation:'stored_values_only_no_recalculation',
      sheets:[{sheet_id:id+'_sheet',name:'Sheet',index:0,hidden:false,row_count:1,column_count:2,merges:[],coverage_gaps:[],source_ref:id,row_metadata:[],column_metadata:[],cell_extraction_complete:true,cells:[
        ...(keyed?[{address:'A1',row:1,column:1,value_type:'string',value:'SKU001',formula:null,number_format:null,style:{},cached_result:'not_applicable',cache_freshness:'not_applicable',formula_dialect:null,formula_interpretation:'not_formula',hidden_row:false,hidden_column:false,source_ref:id+'!A1'}]:[]),
        {address:'B1',row:1,column:2,value_type:'number',value,formula,number_format:withDate?(format==='xlsx'?'yyyy-mm-dd':'ods:{"name":"date-style"}'):null,style:{},cached_result:'present',cache_freshness:'unknown',formula_dialect:format==='xlsx'?'xlsx_a1':'ods_openformula',formula_interpretation:'explicit',hidden_row:false,hidden_column:false,source_ref:id+'!B1'},
      ]}],
    });
    const dates=[revision('before','xlsx','45292','SUM(C1)',true),revision('after','ods','45293','of:=SUM([.C1])',true)] as const;
    const dateEvents=diffWorkbooks(...dates);
    assert.deepEqual(dateEvents.map(event=>event.kind),['date_system','cell_observation']);
    assert.equal(dateEvents[1]!.alignment_method,'cross_format_date_representation');
    const ordinaryValue=[revision('before','xlsx','100','SUM(C1)'),revision('after','xlsx','120','SUM(C1)')] as const;
    const ordinaryFormula=[revision('before','xlsx','100','SUM(C1)'),revision('after','xlsx','100','SUM(C2)')] as const;
    const uncertainAssociation=[revision('before','xlsx','100','SUM(C1)',false,false),revision('after','xlsx','120','SUM(C1)',false,false)] as const;
    const cases=[
      ...dateEvents.map(change=>({name:'cross-format-'+change.kind,before:boundedWorkbookCell(dates[0].sheets[0]!.cells.find(cell=>cell.address==='B1')!,0,4096),after:boundedWorkbookCell(dates[1].sheets[0]!.cells.find(cell=>cell.address==='B1')!,0,4096),change,eligible_field:''})),
      ...[ [ordinaryValue,'stored_value','value'],[ordinaryFormula,'formula','formula'],[uncertainAssociation,'stored_value',''] ].map(([pair,kind,eligible_field])=>{
        const revisions=pair as typeof ordinaryValue,change=diffWorkbooks(...revisions).find(event=>event.kind===kind)!;
        assert.ok(change,'engine must emit the selected field event');
        return {name:String(kind)+'-'+String(eligible_field),before:boundedWorkbookCell(revisions[0].sheets[0]!.cells.find(cell=>cell.address==='B1')!,0,4096),after:boundedWorkbookCell(revisions[1].sheets[0]!.cells.find(cell=>cell.address==='B1')!,0,4096),change,eligible_field};
      }),
    ];
    const contexts=join(root,'engine-contexts.json');await writeFile(contexts,JSON.stringify(cases));
    const oneSidedResources=join(root,'one-sided','Resources');await mkdir(join(oneSidedResources,'backend'),{recursive:true});await mkdir(join(root,'one-sided','Helpers'),{recursive:true});await symlink(process.execPath,join(root,'one-sided','Helpers','node'));await copyFile(resolve('tests/native/workbook-read-fixture.mjs'),join(oneSidedResources,'backend','bridge.mjs'));
    const run=spawnSync(executable,[contexts,resolve("tests/fixtures/native-workbook-observation-cases.json")],{encoding:'utf8',timeout:40_000,env:{PATH:'/usr/bin:/bin',DOCVER_TEST_USER_DATA:join(root,'userdata'),DOCVER_TEST_ONE_SIDED_RESOURCES:oneSidedResources}});
    assert.equal(run.status,0,run.error?.message ?? run.stderr);assert.match(run.stdout,/PASS native Git diff workspace:/u,run.stderr);
    const source16Evidence=await readFile(join(root,'userdata','source16-proof.json'),'utf8');
    const source16=JSON.parse(source16Evidence) as {observations:unknown[];metadata_caption_has_no_cell_warning_or_field_rows:boolean};assert.equal(source16.observations.length,2);assert.equal(source16.metadata_caption_has_no_cell_warning_or_field_rows,true);
    if(process.env.DOCVER_TEST_SOURCE16_EVIDENCE_OUT) await writeFile(process.env.DOCVER_TEST_SOURCE16_EVIDENCE_OUT,source16Evidence);
    const source17Evidence=await readFile(join(root,'userdata','source17-proof.json'),'utf8');
    const source17=JSON.parse(source17Evidence) as {workbook_cases:unknown[];document_cases:unknown[];partial_and_missing_not_claimed_eof:boolean;raw_utf16_preserved:boolean};
    assert.equal(source17.workbook_cases.length,7);assert.equal(source17.document_cases.length,2);assert.equal(source17.partial_and_missing_not_claimed_eof,true);assert.equal(source17.raw_utf16_preserved,true);
    if(process.env.DOCVER_TEST_SOURCE17_EVIDENCE_OUT) await writeFile(process.env.DOCVER_TEST_SOURCE17_EVIDENCE_OUT,source17Evidence);
    const contextEvidence=await readFile(join(root,'userdata','context-geometry.json'),'utf8');
    const context=JSON.parse(contextEvidence) as {summary_height:number;source_height:number;reason_utf16_count:number;full_reader_utf16:number[];expected_utf16:number[];reader_height:number;reader_viewport_height:number};
    assert.ok(context.summary_height>=46 && context.summary_height<=140 && context.source_height>400);
    assert.equal(context.reason_utf16_count,1998);assert.deepEqual(context.full_reader_utf16,context.expected_utf16);
    assert.ok(context.reader_height>context.reader_viewport_height);
    if(process.env.DOCVER_TEST_CONTEXT_EVIDENCE_OUT) await writeFile(process.env.DOCVER_TEST_CONTEXT_EVIDENCE_OUT,contextEvidence);
    const pagerEvidence=await readFile(join(root,'userdata','pager-proof.json'),'utf8');
    const pager=JSON.parse(pagerEvidence) as {message_observations:{language:string;mode:string;route:string;revision_count:number}[]};
    assert.equal(pager.message_observations.length,8);
    assert.equal(new Set(pager.message_observations.map(item=>[item.language,item.mode,item.route].join('/'))).size,8);
    assert.ok(pager.message_observations.every(item=>item.revision_count===3));
    if(process.env.DOCVER_TEST_PAGER_EVIDENCE_OUT) await writeFile(process.env.DOCVER_TEST_PAGER_EVIDENCE_OUT,pagerEvidence);
    const gridEvidence=await readFile(join(root,'userdata','grid-source-proof.json'),'utf8');
    if(process.env.DOCVER_TEST_GRID_EVIDENCE_OUT) await writeFile(process.env.DOCVER_TEST_GRID_EVIDENCE_OUT,gridEvidence);
    const readingEvidence=await readFile(join(root,'userdata','workbook-reading-proof.json'),'utf8');
    const reading=JSON.parse(readingEvidence) as {observations:{language:string;route:string;revision_count:number;native_message_field_verified:boolean}[]};
    assert.equal(reading.observations.length,6);assert.equal(new Set(reading.observations.map(item=>[item.language,item.route].join('/'))).size,6);
    assert.ok(reading.observations.every(item=>item.native_message_field_verified));
    if(process.env.DOCVER_TEST_WORKBOOK_READING_EVIDENCE_OUT) await writeFile(process.env.DOCVER_TEST_WORKBOOK_READING_EVIDENCE_OUT,readingEvidence);
    const headerEvidence=await readFile(join(root,'userdata','hidden-header-proof.json'),'utf8');
    const headers=JSON.parse(headerEvidence) as {observations:{workspace:string;language:string}[]};
    assert.equal(headers.observations.length,4);assert.equal(new Set(headers.observations.map(item=>[item.workspace,item.language].join('/'))).size,4);
    if(process.env.DOCVER_TEST_HIDDEN_HEADER_EVIDENCE_OUT) await writeFile(process.env.DOCVER_TEST_HIDDEN_HEADER_EVIDENCE_OUT,headerEvidence);
    const reviewEvidence=await readFile(join(root,'userdata','review13-proof.json'),'utf8');
    if(process.env.DOCVER_TEST_REVIEW13_EVIDENCE_OUT) await writeFile(process.env.DOCVER_TEST_REVIEW13_EVIDENCE_OUT,reviewEvidence);
    const oneSidedEvidence=await readFile(join(root,'userdata','one-sided-proof.json'),'utf8');
    if(process.env.DOCVER_TEST_ONE_SIDED_EVIDENCE_OUT) await writeFile(process.env.DOCVER_TEST_ONE_SIDED_EVIDENCE_OUT,oneSidedEvidence);
    const rawEvidence=await readFile(join(root,'userdata','raw-fallback-proof.json'),'utf8');
    if(process.env.DOCVER_TEST_RAW_FALLBACK_EVIDENCE_OUT) await writeFile(process.env.DOCVER_TEST_RAW_FALLBACK_EVIDENCE_OUT,rawEvidence);
  } finally {await rm(root,{recursive:true,force:true});}
});
