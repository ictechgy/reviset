import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, readFile, writeFile, rm, stat, readdir } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { Store } from '../../packages/storage/index.js';
import { byteHash, canonical } from '../../packages/schema/index.js';
import { WorkbookService } from '../../packages/workbook/service.js';
import { WorkbookQueryService } from '../../packages/workbook/query.js';
import { diffWorkbooks, type WorkbookRevisionData } from '../../packages/workbook/diff.js';
import { cellAddress, type WorkbookCellData, type WorkbookSheetData } from '../../packages/workbook/types.js';
import { handleWorkbookAction } from '../../apps/bridge/workbook.js';

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
    const missing=await f.q.query('get_workbook_cell',{...base,row:50,column:12});assert.equal(missing.availability,'not_materialized');assert.equal(missing.cell,null);
  }finally{await f.close();}
});

test('MCP wire budgets and continuations recover full Unicode/formula-looking source text with no regex execution or cursor loop',async()=>{
  const raw='한😀e\u0301 "\\\n'.repeat(1000),csv='id,body\na,"'+raw.replace(/"/g,'""')+'"\n',f=await fixture([csv]);try{
    const r=f.report.revisions[0],args={project_id:f.draft.project_id,report_id:f.report.report_id,revision_occurrence_id:r.revision_occurrence_id,sheet_id:r.sheets[0].sheet_id,row:2,column:2,text_length:4096,max_output_tokens:8000};let offset=0,result='',calls=0;
    do{const response=await f.q.query('get_workbook_cell',{...args,text_offset:offset},wireBytes);assert.ok(wireBytes(response)<=8000);const c=response.cell;result+=c.value;const next=c.text_continuations.value.next_offset;if(next===null)break;assert.ok(next>offset);offset=next;assert.ok(++calls<2000);}while(true);assert.equal(result,raw);
    await assert.rejects(f.q.query('get_workbook_cell',{...args,max_output_tokens:256},wireBytes),{code:'OUTPUT_BUDGET_TOO_SMALL'});
    const searched=await f.q.query('search_workbook_cells',{...args,query:'😀e\u0301',max_output_tokens:8000},wireBytes);assert.equal(searched.total,1);assert.ok(wireBytes(searched)<=8000);
    const none=await f.q.query('search_workbook_cells',{...args,query:'.*'});assert.equal(none.total,0);
  }finally{await f.close();}
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

test('readonly old libraries never migrate workbook tables; local releases are immutable labelled records and safe exports retain full SHA originals',async()=>{
  const empty=await mkdtemp(join(tmpdir(),'docver-workbook-readonly-')),writer=new Store(empty);writer.close();const ro=new Store(empty,true);try{const before=ro.db.prepare("SELECT name FROM sqlite_master ORDER BY name").all();assert.deepEqual(new WorkbookService(ro).projects(),[]);assert.deepEqual(ro.db.prepare("SELECT name FROM sqlite_master ORDER BY name").all(),before);}finally{ro.close();await rm(empty,{recursive:true,force:true});}
  const f=await fixture();try{
    const before=await Promise.all(f.paths.map(async p=>({bytes:await readFile(p),stat:await stat(p)}))),label='[unsafe](https://evil.example) ```\n<script>alert(1)</script>',release=f.service.publish(f.draft.project_id,f.report.report_id,label,'User supplied rationale, not true editing attribution'),next=f.service.publish(f.draft.project_id,f.report.report_id,label,'Second release record');assert.notEqual(release.release_id,next.release_id);assert.equal(release.provenance,'local_user_input_no_editor_authentication');assert.equal(release.schema_version,'workbook.1');
    const output=await f.service.export(f.draft.project_id,f.report.report_id,join(f.root,'export')),md=await readFile(output.files.find(p=>p.endsWith('.md'))!,'utf8'),json=JSON.parse(await readFile(output.files.find(p=>p.endsWith('.json'))!,'utf8'));assert.ok(md.includes('> ````text\n> [unsafe]'));assert.equal(json.releases.length,2);assert.equal(json.report.report_id,f.report.report_id);
    for(const r of f.report.revisions){assert.ok(md.includes(`(${r.asset_id.slice(7)}.csv)`));assert.equal(byteHash(await readFile(join(f.root,'export',r.asset_id.slice(7)+'.csv'))),r.asset_id.slice(7));}
    for(const [i,p]of f.paths.entries()){assert.deepEqual(await readFile(p),before[i].bytes);assert.equal((await stat(p)).mtimeMs,before[i].stat.mtimeMs);}
    const readOnly=new Store(f.store.root,true);try{const reader=new WorkbookService(readOnly);await assert.rejects(reader.create('no',[{path:f.paths[0],label:'x'}]),{code:'READ_ONLY'});assert.equal(reader.releases(f.draft.project_id).length,2);}finally{readOnly.close();}
  }finally{await f.close();}
});
