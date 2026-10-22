import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,writeFile,readFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {odsFixture,xlsxFixture} from '../workbook-fixtures.js';
import {extractWorkbook} from '../../packages/workbook/ingest.js';
import {diffWorkbooks,WorkbookReport,type WorkbookRevisionData} from '../../packages/workbook/diff.js';
import {validateIdentity,WorkbookService} from '../../packages/workbook/service.js';
import {WorkbookQueryService} from '../../packages/workbook/query.js';
import {Store} from '../../packages/storage/index.js';
import {blankCellsInViewport,blankStylesAtCells} from '../../packages/workbook/sparse.js';
import {cellAddress,workbookID} from '../../packages/workbook/types.js';
import {canonical,hash} from '../../packages/schema/index.js';

const styles='<style:style style:name="paint" style:family="table-cell"><style:table-cell-properties fo:background-color="#ffff00"/></style:style><style:style style:name="other" style:family="table-cell"><style:table-cell-properties fo:background-color="#ff0000"/></style:style>';
const blank=(count:number)=>count?`<table:table-cell table:style-name="paint" table:number-columns-repeated="${count}"/>`:'';
const value=(text:string,style='paint')=>`<table:table-cell table:style-name="${style}" office:value-type="string"><text:p>${text}</text:p></table:table-cell>`;
const revision=async(xml:string,id:string):Promise<WorkbookRevisionData>=>({...await extractWorkbook(odsFixture(xml,{automatic:styles}),'ods'),revision_occurrence_id:id,label:id,index:id==='before'?0:1,asset_id:'sha256:'+'a'.repeat(64)});

test('blank/content transitions retain paired physical observations and do not claim formatting disappeared',async()=>{
  for(const columns of [1,64,65,100])for(const changedStyle of [false,true])for(const reverse of [false,true]){
    const offset=Math.floor(columns/2),column=3+offset,address=cellAddress(5,column),prefix='<table:table-row table:number-rows-repeated="4"/><table:table-row><table:table-cell table:number-columns-repeated="2"/>';
    const empty=await revision(prefix+blank(columns)+'</table:table-row>','before'),filled=await revision(prefix+blank(offset)+value('typed',changedStyle?'other':'paint')+blank(columns-offset-1)+'</table:table-row>','after');
    const [before,after]=reverse?[filled,empty]:[empty,filled],events=diffWorkbooks(before,after),content=events.find(c=>c.kind==='cell_observation');
    assert.ok(content,`paired observation for ${columns}, changedStyle=${changedStyle}, reverse=${reverse}`);assert.equal(content.before_address,address);assert.equal(content.after_address,address);assert.equal(content.association,'needs_review');assert.equal(content.alignment_method,'physical_blank_content_coordinate');
    assert.ok(events.every(c=>c.before!==null&&c.after!==null));assert.ok(!events.some(c=>c.kind==='formatting_range'||c.kind==='row_correspondence'));
    const observedBlank=reverse?content.after!:content.before!,observedValue=reverse?content.before!:content.after!;assert.equal(observedBlank.blank_style_only,true);assert.equal(observedBlank.value,null);assert.equal(observedValue.value,'typed');
    const source=empty.sheets[0].cells.find(c=>c.address===address)??blankCellsInViewport(empty.sheets[0],5,6,column,column+1)[0];assert.equal(observedBlank.source_ref,source.source_ref);assert.equal(observedBlank.style_ref,source.style_ref);assert.equal(observedBlank.source_range,source.source_range);
    if(columns>64)assert.equal(observedBlank.difference_range,`${address}:${address}`);
    assert.equal(events.filter(c=>c.kind==='style').length,changedStyle?1:0);assert.ok(events.every(c=>c.association==='needs_review'));
  }
});

