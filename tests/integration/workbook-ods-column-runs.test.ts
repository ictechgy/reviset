import test from 'node:test';
import assert from 'node:assert/strict';
import {setImmediate as yieldTurn} from 'node:timers/promises';
import {odsFixture} from '../workbook-fixtures.js';
import {extractWorkbook} from '../../packages/workbook/ingest.js';
import {blankCellsInViewport} from '../../packages/workbook/sparse.js';

const styles='<style:style style:name="paint" style:family="table-cell"><style:table-cell-properties fo:background-color="#ffee00"/></style:style><style:style style:name="axis" style:family="table-cell"><style:table-cell-properties fo:background-color="#0000ff"/></style:style>';
const styledRow=(columns=16_384)=>`<table:table-row><table:table-cell table:style-name="paint" table:number-columns-repeated="${columns}"/></table:table-row>`;

test('sparse column visibility runs clip source endpoints, merge equal visibility and preserve unmentioned columns',async()=>{
  const columns='<table:table-column table:number-columns-repeated="3" table:default-cell-style-name="axis"/><table:table-column table:number-columns-repeated="3" table:visibility="filter"/><table:table-column table:number-columns-repeated="2" table:visibility="collapse" table:default-cell-style-name="axis"/><table:table-column table:number-columns-repeated="2"/><table:table-column table:number-columns-repeated="2" table:visibility="collapse"/>';
  const cases=[{start:3,end:16,rows:20,hidden:false},{start:6,end:15,rows:30,hidden:true},{start:4,end:12,rows:40,hidden:false},{start:4,end:8,rows:50,hidden:false},{start:9,end:14,rows:60,hidden:false},{start:20,end:25,rows:70,hidden:false},{start:16_380,end:16_384,rows:80,hidden:false}];
  const rows=cases.map(c=>`<table:table-row table:number-rows-repeated="${c.rows}"${c.hidden?' table:visibility="filter"':''}><table:table-cell table:number-columns-repeated="${c.start-1}"/><table:table-cell table:style-name="paint" table:number-columns-repeated="${c.end-c.start+1}"/></table:table-row>`).join('');
  const observed=await extractWorkbook(odsFixture(columns+rows,{automatic:styles}),'ods'),sheet=observed.sheets[0];
  assert.equal(sheet.cells.length,0);assert.ok(sheet.coverage_gaps.some(g=>g.feature==='row_column_default_styles'));
  const runs=sheet.blank_style_ranges!;
  assert.deepEqual(runs.filter(r=>r.row_start===1).map(r=>[r.column_start,r.column_end,r.hidden_column]),[[3,3,false],[4,8,true],[9,10,false],[11,12,true],[13,16,false]]);
  let firstRow=1;
  for(const item of cases){
    const sourceRanges=runs.filter(r=>r.row_start===firstRow);assert.ok(sourceRanges.length>0);
    assert.equal(sourceRanges[0].column_start,item.start);assert.equal(sourceRanges.at(-1)!.column_end,item.end);
    assert.equal(sourceRanges.reduce((n,r)=>n+r.column_end-r.column_start+1,0),item.end-item.start+1);
    for(const range of sourceRanges){
      assert.equal(range.row_end,firstRow+item.rows-1);assert.equal(range.hidden_row,item.hidden);
      assert.equal(observed.style_definitions![range.style_ref!]['table-cell-properties.@fo:background-color'],'#ffee00');
    }
    for(const row of [firstRow,firstRow+item.rows-1])for(let column=item.start;column<=item.end;column++){
      const cells=blankCellsInViewport(sheet,row,row+1,column,column+1);assert.equal(cells.length,1);
      assert.equal(cells[0].hidden_column,column>=4&&column<=8||column>=11&&column<=12);
      assert.equal(cells[0].hidden_row,item.hidden);assert.equal(cells[0].value,null);
    }
    firstRow+=item.rows;
  }
  assert.equal(sheet.row_count,firstRow-1);assert.equal(sheet.column_count,16_384);
});

test('many full-width sparse source rows retain one rectangle each without expanding their cell area',async()=>{
  // 163,840,000 physical cells represented by 10,000 source rows. There is no
  // elapsed-time assertion: count, bounds and sparse output are the contract.
  const observed=await extractWorkbook(odsFixture(styledRow().repeat(10_000),{automatic:styles}),'ods'),sheet=observed.sheets[0];
  assert.equal(sheet.cells.length,0);assert.equal(sheet.blank_style_ranges!.length,10_000);
  assert.deepEqual(sheet.blank_style_ranges!.map(r=>[r.row_start,r.row_end,r.column_start,r.column_end,r.hidden_column]),Array.from({length:10_000},(_,i)=>[i+1,i+1,1,16_384,false]));
  const last=blankCellsInViewport(sheet,10_000,10_001,16_384,16_385)[0];assert.equal(last.address,'XFD10000');assert.equal(last.source_range,'A10000:XFD10000');
});

test('visibility fragmentation retains the independent 100000-rectangle rejection budget',async()=>{
  const columns=Array.from({length:16_384},(_,i)=>`<table:table-column${i%2?' table:visibility="collapse"':''}/>`).join('');
  await assert.rejects(extractWorkbook(odsFixture(columns+styledRow().repeat(7),{automatic:styles}),'ods'),{code:'WORKBOOK_LIMIT',message:'Workbook explicit blank formatting ranges exceed 100000 entries'});
});

test('wide sparse ingestion remains cooperatively cancellable before emitting its complete observation',async()=>{
  const bytes=odsFixture(styledRow().repeat(20_000),{automatic:styles}),controller=new AbortController();
  // Event-loop turns, rather than a wall-clock deadline, make cancellation
  // deterministic while the large run is in progress.
  const cancel=(async()=>{for(let i=0;i<30;i++)await yieldTurn();controller.abort();})();
  await assert.rejects(extractWorkbook(bytes,'ods',{signal:controller.signal}),{code:'CANCELLED'});await cancel;
});

test('known annotation namespace aliases stay sparse and unknown namespace lookalikes fail closed',async()=>{
  const tableUri='urn:oasis:names:tc:opendocument:xmlns:table:1.0';
  const content=(attribute:string)=>`<table:table table:name="Aliases" xmlns:t="${tableUri}" xmlns:future="urn:reviset:test:future"><t:table-row t:number-rows-repeated="1048576"><t:table-cell t:number-columns-repeated="16384" t:style-name="paint" ${attribute}/></t:table-row></table:table>`;
  const observed=await extractWorkbook(odsFixture(content('t:content-validation-name="v" t:protected="true"'),{automatic:styles}),'ods'),sheet=observed.sheets[0];
  assert.equal(sheet.cells.length,0);assert.equal(sheet.blank_style_ranges!.length,1);assert.deepEqual(sheet.coverage_gaps.map(g=>g.feature).sort(),['cell_protection','data_validation']);
  for(const attribute of ['future:protected="true"','future:content-validation-name="v"','t:future-attribute="unknown"'])await assert.rejects(extractWorkbook(odsFixture(content(attribute),{automatic:styles}),'ods'),{code:'WORKBOOK_LIMIT',message:'ODS materialized repetitions exceed cell budget'});
  const values=content('office:value-type="float" office:value="0"').replaceAll('office:value-type','o:value-type').replaceAll('office:value=','o:value=').replace('xmlns:t=', 'xmlns:o="urn:oasis:names:tc:opendocument:xmlns:office:1.0" xmlns:t=');
  await assert.rejects(extractWorkbook(odsFixture(values,{automatic:styles}),'ods'),{code:'WORKBOOK_LIMIT',message:'ODS materialized repetitions exceed cell budget'});
});
