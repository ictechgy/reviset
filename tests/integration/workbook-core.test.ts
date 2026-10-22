import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, readFile, writeFile, rm, stat, readdir } from 'node:fs/promises';
import { mkdirSync,renameSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { Store } from '../../packages/storage/index.js';
import { byteHash, canonical } from '../../packages/schema/index.js';
import { WorkbookService,validateIdentity,MAX_WORKBOOK_REPORT_BYTES } from '../../packages/workbook/service.js';
import { WorkbookQueryService,boundedWorkbookNetCacheBytes } from '../../packages/workbook/query.js';
import { diffWorkbooks, type WorkbookRevisionData } from '../../packages/workbook/diff.js';
import { extractWorkbook } from '../../packages/workbook/ingest.js';
import { cellAddress,workbookID, type WorkbookCellData, type WorkbookSheetData } from '../../packages/workbook/types.js';
import { handleWorkbookAction } from '../../apps/bridge/workbook.js';
import { xlsxFixture,odsFixture,xmlEscape,workbookStyles } from '../workbook-fixtures.js';

function cell(row: number, column: number, value: string | null, extra: Partial<WorkbookCellData> = {}): WorkbookCellData {
  return { row, column, address: cellAddress(row,column), value_type: 'string', value, formula: null, number_format: null, style: {}, hidden_row: false, hidden_column: false, cached_result: 'not_applicable', cache_freshness: 'not_applicable', formula_dialect: null, source_ref: 'independent-source!' + cellAddress(row,column), ...extra };
}
function sheet(id: string, cells: WorkbookCellData[], extra: Partial<WorkbookSheetData> = {}): WorkbookSheetData {
  return { sheet_id: id, name: 'Budget', index: 0, hidden: false, cells, row_count: Math.max(0,...cells.map(c => c.row)), column_count: Math.max(0,...cells.map(c => c.column)), merges: [], row_metadata: [], column_metadata: [], cell_extraction_complete: true, source_ref: 'independent-source/Budget', coverage_gaps: [], ...extra };
}
function revision(id: string, cells: WorkbookCellData[], extra: Partial<WorkbookRevisionData> = {}): WorkbookRevisionData { return { format: 'xlsx', revision_occurrence_id: id, label: id, index: id === 'before' ? 0 : 1, asset_id: 'sha256:' + 'a'.repeat(64), sheets: [sheet('sheet_' + id,cells)], coverage_gaps: [], calculation: 'stored_values_only_no_recalculation', date_system: '1900', calc_flags: {}, ...extra }; }
const wire = (result: Record<string,any>) => ({ structuredContent: result, content: [{type:'text',text:JSON.stringify(result)}] });
const wireBytes = (result: Record<string,any>) => Buffer.byteLength(JSON.stringify(wire(result)));
async function fixture(inputs: string[] = ['id,amount\na,100\n','id,amount\na,120\n','id,amount\na,100\n']) {
  const root = await mkdtemp(join(tmpdir(),'docver-workbook-core-')); await mkdir(join(root,'inputs'));
  const paths: string[] = []; for (const [i,input] of inputs.entries()) { const path = join(root,'inputs',i+'.csv'); await writeFile(path,input); paths.push(path); }
  const store = new Store(join(root,'library')), service = new WorkbookService(store), draft = await service.create('Budget',[...paths].map((path,i) => ({path,label:'v'+(i+1),expected_sha256:byteHash(Buffer.from(inputs[i]))}))), stage = await service.run(draft.project_id); await service.commit(draft.project_id,stage);
  const report = service.report(draft.project_id,stage.report_id), q = new WorkbookQueryService(service,new Set([draft.project_id]));
  return {root,paths,store,service,draft,stage,report,q,close:async()=>{store.close();await rm(root,{recursive:true,force:true});}};
}

test('the real bridge rejects a writerless FIFO promptly without retaining a workbook, report or asset', {skip: process.platform === 'win32'}, async()=>{
  const {spawnSync}=await import('node:child_process'),root=await mkdtemp(join(tmpdir(),'docver-workbook-fifo-')),path=join(root,'named-pipe.xlsx'),library=join(root,'library');
  try {
    const fifo=spawnSync('/usr/bin/mkfifo',[path],{encoding:'utf8',timeout:2000});assert.ifError(fifo.error);assert.equal(fifo.status,0,fifo.stderr);
    // A blocking O_RDONLY open would wait forever for a writer. The child
    // timeout makes that regression fail without hanging the test runner.
    const result=spawnSync(process.execPath,['--import','tsx',join(process.cwd(),'apps/bridge/main.ts'),'--root',library],{input:JSON.stringify({action:'workbookCreate',args:{title:'Nonregular input',revisions:[{label:'pipe',path}]}}),encoding:'utf8',timeout:8000});
    assert.ifError(result.error);assert.equal(result.status,1,result.stderr);const response=JSON.parse(result.stdout);assert.equal(response.ok,false);assert.equal(response.error.code,'WORKBOOK_INPUT_LIMIT');
    const store=new Store(library),service=new WorkbookService(store);try {
      assert.deepEqual(service.projects(),[]);for(const table of ['workbook_reports_v1','workbook_runs_v1','workbook_cells_v1'])assert.equal(store.db.prepare('SELECT count(*) AS n FROM '+table).get()!.n,0);
      assert.deepEqual(await readdir(join(library,'assets')).catch((error:NodeJS.ErrnoException)=>{if(error.code==='ENOENT')return [];throw error;}),[]);
      const regular=join(root,'ordinary.csv'),bytes=Buffer.from('id,value\na,1\n');await writeFile(regular,bytes);const draft=await service.create('Regular control',[{label:'regular',path:regular,expected_sha256:byteHash(bytes)}]);assert.equal(draft.revisions[0].asset_id,'sha256:'+byteHash(bytes));
    }finally{store.close();}
  }finally{await rm(root,{recursive:true,force:true});}
});

test('workbook diff separates formulas, cached results, exact decimals, blanks, types, styles and hidden metadata without executing anything',()=>{
  const before = revision('before',[cell(1,1,'a'),cell(1,2,'10',{value_type:'number',formula:'SUM(C1:D1)',formula_dialect:'xlsx_a1',cached_result:'present',cache_freshness:'unknown'}),cell(1,3,'9007199254740993',{value_type:'number'}),cell(1,4,'1.0',{value_type:'number'}),cell(1,5,null,{value_type:'blank'}),cell(1,6,'x',{style:{'font.bold':'true'}})]);
  const after = revision('after',[cell(1,1,'a'),cell(1,2,'10',{value_type:'number'}),cell(1,3,'9007199254740992',{value_type:'number'}),cell(1,4,'1e0',{value_type:'number'}),cell(1,5,'0',{value_type:'number'}),cell(1,6,'x',{style:{'font.bold':'false'},hidden_row:true})]);
  after.sheets[0].row_metadata=[{start:100,end:120,hidden:true,size:null}];after.sheets[0].merges=['A5:C5'];
  const changes = diffWorkbooks(before,after);
  assert.ok(changes.some(c=>c.kind==='formula'&&c.before_address==='B1'&&c.before?.formula==='SUM(C1:D1)'&&c.after?.formula===null));
  assert.ok(changes.some(c=>c.kind==='stored_value'&&c.before_address==='C1')); // no IEEE-754 collapse
  assert.ok(!changes.some(c=>c.kind==='stored_value'&&c.before_address==='D1')); // exact decimal equivalence
  assert.ok(changes.some(c=>c.kind==='value_type'&&c.before_address==='E1'));
  assert.ok(changes.some(c=>c.kind==='style'));assert.ok(changes.some(c=>c.kind==='visibility'));assert.ok(changes.some(c=>c.kind==='sheet_dimensions'));assert.ok(changes.some(c=>c.kind==='merges'));
  const missing=structuredClone(before);missing.revision_occurrence_id='missing';missing.sheets[0].cells[1].value=null;missing.sheets[0].cells[1].cached_result='missing';
  assert.ok(diffWorkbooks(before,missing).some(c=>c.description.includes('missing cache is not a deleted cell')));
  assert.ok(diffWorkbooks(before,missing).some(c=>c.kind==='cache_availability'));assert.ok(!diffWorkbooks(before,missing).some(c=>c.kind==='stored_value'&&c.before_address==='B1'));
  const boolA=revision('before',[cell(1,1,'k'),cell(1,2,'1',{value_type:'boolean'})]),boolB=revision('after',[cell(1,1,'k'),cell(1,2,'true',{value_type:'boolean'})]);boolB.calc_flags={calcMode:'manual'};const boolDiff=diffWorkbooks(boolA,boolB);assert.ok(!boolDiff.some(c=>c.kind==='stored_value'));assert.ok(boolDiff.some(c=>c.kind==='calculation_settings'));
});

test('raw XLSX formula caches becoming empty or absent change availability without asserting a result type edit',async()=>{
  const source=(cache:string,type='')=>xlsxFixture('<sheetData><row r="1"><c r="A1" t="inlineStr"><is><t>key</t></is></c><c r="B1"'+(type?' t="'+type+'"':'')+'><f t="normal">IF(A1=&quot;key&quot;,1,&quot;1&quot;)</f>'+cache+'</c></row></sheetData>');
  const observations=await Promise.all([source('<v>1</v>'),source('<v/>'),source(''),source('<v>1</v>','str')].map(bytes=>extractWorkbook(bytes,'xlsx'))),revisions=observations.map((observation,index):WorkbookRevisionData=>({...observation,revision_occurrence_id:'cache_'+index,label:'cache '+index,index,asset_id:'sha256:'+String(index).repeat(64)}));
  const observedCell=(index:number)=>revisions[index].sheets[0].cells.find(c=>c.address==='B1')!;
  assert.equal(observedCell(0).value_type,'number');assert.equal(observedCell(0).cached_result,'present');
  for(const missing of [1,2]){
    assert.equal(observedCell(missing).value,null);assert.equal(observedCell(missing).value_type,'blank');assert.equal(observedCell(missing).cached_result,'missing');assert.equal(observedCell(missing).formula_interpretation,'explicit');
    for(const [before,after]of [[0,missing],[missing,0]]){const changes=diffWorkbooks(revisions[before],revisions[after]);assert.deepEqual(changes.map(c=>c.kind),['cache_availability']);assert.ok(changes.every(c=>c.before?.formula===c.after?.formula));}
  }
  const resolvedTypeChange=diffWorkbooks(revisions[0],revisions[3]);assert.equal(observedCell(3).cached_result,'present');assert.equal(observedCell(3).value_type,'string');assert.ok(resolvedTypeChange.some(c=>c.kind==='value_type'&&c.before_address==='B1'));assert.ok(!resolvedTypeChange.some(c=>c.kind==='cache_availability'));
  const changedFormula=structuredClone(revisions[1]),changedCell=changedFormula.sheets[0].cells.find(c=>c.address==='B1')!;changedCell.formula='2';changedCell.number_format='0.0';changedCell.hidden_row=true;const knownEdits=diffWorkbooks(revisions[0],changedFormula);assert.ok(knownEdits.some(c=>c.kind==='formula'));assert.ok(knownEdits.some(c=>c.kind==='number_format'));assert.ok(knownEdits.some(c=>c.kind==='visibility'));assert.ok(!knownEdits.some(c=>c.kind==='value_type'||c.kind==='stored_value'));
});

test('inferred unique keys preserve physical row moves; duplicate keys never establish certain lineage or false semantic deletion',()=>{
  const a=revision('before',[cell(1,1,'a'),cell(1,2,'10'),cell(2,1,'b'),cell(2,2,'20')]);
  const b=revision('after',[cell(1,1,'new'),cell(1,2,'0'),cell(2,1,'b'),cell(2,2,'21'),cell(3,1,'a'),cell(3,2,'10')]);
  const changes=diffWorkbooks(a,b),move=changes.find(c=>c.kind==='row_position'&&c.before_address==='A1');assert.equal(move?.after_address,'A3');assert.equal(move?.association,'inferred');
  const edited=changes.find(c=>c.kind==='stored_value'&&c.before_address==='B2');assert.equal(edited?.after_address,'B2');assert.equal(edited?.alignment_method,'unique_nonempty_first_column_key');
  const duplicate=diffWorkbooks(revision('before',[cell(1,1,'same'),cell(1,2,'x'),cell(2,1,'same'),cell(2,2,'x')]),revision('after',[cell(1,1,'same'),cell(1,2,'y'),cell(2,1,'same'),cell(2,2,'y')]));
  assert.ok(duplicate.length>0);assert.ok(duplicate.every(c=>c.association==='needs_review'));assert.ok(duplicate.every(c=>!c.kind.includes('deleted')));
  const unmatched=diffWorkbooks(a,revision('after',[],{sheets:[sheet('different',[],{name:'Unrelated'})]}));assert.ok(unmatched.every(c=>c.kind==='sheet_observation'&&c.association==='needs_review'));
});

test('cross-format dialect/type gaps are not interpreted as formula/style deletions; date basis changes stay explicit',()=>{
  const a=revision('before',[cell(1,1,'key'),cell(1,2,'1',{value_type:'number',formula:'SUM(C1)',formula_dialect:'xlsx_a1',cached_result:'present',cache_freshness:'unknown',style:{bold:'true'}})]);
  const b=revision('after',[cell(1,1,'key'),cell(1,2,'1',{value_type:'number',formula:'of:=SUM([.C1])',formula_dialect:'ods_openformula',cached_result:'present',cache_freshness:'unknown',style:{'text-properties.font-weight':'bold'},number_format:'ods-number:1'})],{format:'ods',date_system:'iso8601'});b.sheets[0].row_metadata=[{start:1,end:1,hidden:false,size:'0.5cm'}];
  assert.ok(!diffWorkbooks(a,b).some(c=>['formula','style','number_format','sheet_dimensions'].includes(c.kind)));assert.ok(diffWorkbooks(a,b).some(c=>c.kind==='date_system'&&c.association==='needs_review'));
  const csv=revision('after',[cell(1,1,'key'),cell(1,2,'1')],{format:'csv',date_system:'unknown'});assert.ok(!diffWorkbooks(a,csv).some(c=>['formula','value_type','style','visibility','number_format'].includes(c.kind)));
  a.sheets[0].hidden=true;a.sheets[0].merges=['A1:B1'];for(const [left,right]of [[a,csv],[csv,a]] as const)assert.ok(!diffWorkbooks(left,right).some(c=>['sheet_visibility','merges','sheet_name','sheet_position'].includes(c.kind)));
  const serial=revision('before',[cell(1,1,'key'),cell(1,2,'45292',{value_type:'number',number_format:'yyyy-mm-dd'})]),iso=revision('after',[cell(1,1,'key'),cell(1,2,'2024-01-01',{value_type:'date'})],{format:'ods',date_system:'iso8601'});
  for(const [left,right]of [[serial,iso],[iso,serial]] as const){const changes=diffWorkbooks(left,right);assert.ok(!changes.some(c=>['stored_value','value_type'].includes(c.kind)));assert.ok(changes.some(c=>c.kind==='cell_observation'&&c.association==='needs_review'&&c.alignment_method==='cross_format_date_representation'));}
});

test('ODS numeric/currency/percentage format vocabulary cannot hide real cross-format value changes while genuine date/time styles remain reviewable',()=>{
  for(const [kind,xlsxFormat]of [['number-style','0.00'],['currency-style','"USD"0.00'],['percentage-style','0.00%']]as const){
    const xlsx=revision('before',[cell(1,1,'key'),cell(1,2,'100',{value_type:'number',number_format:xlsxFormat})]);
    const ods=revision('after',[cell(1,1,'key'),cell(1,2,'120',{value_type:'number',number_format:'ods:'+JSON.stringify({name:kind,attrs:{name:'has-days-and-seconds-in-a-label'},content:[]})})],{format:'ods',date_system:'iso8601'});
    for(const [left,right]of [[xlsx,ods],[ods,xlsx]]as const){const changes=diffWorkbooks(left,right);assert.ok(changes.some(c=>c.kind==='stored_value'&&c.before_address==='B1'&&c.after_address==='B1'),kind);assert.ok(!changes.some(c=>c.alignment_method==='cross_format_date_representation'),kind);}
  }
  for(const kind of ['date-style','time-style']){
    const xlsx=revision('before',[cell(1,1,'key'),cell(1,2,'45292',{value_type:'number',number_format:'General'})]);
    const ods=revision('after',[cell(1,1,'key'),cell(1,2,'45293',{value_type:'number',number_format:'ods:'+JSON.stringify({name:kind,attrs:{},content:[]})})],{format:'ods',date_system:'iso8601'});
    for(const [left,right]of [[xlsx,ods],[ods,xlsx]]as const){const changes=diffWorkbooks(left,right);assert.ok(changes.some(c=>c.kind==='cell_observation'&&c.alignment_method==='cross_format_date_representation'&&c.association==='needs_review'));assert.ok(!changes.some(c=>c.kind==='stored_value'||c.kind==='value_type'));}
  }
});

test('interned styles compare semantic definitions, reject broken references, and leave raw inline legacy cells supported',()=>{
  const oldStyle={'font.name.val':'Calibri'},newStyle={'font.name.val':'Aptos'},oldRef=workbookID('wstyle',oldStyle),newRef=workbookID('wstyle',newStyle);
  const a=revision('before',[cell(1,1,'key'),cell(1,2,'1',{style:{},style_ref:oldRef})],{style_definitions:{[oldRef]:oldStyle}}),b=revision('after',[cell(1,1,'key'),cell(1,2,'1',{style:{},style_ref:newRef})],{style_definitions:{[newRef]:newStyle}});
  const changes=diffWorkbooks(a,b);assert.ok(changes.some(c=>c.kind==='style'&&c.before?.style_ref===oldRef&&c.after?.style_ref===newRef));assert.deepEqual(changes.find(c=>c.kind==='style')?.before?.style,{});
  const missing=structuredClone(b);missing.style_definitions={};assert.throws(()=>diffWorkbooks(a,missing),{code:'WORKBOOK_STYLE_SCOPE'});
  assert.ok(diffWorkbooks(revision('before',[cell(1,1,'key'),cell(1,2,'1',{style:oldStyle})]),revision('after',[cell(1,1,'key'),cell(1,2,'1',{style:newStyle})])).some(c=>c.kind==='style'));
});

test('a large style reused by 1000 cells stays interned during sheet/row matching and still exposes semantic style changes',()=>{
  const style=Object.fromEntries(Array.from({length:256},(_,i)=>['property_'+i,'x'.repeat(4096)])),reference=workbookID('wstyle',style);
  const cells=Array.from({length:1000},(_,i)=>cell(i+1,2,'row-'+i,{style:{},style_ref:reference})),before=revision('before',cells,{style_definitions:{[reference]:style}}),after=revision('after',structuredClone(cells),{style_definitions:{[reference]:style}});after.sheets[0].name='Renamed';
  assert.ok(Buffer.byteLength(canonical({revisions:[before,after]}))<256*1024*1024);
  const renamed=diffWorkbooks(before,after);assert.equal(renamed.filter(c=>c.kind==='sheet_name').length,1);assert.ok(!renamed.some(c=>c.kind==='sheet_observation'||c.kind==='style'||c.kind==='stored_value'));
  const moved=revision('after',cells.map(c=>({...c,row:c.row+1,address:cellAddress(c.row+1,c.column)})),{style_definitions:{[reference]:style}}),moves=diffWorkbooks(before,moved);assert.equal(moves.filter(c=>c.kind==='row_position').length,1000);assert.ok(moves.every(c=>c.alignment_method==='unique_exact_row_content'));
  const changedStyle={...style,property_0:'y'.repeat(4096)},changedReference=workbookID('wstyle',changedStyle),changed=revision('after',cells.map((c,i)=>i===500?{...c,style_ref:changedReference}:c),{style_definitions:{[reference]:style,[changedReference]:changedStyle}}),changes=diffWorkbooks(before,changed);assert.equal(changes.filter(c=>c.kind==='style').length,1);assert.equal(changes.find(c=>c.kind==='style')?.before?.style_ref,reference);assert.equal(changes.find(c=>c.kind==='style')?.after?.style_ref,changedReference);
  const wrong=revision('after',cells,{style_definitions:{[reference]:changedStyle}});assert.throws(()=>diffWorkbooks(before,wrong),{code:'WORKBOOK_STYLE_SCOPE'});
  const inline=revision('before',Array.from({length:8},(_,i)=>cell(i+1,2,'inline-'+i,{style}))),inlineAfter=revision('after',inline.sheets[0].cells.map(c=>({...c})));inlineAfter.sheets[0].name='Inline renamed';assert.equal(diffWorkbooks(inline,inlineAfter).filter(c=>c.kind==='sheet_name').length,1);
});

test('net cache sizing stops after its byte budget without concatenating a huge projection and converts individual serialization exhaustion to a domain limit',()=>{
  const value='x'.repeat(1024*1024-1),before:WorkbookCellData[]=[],after:WorkbookCellData[]=[];
  for(let row=1;row<=8;row++){before.push(cell(row,1,'key-'+row),cell(row,2,value+'a'));after.push(cell(row,1,'key-'+row),cell(row,2,value+'b'));}
  const changes=diffWorkbooks(revision('before',before),revision('after',after));assert.equal(changes.length,8);let visited=false;
  const beyondBudget={...changes[0],toJSON(){visited=true;throw new Error('Sizing must stop once retention is impossible');}};
  assert.equal(boundedWorkbookNetCacheBytes([...changes,beyondBudget]),null);assert.equal(visited,false);
  const small=diffWorkbooks(revision('before',[cell(1,1,'k'),cell(1,2,'한😀')]),revision('after',[cell(1,1,'k'),cell(1,2,'quote"\\\n')]));assert.equal(boundedWorkbookNetCacheBytes(small),Buffer.byteLength(JSON.stringify(small)));
  const exhausted={...small[0],toJSON(){throw new RangeError('Controlled individual serialization exhaustion');}};assert.throws(()=>boundedWorkbookNetCacheBytes([exhausted]),{code:'WORKBOOK_DIFF_LIMIT'});
});

test('shared formula expansion and array-result followers never assert formula deletion or direct-input semantics when interpretation is unresolved',()=>{
  const shared=revision('before',[cell(1,1,'key'),cell(1,2,'2',{value_type:'number',formula:'',formula_dialect:'xlsx_a1',cached_result:'present',cache_freshness:'unknown',formula_interpretation:'unresolved'})]);
  const ordinary=revision('after',[cell(1,1,'key'),cell(1,2,'2',{value_type:'number',formula:'A1*2',formula_dialect:'xlsx_a1',cached_result:'present',cache_freshness:'unknown',formula_interpretation:'explicit'})]);
  const changes=diffWorkbooks(shared,ordinary);assert.ok(changes.some(c=>c.kind==='cell_observation'&&c.association==='needs_review'&&c.alignment_method==='unresolved_formula_interpretation'));assert.ok(!changes.some(c=>['formula','stored_value','value_type','cache_availability'].includes(c.kind)));
  const array=revision('before',[cell(1,1,'key'),cell(1,2,'10',{value_type:'number',formula:null,cached_result:'present',cache_freshness:'unknown',formula_interpretation:'unresolved'})]),constant=revision('after',[cell(1,1,'key'),cell(1,2,'11',{value_type:'number',formula_interpretation:'not_formula'})]);
  const observed=diffWorkbooks(array,constant);assert.ok(observed.some(c=>c.kind==='cell_observation'&&c.description.includes('not an asserted formula removal, direct-input edit')));assert.ok(!observed.some(c=>['formula','stored_value','value_type','cache_availability'].includes(c.kind)));assert.equal(observed.find(c=>c.before_address==='B1')?.before?.formula_interpretation,'unresolved');
});

test('dense multi-property changes fail at the declared observation budget with a domain error, rather than native argument-spread/heap growth',()=>{
  const before:WorkbookCellData[]=[],after:WorkbookCellData[]=[];
  for(let row=1;row<=16_667;row++){before.push(cell(row,1,'1',{value_type:'number',formula:'1',formula_dialect:'xlsx_a1',cached_result:'present',cache_freshness:'unknown',number_format:'0',style:{bold:'false'}}));after.push(cell(row,1,'2',{value_type:'string',formula:'2',formula_dialect:'xlsx_a1',cached_result:'present',cache_freshness:'unknown',number_format:'@',style:{bold:'true'},hidden_row:true}));}
  assert.throws(()=>diffWorkbooks(revision('before',before),revision('after',after)),{code:'WORKBOOK_DIFF_LIMIT'});
});

test('workbook staging is server-backed, immutable and separate from document tables; endpoint net differs from intermediate history and A→B→A has distinct occurrences',async()=>{
  const f=await fixture();try{
    assert.match(f.draft.project_id,/^wprj_/);assert.equal(f.report.comparison_coverage,'supported_cells_only');assert.equal(f.store.projects().length,0);assert.equal(f.report.revisions.length,3);assert.notEqual(f.report.revisions[0].revision_occurrence_id,f.report.revisions[2].revision_occurrence_id);
    const scope={project_id:f.draft.project_id,report_id:f.report.report_id,from_revision_occurrence_id:f.report.revisions[0].revision_occurrence_id,to_revision_occurrence_id:f.report.revisions[2].revision_occurrence_id,max_output_tokens:8000};
    const history=await f.q.query('list_workbook_changes',{...scope,mode:'history'});assert.ok(history.total>=2);const net=await f.q.query('list_workbook_changes',{...scope,mode:'range_net'});assert.equal(net.total,0);
    const first=f.report.changes[0];await assert.rejects(f.q.query('get_workbook_change',{...scope,change_id:first.change_id,mode:'history',from_revision_occurrence_id:f.report.revisions[1].revision_occurrence_id,to_revision_occurrence_id:f.report.revisions[2].revision_occurrence_id}),{code:'WORKBOOK_CHANGE_SCOPE'});await assert.rejects(f.q.query('get_workbook_change',{project_id:f.draft.project_id,report_id:f.report.report_id,change_id:first.change_id,from_revision_occurrence_id:f.report.revisions[0].revision_occurrence_id}),{code:'WORKBOOK_RANGE_REQUIRED'});
    const r=f.report.revisions[0],lineage=await f.q.query('get_workbook_cell_history',{project_id:f.draft.project_id,report_id:f.report.report_id,revision_occurrence_id:r.revision_occurrence_id,sheet_id:r.sheets[0].sheet_id,row:2,column:2,max_output_tokens:8000});assert.deepEqual(lineage.items.map((i:any)=>i.cell?.value),['100','120','100']);
    await assert.rejects(f.service.commit(f.draft.project_id,f.stage),{code:'STALE_RUN'});
    const staged=await f.service.run(f.draft.project_id);assert.equal(f.service.reports(f.draft.project_id).length,1);const reopened=new Store(f.store.root);try{const other=new WorkbookService(reopened);const committed=await other.commit(f.draft.project_id,staged);assert.equal(committed.report_id,f.report.report_id);}finally{reopened.close();}
    assert.equal(f.service.reports(f.draft.project_id).length,1);assert.equal(f.store.db.prepare('SELECT count(*) AS n FROM reports').get()?.n,0);
  }finally{await f.close();}
});

test('scopes, cursor tampering, fixed latest binding and sparse grid reads cannot cross workbook project/occurrence/sheet boundaries',async()=>{
  const f=await fixture();try{
    const r=f.report.revisions[0],base={project_id:f.draft.project_id,report_id:f.report.report_id,revision_occurrence_id:r.revision_occurrence_id,sheet_id:r.sheets[0].sheet_id,row_start:1,row_limit:100,column_start:1,column_limit:12,limit:1,max_output_tokens:8000};
    const first=await f.q.query('get_workbook_range',base);assert.equal(first.items.length,1);assert.ok(first.next_cursor);
    const next=await f.q.query('get_workbook_range',{...base,cursor:first.next_cursor});assert.notEqual(next.items[0].address,first.items[0].address);
    await assert.rejects(f.q.query('get_workbook_range',{...base,row_start:2,cursor:first.next_cursor}),{code:'WORKBOOK_CURSOR_SCOPE'});
    const tampered=JSON.parse(Buffer.from(first.next_cursor,'base64url').toString());tampered.index=999;await assert.rejects(f.q.query('get_workbook_range',{...base,cursor:Buffer.from(JSON.stringify(tampered)).toString('base64url')}),{code:'WORKBOOK_CURSOR_SCOPE'});
    await assert.rejects(f.q.query('get_workbook_cell',{...base,row:1,column:1,sheet_id:f.report.revisions[1].sheets[0].sheet_id}),{code:'WORKBOOK_SHEET_SCOPE'});
    await assert.rejects(new WorkbookQueryService(f.service,new Set()).query('get_workbook_report',{project_id:f.draft.project_id,report_id:f.report.report_id}),{code:'PROJECT_SCOPE'});
    // Grid hot path does not deserialize the immutable full report.
    const original=f.service.report;f.service.report=()=>{throw Error('full report should not be parsed');};try{const range=await f.q.query('get_workbook_range',base);assert.equal(range.items.length,1);}finally{f.service.report=original;}
    const grid:any=await handleWorkbookAction(f.store,'workbookGrid',base);assert.equal(grid.preview_only,true);assert.equal(grid.items.length,4);assert.ok(Buffer.byteLength(JSON.stringify(grid))<=1024*1024);
    const missing=await f.q.query('get_workbook_cell',{...base,row:50,column:12});assert.equal(missing.availability,'not_materialized');assert.deepEqual(missing.items,[]);
  }finally{await f.close();}
});

test('MCP wire budgets and continuations recover full Unicode/formula-looking source text with no regex execution or cursor loop',async()=>{
  const raw='한😀e\u0301 "\\\n'.repeat(1000),csv='id,body\na,"'+raw.replace(/"/g,'""')+'"\n',f=await fixture([csv]);try{
    const r=f.report.revisions[0],args={project_id:f.draft.project_id,report_id:f.report.report_id,revision_occurrence_id:r.revision_occurrence_id,sheet_id:r.sheets[0].sheet_id,row:2,column:2,text_length:4096,max_output_tokens:8000};let offset=0,result='',calls=0;
    do{const response=await f.q.query('get_workbook_cell',{...args,text_offset:offset},wireBytes);assert.ok(wireBytes(response)<=8000);const c=response.items[0];result+=c.value;const next=c.text_continuations.value.next_offset;if(next===null)break;assert.ok(next>offset);offset=next;assert.ok(++calls<2000);}while(true);assert.equal(result,raw);
    await assert.rejects(f.q.query('get_workbook_cell',{...args,max_output_tokens:256},wireBytes),{code:'OUTPUT_BUDGET_TOO_SMALL'});
    const searched=await f.q.query('search_workbook_cells',{...args,query:'😀e\u0301',max_output_tokens:8000},wireBytes);assert.equal(searched.total,1);assert.ok(wireBytes(searched)<=8000);
    const none=await f.q.query('search_workbook_cells',{...args,query:'.*'});assert.equal(none.total,0);
  }finally{await f.close();}
});

test('range and literal search can continue long text on a nonzero item cursor while logical selectors remain bound',async()=>{
  const raw='match 한😀 "\\\n'.repeat(150),quote=(value:string)=>'"'+value.replaceAll('"','""')+'"',f=await fixture(['id,body\none,'+quote(raw+'first')+'\ntwo,'+quote(raw+'second')+'\n']);try{
    const r=f.report.revisions[0],base={project_id:f.draft.project_id,report_id:f.report.report_id,revision_occurrence_id:r.revision_occurrence_id,sheet_id:r.sheets[0].sheet_id,limit:1,max_output_tokens:4000};
    for(const [name,selectors]of [['get_workbook_range',{row_start:2,row_limit:2,column_start:2,column_limit:1}],['search_workbook_cells',{query:'match'}]]as const){
      const first=await f.q.query(name,{...base,...selectors,text_length:5},wireBytes);assert.ok(first.next_cursor);const incoming=first.next_cursor;let offset=0,reconstructed='',calls=0;
      while(true){const response=await f.q.query(name,{...base,...selectors,cursor:incoming,text_offset:offset,text_length:offset===0?7:31},wireBytes);assert.ok(wireBytes(response)<=4000);assert.equal(response.items.length,1);const item=response.items[0];assert.equal(item.address,'B3');reconstructed+=item.value;const next=item.text_continuations.value.next_offset;if(next===null)break;assert.ok(next>offset);offset=next;assert.ok(++calls<2000);}
      assert.equal(reconstructed,raw+'second');
      await assert.rejects(f.q.query(name,{...base,...selectors,cursor:incoming,...(name==='get_workbook_range'?{row_start:3}:{query:'different'})}),{code:'WORKBOOK_CURSOR_SCOPE'});
    }
  }finally{await f.close();}
});

test('literal search projects only the selected page of 40000 raw matches and preserves nonzero Unicode continuations',async()=>{
  const raw='match 한😀 "\\\n'+'x'.repeat(48),quote=(value:string)=>'"'+value.replaceAll('"','""')+'"',values=Array.from({length:40_000},(_,i)=>raw+i),f=await fixture([values.map(quote).join('\n')+'\n']);try{
    const r=f.report.revisions[0],args={project_id:f.draft.project_id,report_id:f.report.report_id,revision_occurrence_id:r.revision_occurrence_id,sheet_id:r.sheets[0].sheet_id,query:'match',limit:1,max_output_tokens:4000},indexed=f.service.indexedCells,reader=f.q as any,resolveStyle=reader.cellStyle;let projections=0,scans=0;
    f.service.indexedCells=(...params:Parameters<WorkbookService['indexedCells']>)=>{assert.equal(params[9],false,'search must retain interned style references during its index scan');scans++;return indexed.apply(f.service,params);};
    reader.cellStyle=function(...params:any[]){projections++;return resolveStyle.apply(this,params);};
    try{
      const first=await f.q.query('search_workbook_cells',{...args,text_length:7},wireBytes);assert.equal(first.total,40_000);assert.equal(first.items[0].address,'A1');assert.equal(projections,1);assert.ok(first.next_cursor);assert.ok(wireBytes(first)<=4000);
      const incoming=first.next_cursor;let offset=0,reconstructed='',calls=0;
      while(true){projections=0;const response=await f.q.query('search_workbook_cells',{...args,cursor:incoming,text_offset:offset,text_length:offset===0?9:31},wireBytes);assert.equal(response.total,40_000);assert.equal(response.items.length,1);assert.equal(response.items[0].address,'A2');assert.equal(projections,1,'bounded cell/style projection must be proportional to the selected page');assert.ok(wireBytes(response)<=4000);const item=response.items[0];reconstructed+=item.value;const next=item.text_continuations.value.next_offset;if(next===null)break;assert.ok(next>offset);offset=next;assert.ok(++calls<10);}
      assert.equal(reconstructed,values[1]);assert.ok(scans>=3);
      await assert.rejects(f.q.query('search_workbook_cells',{...args,cursor:incoming,query:'other'}),{code:'WORKBOOK_CURSOR_SCOPE'});
    }finally{f.service.indexedCells=indexed;reader.cellStyle=resolveStyle;}
  }finally{await f.close();}
});

test('fresh native-style readers use immutable indexes for adjacent and nonadjacent net comparisons and physical-key cell history',async()=>{
  const f=await fixture(['id,value\na,1\nb,2\n','id,value\nb,3\na,4\n','id,value\na,5\nb,6\n']);try{
    const scope={project_id:f.draft.project_id,report_id:f.report.report_id},expectedAdjacent=diffWorkbooks(f.report.revisions[0],f.report.revisions[1]).map(c=>c.change_id),expectedNet=diffWorkbooks(f.report.revisions[0],f.report.revisions[2]).map(c=>c.change_id),reader=f.service.report;f.service.report=()=>{throw Error('an indexed workbook read must not deserialize or hash the full report');};
    try{
      for(const [end,expected]of [[1,expectedAdjacent],[2,expectedNet]]as const){const q=new WorkbookQueryService(f.service,new Set([f.draft.project_id])),response=await q.query('list_workbook_changes',{...scope,from_revision_occurrence_id:f.report.revisions[0].revision_occurrence_id,to_revision_occurrence_id:f.report.revisions[end].revision_occurrence_id,mode:'range_net',max_output_tokens:8000},wireBytes);const actual:string[]=response.items.map((c:any)=>c.change_id);let cursor=response.next_cursor;while(cursor){const page=await q.query('list_workbook_changes',{...scope,from_revision_occurrence_id:f.report.revisions[0].revision_occurrence_id,to_revision_occurrence_id:f.report.revisions[end].revision_occurrence_id,mode:'range_net',cursor,max_output_tokens:8000},wireBytes);actual.push(...page.items.map((c:any)=>c.change_id));cursor=page.next_cursor;}assert.deepEqual(actual,expected);}
      const q=new WorkbookQueryService(f.service,new Set([f.draft.project_id])),r=f.report.revisions[0],response=await q.query('get_workbook_cell_history',{...scope,revision_occurrence_id:r.revision_occurrence_id,sheet_id:r.sheets[0].sheet_id,row:2,column:2,limit:1,max_output_tokens:8000},wireBytes);const items=[...response.items];let cursor=response.next_cursor;while(cursor){const page=await new WorkbookQueryService(f.service,new Set([f.draft.project_id])).query('get_workbook_cell_history',{...scope,revision_occurrence_id:r.revision_occurrence_id,sheet_id:r.sheets[0].sheet_id,row:2,column:2,limit:1,cursor,max_output_tokens:8000},wireBytes);items.push(...page.items);cursor=page.next_cursor;}assert.deepEqual(items.map(c=>c.cell?.value),['1','4','5']);assert.deepEqual(items.map(c=>c.cell?.address),['B2','B3','B2']);
    }finally{f.service.report=reader;}
  }finally{await f.close();}
});

test('cell history follows unique physical row keys through a moved middle hole and cleared latest cell while duplicate keys stay unresolved',async()=>{
  const root=await mkdtemp(join(tmpdir(),'docver-workbook-history-holes-')),store=new Store(join(root,'library')),service=new WorkbookService(store);try{
    const key=(row:number,value:string)=>'<c r="A'+row+'" t="inlineStr"><is><t>'+xmlEscape(value)+'</t></is></c>',header='<row r="1">'+key(1,'id')+'<c r="B1" t="inlineStr"><is><t>value</t></is></c></row>',sources=[
      header+'<row r="2">'+key(2,'K')+'<c r="B2"><v>100</v></c></row>',
      header+'<row r="2">'+key(2,'Other')+'<c r="B2"><v>9</v></c></row><row r="3">'+key(3,'K')+'</row>',
      header+'<row r="2">'+key(2,'K')+'</row>',
      header+'<row r="2">'+key(2,'K')+'</row><row r="3">'+key(3,'K')+'</row>',
    ],paths:string[]=[];for(const [i,rows]of sources.entries()){const path=join(root,i+'.xlsx');await writeFile(path,xlsxFixture('<sheetData>'+rows+'</sheetData>'));paths.push(path);}
    const analyze=async(selected:string[])=>{const project=await service.create('History holes',selected.map((path,i)=>({path,label:'v'+i}))),stage=await service.run(project.project_id);await service.commit(project.project_id,stage);return service.report(project.project_id,stage.report_id);};
    const report=await analyze(paths.slice(0,3)),ambiguous=await analyze([paths[0],paths[3],paths[2]]),originalReader=service.report;service.report=()=>{throw Error('hole lineage must use scoped indexes, not full report');};
    try{
      for(const selected of [0,2]){const r=report.revisions[selected],args={project_id:report.project_id,report_id:report.report_id,revision_occurrence_id:r.revision_occurrence_id,sheet_id:r.sheets[0].sheet_id,row:2,column:2,limit:1,max_output_tokens:8000},items:any[]=[];let cursor:string|undefined;do{const response=await new WorkbookQueryService(service,new Set([report.project_id])).query('get_workbook_cell_history',{...args,...(cursor?{cursor}:{})},wireBytes);assert.ok(wireBytes(response)<=8000);items.push(...response.items);cursor=response.next_cursor??undefined;}while(cursor);assert.deepEqual(items.map(c=>c.availability),['available','not_materialized','not_materialized']);assert.deepEqual(items.map(c=>c.address),['B2','B3','B2']);assert.deepEqual(items.map(c=>c.cell?.value??null),['100',null,null]);assert.ok(items.filter(c=>!c.cell).every(c=>c.column===2&&c.row>0));}
      const r=ambiguous.revisions[2],negative=await new WorkbookQueryService(service,new Set([ambiguous.project_id])).query('get_workbook_cell_history',{project_id:ambiguous.project_id,report_id:ambiguous.report_id,revision_occurrence_id:r.revision_occurrence_id,sheet_id:r.sheets[0].sheet_id,row:2,column:2,max_output_tokens:8000},wireBytes);assert.deepEqual(negative.items.map((c:any)=>c.availability),['correspondence_unresolved','correspondence_unresolved','not_materialized']);assert.ok(negative.items.slice(0,2).every((c:any)=>c.association==='needs_review'&&c.address===null));
    }finally{service.report=originalReader;}
  }finally{store.close();await rm(root,{recursive:true,force:true});}
});

test('ordinary change summaries and individual endpoint components fit conservative 4000-byte MCP responses without duplicated cells',async()=>{
  const f=await fixture();try{
    const scope={project_id:f.draft.project_id,report_id:f.report.report_id},interval={...scope,from_revision_occurrence_id:f.report.revisions[0].revision_occurrence_id,to_revision_occurrence_id:f.report.revisions[2].revision_occurrence_id,max_output_tokens:4000};
    const listed=await f.q.query('list_workbook_changes',interval,wireBytes);assert.ok(listed.items.length);assert.ok(wireBytes(listed)<=4000);assert.ok(!('before'in listed.items[0]));assert.ok(!('after'in listed.items[0]));
    const selected={...scope,change_id:listed.items[0].change_id,max_output_tokens:4000};const summary=await f.q.query('get_workbook_change',selected,wireBytes);assert.ok(wireBytes(summary)<=4000);assert.ok(!('change'in summary));assert.equal(summary.items[0].component,'summary');
    for(const component of ['before','after'] as const){const detail=await f.q.query('get_workbook_change',{...selected,component},wireBytes);assert.ok(wireBytes(detail)<=4000);assert.equal(detail.items[0].component,component);assert.equal(detail.items[0][component].address,'B2');assert.ok(!((component==='before'?'after':'before')in detail.items[0]));}
  }finally{await f.close();}
});

test('long Unicode package references and endpoint text remain fully readable under 8000-byte MCP wire limits',async()=>{
  const root=await mkdtemp(join(tmpdir(),'docver-workbook-long-reference-')),store=new Store(join(root,'library')),service=new WorkbookService(store),path='xl/'+'한'.repeat(473)+'.xml',formula='한😀 "quoted"\\\n'.repeat(400);try{
    const inputs=[];for(const [i,text]of [formula,formula+'+1',formula+'+2'].entries()){const sheetXml='<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData><row r="1"><c r="A1" t="inlineStr"><is><t>key</t></is></c><c r="B1" s="1"><f>'+xmlEscape(text)+'</f><v>1</v></c></row></sheetData></worksheet>',source=join(root,i+'.xlsx');await writeFile(source,xlsxFixture(sheetXml,{styles:workbookStyles,relationships:'<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="sheet1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="'+path.slice(3)+'"/><Relationship Id="styles" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>',extra:{[path]:sheetXml}}));inputs.push({path:source,label:'v'+i});}
    const draft=await service.create('long reference',inputs),stage=await service.run(draft.project_id);await service.commit(draft.project_id,stage);const report=service.report(draft.project_id,stage.report_id),q=new WorkbookQueryService(service,new Set([draft.project_id])),change=report.changes.find(c=>c.kind==='formula')!;assert.ok(change);
    for(const component of ['before','after']as const){let result='',offset=0,calls=0;while(true){const response=await q.query('get_workbook_change',{project_id:draft.project_id,report_id:report.report_id,change_id:change.change_id,component,text_offset:offset,text_length:4096,max_output_tokens:8000},wireBytes);assert.ok(wireBytes(response)<=8000);const c=response.items[0][component];assert.ok(c.source_ref.startsWith(path));assert.ok(Object.keys(c.style).length>0||c.style_truncated);result+=c.formula;const next=c.text_continuations.formula.next_offset;if(next===null)break;assert.ok(next>offset);offset=next;assert.ok(++calls<2000);}assert.equal(result,component==='before'?formula:formula+'+1');}
    const r=report.revisions[0],raw=await q.query('get_workbook_cell',{project_id:draft.project_id,report_id:report.report_id,revision_occurrence_id:r.revision_occurrence_id,sheet_id:r.sheets[0].sheet_id,row:1,column:2,max_output_tokens:8000},wireBytes);assert.ok(wireBytes(raw)<=8000);assert.ok(!('cell'in raw));assert.ok(raw.items[0].source_ref.startsWith(path));
    const originalReader=service.report;service.report=()=>{throw Error('styled indexed endpoint reads must not parse full report');};try{for(const end of [1,2]){const expected=diffWorkbooks(report.revisions[0],report.revisions[end]).map(c=>c.change_id),indexed=await new WorkbookQueryService(service,new Set([draft.project_id])).query('list_workbook_changes',{project_id:draft.project_id,report_id:report.report_id,from_revision_occurrence_id:r.revision_occurrence_id,to_revision_occurrence_id:report.revisions[end].revision_occurrence_id,mode:'range_net',max_output_tokens:8000},wireBytes);assert.deepEqual(indexed.items.map((c:any)=>c.change_id),expected);}}finally{service.report=originalReader;}
  }finally{store.close();await rm(root,{recursive:true,force:true});}
});

test('dense 1200-cell Unicode grid previews stay compact despite semantic styles while raw reads preserve interned style definitions',async()=>{
  const root=await mkdtemp(join(tmpdir(),'docver-workbook-grid-')),store=new Store(join(root,'library')),service=new WorkbookService(store),source=join(root,'dense.xlsx'),raw='한😀 "\\\n'.repeat(100);try{
    let rows='';for(let row=1;row<=100;row++){rows+='<row r="'+row+'">';for(let col=1;col<=12;col++)rows+='<c r="'+cellAddress(row,col)+'" t="str" s="1"><f>'+xmlEscape(raw)+'</f><v>'+xmlEscape(raw)+'</v></c>';rows+='</row>';}
    await writeFile(source,xlsxFixture('<sheetData>'+rows+'</sheetData>',{styles:workbookStyles}));const draft=await service.create('dense',[{path:source,label:'one'}]),stage=await service.run(draft.project_id);await service.commit(draft.project_id,stage);const report=service.report(draft.project_id,stage.report_id),r=report.revisions[0],s=r.sheets[0];assert.ok(r.style_definitions&&Object.keys(r.style_definitions).length>0);assert.ok(s.cells[0].style_ref);assert.deepEqual(s.cells[0].style,{});
    const grid:any=await handleWorkbookAction(store,'workbookGrid',{project_id:draft.project_id,report_id:report.report_id,revision_occurrence_id:r.revision_occurrence_id,sheet_id:s.sheet_id,row_start:1,row_limit:100,column_start:1,column_limit:12});assert.equal(grid.items.length,1200);assert.ok(Buffer.byteLength(JSON.stringify(grid))<1024*1024);assert.ok(grid.items.every((c:any)=>c.text_truncated&&c.source_lengths.value===raw.length&&c.cached_result==='present'&&!('style'in c)&&!('text_continuations'in c)&&!('source_ref'in c)));
    const q=new WorkbookQueryService(service,new Set([draft.project_id])),cell=await q.query('get_workbook_cell',{project_id:draft.project_id,report_id:report.report_id,revision_occurrence_id:r.revision_occurrence_id,sheet_id:s.sheet_id,row:1,column:1,max_output_tokens:8000},wireBytes);assert.ok(Object.keys(cell.items[0].style).length>0||cell.items[0].style_truncated);assert.ok(!('style_definitions'in service.view(draft.project_id,report.report_id).revisions[0]));assert.ok(!('style_definitions'in (await q.query('list_workbook_revisions',{project_id:draft.project_id,report_id:report.report_id})).items[0]));
    const searched=await q.query('search_workbook_cells',{project_id:draft.project_id,report_id:report.report_id,revision_occurrence_id:r.revision_occurrence_id,sheet_id:s.sheet_id,query:'한😀',limit:1,max_output_tokens:8000},wireBytes);assert.equal(searched.total,1200);assert.deepEqual(searched.items[0].style,cell.items[0].style);assert.equal(searched.items[0].style_ref,s.cells[0].style_ref);assert.ok(wireBytes(searched)<=8000);
    const bad=structuredClone(report),key='wstyle_'+'f'.repeat(64);bad.revisions[0].style_definitions={[key]:{bad:'definition'}};bad.report_id=workbookID('wreport',Object.fromEntries(Object.entries(bad).filter(([field])=>field!=='report_id')));assert.throws(()=>validateIdentity(bad),{code:'WORKBOOK_STYLE_SCOPE'});
    const exported=await service.export(draft.project_id,report.report_id,join(root,'export')),records=(await readFile(exported.files.find(p=>p.endsWith('.jsonl'))!,'utf8')).trim().split('\n').map(line=>JSON.parse(line));assert.equal(records[0].record_type,'workbook_manifest');assert.equal(records[0].report_id,report.report_id);assert.deepEqual(records[0].revisions[0].style_definitions[s.cells[0].style_ref!],r.style_definitions![s.cells[0].style_ref!]);
  }finally{store.close();await rm(root,{recursive:true,force:true});}
});

test('cumulative revision text rejects an oversized report before parsing later originals and leaves only a failed run',async()=>{
  const root=await mkdtemp(join(tmpdir(),'docver-workbook-report-budget-')),store=new Store(join(root,'library')),service=new WorkbookService(store),source=join(root,'large-text.xlsx'),sentinel=join(root,'unreached.xlsx');try{
    // One legal 1 MiB UTF-16 cell has 3 MiB of UTF-8 source text, compressed
    // to a small original. Repeated occurrences must still consume report bytes.
    const text='한'.repeat(1024*1024),bytes=xlsxFixture('<sheetData><row r="1"><c r="A1" t="inlineStr"><is><t>'+text+'</t></is></c></row></sheetData>');assert.ok(bytes.length<64*1024);assert.ok(Buffer.byteLength(text)*99>MAX_WORKBOOK_REPORT_BYTES);await writeFile(source,bytes);
    // This SHA-correct malformed original would fail parsing if analysis kept
    // retaining revisions after the earlier cumulative budget was exhausted.
    await writeFile(sentinel,'This original must not be parsed after the report budget is exhausted.');
    const draft=await service.create('Cumulative report budget',Array.from({length:100},(_,index)=>({path:index===99?sentinel:source,label:'v'+(index+1)})));assert.equal(draft.revisions[0].asset_id,'sha256:'+byteHash(bytes));
    await assert.rejects(service.run(draft.project_id),{code:'WORKBOOK_REPORT_LIMIT'});assert.deepEqual(service.reports(draft.project_id),[]);
    const run=store.db.prepare('SELECT id,status,error,report_id,staged_sha,finished_at FROM workbook_runs_v1 WHERE project_id=?').get(draft.project_id)!;assert.equal(run.status,'failed');assert.equal(run.error,'WORKBOOK_REPORT_LIMIT');assert.equal(run.report_id,null);assert.equal(run.staged_sha,null);assert.ok(run.finished_at);assert.equal(service.runStatus(draft.project_id,String(run.id)).status,'failed');
    const stages=await readdir(join(store.root,'workbook-staging-v1')).catch((error:NodeJS.ErrnoException)=>{if(error.code==='ENOENT')return [];throw error;});assert.deepEqual(stages,[]);assert.equal(store.db.prepare('SELECT count(*) AS n FROM workbook_reports_v1').get()!.n,0);assert.equal(store.db.prepare('SELECT count(*) AS n FROM workbook_cells_v1').get()!.n,0);
  }finally{store.close();await rm(root,{recursive:true,force:true});}
});

test('reused number formats reject oversized reports before full-revision allocation, including the 500k-cell cap',async()=>{
  const {spawnSync}=await import('node:child_process'),root=await mkdtemp(join(tmpdir(),'docver-workbook-format-budget-'));
  const child=`
    import assert from 'node:assert/strict';
    import {readdir} from 'node:fs/promises';
    import {join} from 'node:path';
    import {Store} from './packages/storage/index.ts';
    import {WorkbookService} from './packages/workbook/service.ts';
    const store=new Store(process.argv[2]),service=new WorkbookService(store);
    try{
      const draft=await service.create('Format amplification',[{label:'source',path:process.argv[1]}]);
      await assert.rejects(service.run(draft.project_id),{code:'WORKBOOK_REPORT_LIMIT'});
      assert.deepEqual({...store.db.prepare('SELECT status,error FROM workbook_runs_v1 WHERE project_id=?').get(draft.project_id)},{status:'failed',error:'WORKBOOK_REPORT_LIMIT'});
      for(const table of ['workbook_reports_v1','workbook_cells_v1','workbook_changes_v1'])assert.equal(store.db.prepare('SELECT count(*) AS n FROM '+table).get().n,0);
      assert.deepEqual(await readdir(join(store.root,'workbook-staging-v1')).catch(error=>{if(error.code==='ENOENT')return[];throw error;}),[]);
    }finally{store.close();}
  `;
  try{
    const xlsx=xlsxFixture('<sheetData>'+Array.from({length:600},(_,i)=>`<row r="${i+1}"><c r="A${i+1}" s="1"><v>1</v></c></row>`).join('')+'</sheetData>',{styles:workbookStyles.replace('formatCode="0.000"','formatCode="'+'0'.repeat(1_000_000)+'"')});
    const ods=odsFixture('<table:table-row table:number-rows-repeated="20000"><table:table-cell table:style-name="cell" office:value-type="float" office:value="1"/></table:table-row>',{automatic:'<number:number-style style:name="big"><number:text>'+'0'.repeat(16_000)+'</number:text></number:number-style><style:style style:name="cell" style:family="table-cell" style:data-style-name="big"/>'});
    const columns=Array.from({length:50},(_,n)=>n<26?String.fromCharCode(65+n):'A'+String.fromCharCode(65+n-26));
    const rows=Array.from({length:10_000},(_,i)=>`<row r="${i+1}">`+columns.map(c=>`<c r="${c}${i+1}" s="1"><v>1</v></c>`).join('')+'</row>');
    const maximal=xlsxFixture('<sheetData>'+rows.join('')+'</sheetData>',{styles:workbookStyles.replace('formatCode="0.000"','formatCode="'+'0'.repeat(1_000_000)+'"')});
    for(const [name,format,bytes,heap]of [['xlsx-small','xlsx',xlsx,256],['ods','ods',ods,256],['xlsx-max','xlsx',maximal,2048]]as const){
      const path=join(root,name+'.'+format);await writeFile(path,bytes);
      const result=spawnSync(process.execPath,['--max-old-space-size='+heap,'--import','tsx','--input-type=module','--eval',child,path,join(root,name+'-library')],{cwd:process.cwd(),encoding:'utf8',timeout:20_000});
      assert.ifError(result.error);assert.equal(result.status,0,name+': '+result.stderr);assert.equal(result.signal,null);
    }
  }finally{await rm(root,{recursive:true,force:true});}
});

test('cancelled, interrupted, stale-input, tampered-stage and corrupt-original analyses never commit partial reports; corrupted drafts retain fixed read access',async()=>{
  const root=await mkdtemp(join(tmpdir(),'docver-workbook-fault-')),path=join(root,'a.csv');await writeFile(path,'id,value\na,1\n');const store=new Store(join(root,'library')),service=new WorkbookService(store);try{
    const draft=await service.create('fault',[{path,label:'one'}]),controller=new AbortController();controller.abort();await assert.rejects(service.run(draft.project_id,controller.signal));assert.equal(service.reports(draft.project_id).length,0);
    const stage=await service.run(draft.project_id),stagedPath=join(store.root,'workbook-staging-v1',stage.staged_name),original=await readFile(stagedPath);await writeFile(stagedPath,Buffer.concat([original,Buffer.from(' ')]));await assert.rejects(service.commit(draft.project_id,{...stage,sha256:byteHash(await readFile(stagedPath))}),{code:'STALE_RUN'});assert.equal(service.reports(draft.project_id).length,0);
    await service.recover(draft.project_id);await assert.rejects(service.commit(draft.project_id,stage),{code:'STALE_RUN'});assert.deepEqual(await readdir(join(store.root,'workbook-staging-v1')),[]);
    const valid=await service.run(draft.project_id);await service.commit(draft.project_id,valid);const originalReport=canonical(service.report(draft.project_id,valid.report_id));
    const pending=await service.run(draft.project_id);store.db.prepare('UPDATE workbook_projects_v1 SET body=? WHERE id=?').run(JSON.stringify({...service.project(draft.project_id),title:'changed'}),draft.project_id);await assert.rejects(service.commit(draft.project_id,pending),{code:'STALE_RUN'});
    await writeFile(join(store.root,'assets',draft.revisions[0].asset_id.slice(7)),'corrupt');await assert.rejects(service.run(draft.project_id),{code:'ASSET_CORRUPT'});assert.equal(canonical(service.report(draft.project_id,valid.report_id)),originalReport);
    store.db.prepare('UPDATE workbook_projects_v1 SET body=? WHERE id=?').run('{broken',draft.project_id);assert.throws(()=>service.project(draft.project_id),{code:'WORKBOOK_DRAFT_UNREADABLE'});assert.equal(service.projects()[0].unreadable,true);assert.equal(canonical(service.report(draft.project_id,valid.report_id)),originalReport);
    const q=new WorkbookQueryService(service,new Set([draft.project_id]));assert.equal((await q.query('list_workbook_revisions',{project_id:draft.project_id,report_id:valid.report_id})).total,1);
  }finally{store.close();await rm(root,{recursive:true,force:true});}
});

test('discard invalidates only the exact owned active run, cleans superseded stages and preserves peer projects and fixed reports across restart recovery',async()=>{
  const f=await fixture();try{
    const original=canonical(f.service.report(f.draft.project_id,f.report.report_id)),peer=await f.service.create('peer',[{path:f.paths[0],label:'peer'}]),peerStage=await f.service.run(peer.project_id),cancelled=await f.service.run(f.draft.project_id),folder=join(f.store.root,'workbook-staging-v1');
    await assert.rejects(f.service.discard(f.draft.project_id,peerStage.analysis_run_id),{code:'WORKBOOK_RUN_SCOPE'});await assert.rejects(f.service.discard(f.draft.project_id,f.stage.analysis_run_id),{code:'STALE_RUN'});
    const result:any=await handleWorkbookAction(f.store,'workbookDiscard',{project_id:f.draft.project_id,analysis_run_id:cancelled.analysis_run_id});assert.equal(result.discarded,true);await assert.rejects(readFile(join(folder,cancelled.staged_name)),{code:'ENOENT'});await assert.rejects(f.service.commit(f.draft.project_id,cancelled),{code:'STALE_RUN'});
    const first=await f.service.run(f.draft.project_id),next=await f.service.run(f.draft.project_id);await assert.rejects(readFile(join(folder,first.staged_name)),{code:'ENOENT'});await assert.rejects(f.service.commit(f.draft.project_id,first),{code:'STALE_RUN'});
    await f.service.commit(peer.project_id,peerStage);assert.equal(f.service.reports(peer.project_id).length,1);const reopened=new Store(f.store.root);try{const afterRestart=new WorkbookService(reopened);await afterRestart.recover(f.draft.project_id);await assert.rejects(afterRestart.commit(f.draft.project_id,next),{code:'STALE_RUN'});assert.equal(afterRestart.reports(peer.project_id).length,1);assert.equal(canonical(afterRestart.report(f.draft.project_id,f.report.report_id)),original);}finally{reopened.close();}
    assert.deepEqual(await readdir(folder),[]);
  }finally{await f.close();}
});

test('a durable commit remains successful when private stage cleanup fails, and exact-run status recovers a lost reply without crossing projects',async()=>{
  const f=await fixture();try{
    const fixed=canonical(f.report),pending=await f.service.run(f.draft.project_id),path=join(f.store.root,'workbook-staging-v1',pending.staged_name),retained=path+'.test-retained';
    assert.equal(f.service.runStatus(f.draft.project_id,pending.analysis_run_id).status,'staged');assert.equal(f.service.runStatus(f.draft.project_id,pending.analysis_run_id).report_id,null);
    // The real transaction's success update replaces only this test-owned stage
    // with an empty directory after its bytes were verified. No production hook.
    f.store.db.function('workbook_core_stage_cleanup_fault',()=>{renameSync(path,retained);mkdirSync(path,{mode:0o700});return 0;});
    f.store.db.exec("CREATE TEMP TRIGGER workbook_core_stage_cleanup_fault AFTER UPDATE OF status ON workbook_runs_v1 WHEN NEW.status='success' AND OLD.status='staged' BEGIN SELECT workbook_core_stage_cleanup_fault(); END");
    let result;try{result=await f.service.commit(f.draft.project_id,pending);}finally{f.store.db.exec('DROP TRIGGER workbook_core_stage_cleanup_fault');}
    assert.equal(result.status,'complete');assert.equal(result.cleanup_pending,true);assert.equal(result.report_id,f.report.report_id);assert.equal((await stat(path)).isDirectory(),true);assert.equal(canonical(f.service.report(f.draft.project_id,f.report.report_id)),fixed);
    const recovered:any=await handleWorkbookAction(f.store,'workbookRunStatus',{project_id:f.draft.project_id,analysis_run_id:pending.analysis_run_id});assert.equal(recovered.status,'success');assert.equal(recovered.report_id,f.report.report_id);await assert.rejects(f.service.discard(f.draft.project_id,pending.analysis_run_id),{code:'STALE_RUN'});
    await rm(path,{recursive:true});renameSync(retained,path);await f.service.recover();await assert.rejects(readFile(path),{code:'ENOENT'});assert.equal(canonical(f.service.report(f.draft.project_id,f.report.report_id)),fixed);
    const peer=await f.service.create('peer scope',[{path:f.paths[0],label:'peer'}]),peerStage=await f.service.run(peer.project_id);await f.service.commit(peer.project_id,peerStage);assert.throws(()=>f.service.runStatus(peer.project_id,pending.analysis_run_id),{code:'WORKBOOK_RUN_SCOPE'});
    const next=await f.service.run(f.draft.project_id);await f.service.commit(f.draft.project_id,next); // caller intentionally retains no commit response
    const reader=new Store(f.store.root,true);try{const status=new WorkbookService(reader).runStatus(f.draft.project_id,next.analysis_run_id);assert.equal(status.status,'success');assert.equal(status.report_id,f.report.report_id);}finally{reader.close();}
    f.store.db.prepare('UPDATE workbook_runs_v1 SET report_id=? WHERE id=?').run(peerStage.report_id,next.analysis_run_id);assert.throws(()=>f.service.runStatus(f.draft.project_id,next.analysis_run_id),{code:'WORKBOOK_RUN_CORRUPT'});f.store.db.prepare('UPDATE workbook_runs_v1 SET report_id=? WHERE id=?').run(f.report.report_id,next.analysis_run_id);
    const discarded=await f.service.run(f.draft.project_id);await f.service.discard(f.draft.project_id,discarded.analysis_run_id);const cancelled=f.service.runStatus(f.draft.project_id,discarded.analysis_run_id);assert.equal(cancelled.status,'failed');assert.equal(cancelled.report_id,null);assert.equal(cancelled.error,'CANCELLED');assert.equal(canonical(f.service.report(f.draft.project_id,f.report.report_id)),fixed);
  }finally{await f.close();}
});

test('interval and exact-change SQL reads avoid unrelated corrupted indexes; endpoint net paging reuses a fixed bounded cache instead of reparsing the full report',async()=>{
  const f=await fixture(['id,value\na,1\nb,2\nc,3\n','id,value\na,4\nb,5\nc,6\n','id,value\na,7\nb,8\nc,9\n']);try{
    const scope={project_id:f.draft.project_id,report_id:f.report.report_id},interval={...scope,from_revision_occurrence_id:f.report.revisions[0].revision_occurrence_id,to_revision_occurrence_id:f.report.revisions[1].revision_occurrence_id,mode:'range_net',limit:1,max_output_tokens:8000};
    const netInterval={...interval,to_revision_occurrence_id:f.report.revisions[2].revision_occurrence_id},first=await f.q.query('list_workbook_changes',netInterval,wireBytes);assert.ok(first.next_cursor);const reportReader=f.service.report;f.service.report=()=>{throw Error('cached net paging must not reparse full report');};try{const next=await f.q.query('list_workbook_changes',{...netInterval,cursor:first.next_cursor},wireBytes);assert.equal(next.items.length,1);assert.notEqual(next.items[0].change_id,first.items[0].change_id);}finally{f.service.report=reportReader;}
    const outside=f.report.changes.find(c=>c.to_revision_occurrence_id===f.report.revisions[2].revision_occurrence_id)!;f.store.db.prepare('UPDATE workbook_changes_v1 SET body=? WHERE report_id=? AND change_id=?').run('{}',f.report.report_id,outside.change_id);
    const history=await f.q.query('list_workbook_changes',{...interval,mode:'history'},wireBytes);assert.equal(history.total,3);const inside=f.report.changes.find(c=>c.to_revision_occurrence_id===f.report.revisions[1].revision_occurrence_id)!;const exact=await f.q.query('get_workbook_change',{...scope,change_id:inside.change_id},wireBytes);assert.equal(exact.items[0].change_id,inside.change_id);
    const body=String(f.store.db.prepare('SELECT body FROM workbook_reports_v1 WHERE id=?').get(f.report.report_id)!.body);f.store.db.prepare('UPDATE workbook_reports_v1 SET body=? WHERE id=?').run('{broken primary body',f.report.report_id);assert.equal(f.service.reports(f.draft.project_id)[0].revision_count,3);f.store.db.prepare('UPDATE workbook_reports_v1 SET body=? WHERE id=?').run(body,f.report.report_id);
  }finally{await f.close();}
});

test('readonly old libraries never migrate workbook tables; local releases are immutable labelled records and safe exports retain full SHA originals',async()=>{
  const empty=await mkdtemp(join(tmpdir(),'docver-workbook-readonly-')),writer=new Store(empty);writer.close();const ro=new Store(empty,true);try{const before=ro.db.prepare("SELECT name FROM sqlite_master ORDER BY name").all();assert.deepEqual(new WorkbookService(ro).projects(),[]);assert.deepEqual(ro.db.prepare("SELECT name FROM sqlite_master ORDER BY name").all(),before);}finally{ro.close();await rm(empty,{recursive:true,force:true});}
  const f=await fixture();try{
    const before=await Promise.all(f.paths.map(async p=>({bytes:await readFile(p),stat:await stat(p)}))),label='[unsafe](https://evil.example) ```\n<script>alert(1)</script>',release=f.service.publish(f.draft.project_id,f.report.report_id,label,'User supplied rationale, not true editing attribution'),next=f.service.publish(f.draft.project_id,f.report.report_id,label,'Second release record');assert.notEqual(release.release_id,next.release_id);assert.equal(release.provenance,'local_user_input_no_editor_authentication');assert.equal(release.schema_version,'workbook.1');
    const output=await f.service.export(f.draft.project_id,f.report.report_id,join(f.root,'export')),md=await readFile(output.files.find(p=>p.endsWith('.md'))!,'utf8'),json=JSON.parse(await readFile(output.files.find(p=>p.endsWith('.json'))!,'utf8'));assert.ok(md.includes('> ````text\n> [unsafe]'));assert.equal(json.releases.length,2);assert.equal(json.report.report_id,f.report.report_id);const records=(await readFile(output.files.find(p=>p.endsWith('.jsonl'))!,'utf8')).trim().split('\n').map(line=>JSON.parse(line));assert.equal(records[0].record_type,'workbook_manifest');assert.equal(records[0].schema_version,'workbook.1');assert.ok(records.slice(1).every(c=>c.record_type==='workbook_change'&&c.report_id===f.report.report_id));
    for(const r of f.report.revisions){assert.ok(md.includes(`(${r.asset_id.slice(7)}.csv)`));assert.equal(byteHash(await readFile(join(f.root,'export',r.asset_id.slice(7)+'.csv'))),r.asset_id.slice(7));}
    for(const [i,p]of f.paths.entries()){assert.deepEqual(await readFile(p),before[i].bytes);assert.equal((await stat(p)).mtimeMs,before[i].stat.mtimeMs);}
    const readOnly=new Store(f.store.root,true);try{const reader=new WorkbookService(readOnly);await assert.rejects(reader.create('no',[{path:f.paths[0],label:'x'}]),{code:'READ_ONLY'});assert.equal(reader.releases(f.draft.project_id).length,2);}finally{readOnly.close();}
  }finally{await f.close();}
});