test('physical blank transitions do not invent row lineage or override matched content moves',async()=>{
  const before=await revision('<table:table-row>'+value('key')+value('payload')+'</table:table-row><table:table-row>'+blank(2)+'</table:table-row>','before');
  const after=await revision('<table:table-row>'+blank(2)+'</table:table-row><table:table-row>'+value('key')+value('payload')+'</table:table-row>','after');
  const moved=diffWorkbooks(before,after);assert.equal(moved.length,1);assert.equal(moved[0].kind,'row_position');assert.equal(moved[0].before?.value,'key');assert.equal(moved[0].after?.value,'key');assert.equal(moved[0].before_address,'A1');assert.equal(moved[0].after_address,'A2');
  const ambiguousBefore=await revision('<table:table-row>'+value('duplicate')+blank(1)+'</table:table-row><table:table-row>'+value('duplicate')+value('old')+'</table:table-row>','before');
  const ambiguousAfter=await revision('<table:table-row>'+value('duplicate')+value('new')+'</table:table-row><table:table-row>'+value('duplicate')+blank(1)+'</table:table-row>','after');
  const transitions=diffWorkbooks(ambiguousBefore,ambiguousAfter).filter(c=>c.alignment_method==='physical_blank_content_coordinate');assert.equal(transitions.length,2);assert.ok(transitions.every(c=>c.kind==='cell_observation'&&c.association==='needs_review'&&c.before_address===c.after_address&&c.before&&c.after));
});

test('change formatting-range style references must belong to their endpoint occurrence',async()=>{
  const before=await revision('<table:table-row>'+blank(100)+'</table:table-row>','before'),after=await revision('<table:table-row><table:table-cell table:style-name="other" table:number-columns-repeated="100"/></table:table-row>','after');
  for(const r of [before,after])r.sheets[0].sheet_id='sheet_'+r.revision_occurrence_id;
  const body={schema_version:'workbook.1' as const,engine_version:'workbook.1.1' as const,project_id:'wprj_range_scope',title:'range scope',status:'complete' as const,comparison_coverage:'supported_cells_only' as const,calculation:'stored_values_only_no_recalculation' as const,revisions:[before,after],changes:diffWorkbooks(before,after),coverage_gaps:[]};
  const valid=WorkbookReport.parse({...body,report_id:workbookID('wreport',body)});validateIdentity(valid);
  for(const side of ['before','after'] as const){const invalid=structuredClone(valid),change=invalid.changes[0],other=side==='before'?'after':'before';change[`${side}_blank_style_range`]!.style_ref=change[`${other}_blank_style_range`]!.style_ref;const {report_id:_,...invalidBody}=invalid;invalid.report_id=workbookID('wreport',invalidBody);assert.throws(()=>validateIdentity(WorkbookReport.parse(invalid)),{code:'WORKBOOK_STYLE_SCOPE'});}
});

test('a full-sheet blank transition is bounded and preserves original and single-coordinate provenance', {timeout:5000}, async()=>{
  const before=await revision('<table:table-row table:number-rows-repeated="1048576">'+blank(16384)+'</table:table-row>','before');
  const after=await revision('<table:table-row table:number-rows-repeated="1048575">'+blank(16384)+'</table:table-row><table:table-row>'+blank(16383)+value('last')+'</table:table-row>','after');
  const events=diffWorkbooks(before,after);assert.equal(events.length,1);const event=events[0];assert.equal(event.kind,'cell_observation');assert.equal(event.before?.source_range,'A1:XFD1048576');assert.equal(event.before?.difference_range,'XFD1048576:XFD1048576');assert.equal(event.before_address,'XFD1048576');assert.equal(event.after?.value,'last');assert.equal(before.sheets[0].cells.length,0);assert.equal(after.sheets[0].cells.length,1);
});

test('masking a content coordinate retains differing blank style bands around it with source provenance',async()=>{
  const before=await revision('<table:table-row>'+blank(100)+'</table:table-row>','before'),after=await revision('<table:table-row>'+blank(49).replaceAll('paint','other')+value('middle')+blank(50).replaceAll('paint','other')+'</table:table-row>','after');
  const events=diffWorkbooks(before,after),ranges=events.filter(c=>c.kind==='formatting_range');assert.ok(ranges.length>0);let area=0;
  for(const event of ranges){const r=event.before_blank_style_range!;assert.ok(r.column_end<50||r.column_start>50);area+=(r.column_end-r.column_start+1)*(r.row_end-r.row_start+1);assert.equal(event.before?.source_range,'A1:CV1');assert.ok(event.before&&event.after);}
  assert.equal(area,99);assert.equal(events.filter(c=>c.alignment_method==='physical_blank_content_coordinate').length,1);
});

