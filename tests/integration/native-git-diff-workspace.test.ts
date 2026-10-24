import {nativeLocalizationTestSources, prepareLegacyNativeLocalization} from '../../scripts/native-swift-sources.js';
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {execFileSync} from 'node:child_process';
import {diffWorkbooks, WorkbookRevision} from '../../packages/workbook/diff.js';
import {boundedWorkbookCell} from '../../packages/workbook/query.js';

test('native Git-inspired workspace preserves query/event scope, source semantics, bounded diffs and existing layouts', {skip:process.platform !== 'darwin', timeout:60_000}, async () => {
  const root=await mkdtemp(join(tmpdir(), 'reviset-git-workspace-'));
  try {
    await prepareLegacyNativeLocalization(root);
    const executable=join(root,'probe');
    execFileSync('swiftc', ['-warnings-as-errors','-swift-version','5','-parse-as-library','-target','arm64-apple-macos14.0',...nativeLocalizationTestSources,'apps/macos/Bridge.swift','apps/macos/Model.swift','apps/macos/WorkbookView.swift','tests/native/GitDiffWorkspace.swift','-o',executable,'-framework','SwiftUI','-framework','AppKit'], {timeout:45_000,stdio:'pipe'});
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
    const stdout=execFileSync(executable,[contexts,resolve("tests/fixtures/native-workbook-observation-cases.json")],{encoding:'utf8',timeout:10_000,env:{PATH:'/usr/bin:/bin',DOCVER_TEST_USER_DATA:join(root,'userdata')}});
    assert.match(stdout,/PASS native Git diff workspace:/u);
  } finally {await rm(root,{recursive:true,force:true});}
});