test('formula-dependent blank transitions retain unresolved endpoints and do not assert formula edits',async()=>{
  const matrix='<table:table-cell table:formula="of:=1" office:value-type="float" office:value="1" table:number-matrix-columns-spanned="101"/>';
  const before=await revision('<table:table-row>'+matrix+blank(100)+'</table:table-row>','before'),after=await revision('<table:table-row>'+matrix+blank(50)+value('saved result')+blank(49)+'</table:table-row>','after');
  const events=diffWorkbooks(before,after),transition=events.find(c=>c.alignment_method==='physical_blank_content_coordinate');assert.ok(transition);assert.equal(transition.before?.formula_interpretation,'unresolved');assert.equal(transition.before?.cache_freshness,'unknown');assert.equal(transition.after?.value,'saved result');assert.ok(!events.some(c=>c.kind==='formula'||c.kind==='stored_value'||c.kind==='value_type'));assert.ok(events.every(c=>c.before&&c.after));
});

test('cross-format compressed blanks retain explicit endpoints without asserting style equivalence',async()=>{
  const blankSource=await revision('<table:table-row>'+blank(100)+'</table:table-row>','before');
  const xlsx:WorkbookRevisionData={...await extractWorkbook(xlsxFixture('<sheetData><row r="1"><c r="B1" t="inlineStr"><is><t>value</t></is></c></row></sheetData>'),'xlsx'),revision_occurrence_id:'after',label:'after',index:1,asset_id:'sha256:'+'b'.repeat(64)};
  for(const [before,after]of [[blankSource,xlsx],[xlsx,blankSource]]){const events=diffWorkbooks(before,after),transition=events.find(c=>c.alignment_method==='physical_blank_content_coordinate');assert.ok(transition);assert.ok(transition.before&&transition.after);assert.equal(transition.before_address,'B1');assert.equal(transition.after_address,'B1');assert.ok(!events.some(c=>c.kind==='style'||c.kind==='number_format'||c.kind==='formatting_range'));}
});

test('blank point lookup agrees with independent coordinate checks across range boundaries and small cells',async()=>{
  const source=await revision('<table:table-row table:number-rows-repeated="3"><table:table-cell table:number-columns-repeated="2"/>'+blank(100)+'</table:table-row><table:table-row table:number-rows-repeated="2"/><table:table-row><table:table-cell table:number-columns-repeated="5"/>'+blank(3)+'</table:table-row><table:table-row table:number-rows-repeated="2">'+blank(128)+'</table:table-row>','before');
  const content=(await revision('<table:table-row>'+value('probe')+'</table:table-row>','after')).sheets[0].cells[0],probes=Array.from({length:12*130},(_,i)=>({...content,row:Math.floor(i/130)+1,column:i%130+1,address:cellAddress(Math.floor(i/130)+1,i%130+1)})),sheet=source.sheets[0],found=blankStylesAtCells(sheet,probes);
  for(const cell of probes){const expected=sheet.cells.find(c=>c.blank_style_only&&c.row===cell.row&&c.column===cell.column)??sheet.blank_style_ranges?.find(r=>r.row_start<=cell.row&&r.row_end>=cell.row&&r.column_start<=cell.column&&r.column_end>=cell.column);assert.equal(found.get(cell),expected,cell.address);}
  const controller=new AbortController();controller.abort();assert.throws(()=>blankStylesAtCells(sheet,probes,controller.signal));
});

test('stored reports, bounded MCP queries, net comparison and exports agree on explicit blank transition availability',async()=>{
  const root=await mkdtemp(join(tmpdir(),'reviset-blank-transition-')),store=new Store(join(root,'library'));
  try{
    const empty=join(root,'empty.ods'),filled=join(root,'filled.ods');await writeFile(empty,odsFixture('<table:table-row>'+blank(100)+'</table:table-row>',{automatic:styles}));await writeFile(filled,odsFixture('<table:table-row>'+blank(49)+value('middle')+blank(50)+'</table:table-row>',{automatic:styles}));
    const service=new WorkbookService(store),project=await service.create('blank transitions',[{label:'blank',path:empty},{label:'filled',path:filled},{label:'cleared',path:empty}]),stage=await service.run(project.project_id);await service.commit(project.project_id,stage);
    const report=service.report(project.project_id,stage.report_id),q=new WorkbookQueryService(service,new Set([project.project_id])),scope={project_id:project.project_id,report_id:report.report_id};assert.equal(report.changes.length,2);
    for(const change of report.changes){assert.equal(change.kind,'cell_observation');for(const component of ['before','after']){const details=await q.query('get_workbook_change',{...scope,change_id:change.change_id,component,max_output_tokens:8000}),item=details.items[0];assert.equal(item.before_observation,'available');assert.equal(item.after_observation,'available');assert.equal(item[component].address,'AX1');assert.ok(item[component].source_ref);}}
    const source=report.revisions[0],cell=await q.query('get_workbook_cell',{...scope,revision_occurrence_id:source.revision_occurrence_id,sheet_id:source.sheets[0].sheet_id,row:1,column:50,max_output_tokens:8000});assert.equal(cell.availability,'available');assert.equal(cell.items[0].value,null);assert.equal(cell.items[0].source_range,report.changes[0].before?.source_range);
    const interval={...scope,from_revision_occurrence_id:source.revision_occurrence_id,to_revision_occurrence_id:report.revisions[2].revision_occurrence_id,max_output_tokens:8000};assert.equal((await q.query('list_workbook_changes',{...interval,mode:'history'})).total,2);assert.equal((await q.query('list_workbook_changes',{...interval,mode:'range_net'})).total,0);
    const exported=await service.export(project.project_id,report.report_id,join(root,'export'));assert.deepEqual(JSON.parse(await readFile(exported.files[0],'utf8')).report,report);
  }finally{store.close();await rm(root,{recursive:true,force:true});}
});

test('zero and empty-string transitions remain distinct from an available explicit blank endpoint',async()=>{
  for(const columns of [1,100])for(const [attrs,expected,type]of [['office:value-type="float" office:value="0"','0','number'],['office:value-type="string" office:string-value=""','','string']]){
    const empty=await revision('<table:table-row>'+blank(columns)+'</table:table-row>','before'),filled=await revision('<table:table-row><table:table-cell table:style-name="paint" '+attrs+'/>'+blank(columns-1)+'</table:table-row>','after');
    for(const reverse of [false,true]){const events=diffWorkbooks(...(reverse?[filled,empty]:[empty,filled]) as [WorkbookRevisionData,WorkbookRevisionData]);assert.equal(events.length,1);const event=events[0];assert.equal(event.kind,'cell_observation');assert.ok(event.before&&event.after);const blankEndpoint=reverse?event.after:event.before,valueEndpoint=reverse?event.before:event.after;assert.equal(blankEndpoint.value,null);assert.equal(blankEndpoint.value_type,'blank');assert.equal(valueEndpoint.value,expected);assert.equal(valueEndpoint.value_type,type);assert.equal(event.before_address,'A1');assert.equal(event.after_address,'A1');}
  }
});

test('hash-valid indexed formatting ranges cannot expose a style from the opposite source occurrence',async()=>{
  const root=await mkdtemp(join(tmpdir(),'reviset-range-style-scope-')),store=new Store(join(root,'library'));
  try{
    const sources=[];for(const name of ['paint','other']){const path=join(root,name+'.ods');await writeFile(path,odsFixture('<table:table-row>'+blank(100).replaceAll('paint',name)+'</table:table-row>',{automatic:styles}));sources.push({label:name,path});}
    const service=new WorkbookService(store),project=await service.create('range style scope',sources),stage=await service.run(project.project_id);await service.commit(project.project_id,stage);const report=service.report(project.project_id,stage.report_id),row=store.db.prepare('SELECT * FROM workbook_changes_v1 WHERE report_id=?').get(report.report_id)!,change=JSON.parse(String(row.body));
    change.before_blank_style_range.style_ref=change.after_blank_style_range.style_ref;const {change_id:_,...content}=change;change.change_id=workbookID('wchg',content);const body=canonical(change);store.db.prepare('UPDATE workbook_changes_v1 SET change_id=?,body=?,body_sha=? WHERE report_id=? AND position=?').run(change.change_id,body,hash({report_id:report.report_id,position:row.position,body}),report.report_id,row.position);
    const q=new WorkbookQueryService(service,new Set([project.project_id]));await assert.rejects(q.query('list_workbook_changes',{project_id:project.project_id,report_id:report.report_id,from_revision_occurrence_id:report.revisions[0].revision_occurrence_id,to_revision_occurrence_id:report.revisions[1].revision_occurrence_id}),{code:'WORKBOOK_STYLE_SCOPE'});assert.deepEqual(service.report(project.project_id,report.report_id),report);
  }finally{store.close();await rm(root,{recursive:true,force:true});}
});
