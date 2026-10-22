import test from 'node:test';
import assert from 'node:assert/strict';
import {odsFixture} from '../workbook-fixtures.js';
import {extractWorkbook} from '../../packages/workbook/ingest.js';
import {blankCellsInViewport} from '../../packages/workbook/sparse.js';

const annotations='table:content-validation-name="v1" table:protect="true" table:protected="true"';
const style='<style:style style:name="base" style:family="table-cell"><style:table-cell-properties fo:background-color="#ff8800"/></style:style><style:style style:name="child" style:family="table-cell" style:parent-style-name="base"/>';
const rows=(attrs:string,body='',rowCount=1_048_576,columns=16_384)=>`<table:table-row table:number-rows-repeated="${rowCount}"><table:table-cell table:number-columns-repeated="${columns}" ${attrs}>${body}</table:table-cell></table:table-row>`;

test('full-sheet validation and protection annotations stay sparse with explicit coverage gaps',async()=>{
  for(const attrs of ['table:content-validation-name="v1"','table:content-validation-name=""','table:protect="true"','table:protected="true"',annotations]){
    const observed=await extractWorkbook(odsFixture(rows(attrs)),'ods'),sheet=observed.sheets[0];
    assert.equal(sheet.cells.length,0,attrs);assert.equal(sheet.blank_style_ranges,undefined);assert.equal(sheet.cell_extraction_complete,true);
    assert.equal(sheet.coverage_gaps.filter(g=>g.feature==='data_validation').length,attrs.includes('content-validation-name')?1:0);
    assert.equal(sheet.coverage_gaps.filter(g=>g.feature==='cell_protection').length,attrs.includes('table:protect')?1:0);
    assert.ok(sheet.coverage_gaps.every(g=>g.sheet_id===sheet.sheet_id&&g.address===undefined));
  }
});

test('annotation-only runs preserve explicit inherited styles as ranges and leave axis defaults explicitly unsupported',async()=>{
  const observed=await extractWorkbook(odsFixture(rows(`${annotations} table:style-name="child"`),{automatic:style}),'ods'),sheet=observed.sheets[0];
  assert.equal(sheet.cells.length,0);assert.equal(sheet.blank_style_ranges?.length,1);const range=sheet.blank_style_ranges![0];
  assert.equal(observed.style_definitions![range.style_ref!]['table-cell-properties.@fo:background-color'],'#ff8800');
  const last=blankCellsInViewport(sheet,1_048_576,1_048_577,16_384,16_385)[0];assert.equal(last.address,'XFD1048576');assert.equal(last.source_range,'A1:XFD1048576');
  assert.deepEqual(sheet.coverage_gaps.map(g=>g.feature).sort(),['cell_protection','data_validation']);
  for(const axis of ['row','column']){
    const xml=axis==='row'?rows(annotations).replace('<table:table-row ','<table:table-row table:default-cell-style-name="child" '):'<table:table-column table:number-columns-repeated="16384" table:default-cell-style-name="child"/>'+rows(annotations);
    const defaults=(await extractWorkbook(odsFixture(xml,{automatic:style}),'ods')).sheets[0];assert.equal(defaults.cells.length,0);assert.equal(defaults.blank_style_ranges,undefined);assert.deepEqual(defaults.coverage_gaps.map(g=>g.feature).sort(),['cell_protection','data_validation','row_column_default_styles']);
  }
});

test('annotation exceptions never sparsify values, formulas, spans, extensions, unknown attributes or child content',async()=>{
  const material=[
    'office:string-value="saved"','office:value="1"','office:value-type="float"','office:boolean-value="true"','office:date-value="2026-10-23"','office:time-value="PT1H"','office:currency="USD"',
    'table:formula="of:=1"','table:number-columns-spanned="1"','table:number-rows-spanned="1"','table:number-matrix-columns-spanned="1"','table:number-matrix-rows-spanned="1"','table:matrix-covered="true"','calcext:value-type="error"','table:future-attribute="unknown"',
  ];
  for(const attrs of material){
    const xml='<table:table table:name="Strict" xmlns:calcext="urn:org:documentfoundation:names:experimental:calc:xmlns:calcext:1.0">'+rows(`${annotations} ${attrs}`,'',31)+'</table:table>';
    await assert.rejects(extractWorkbook(odsFixture(xml),'ods'),{code:'WORKBOOK_LIMIT'},attrs);
  }
  for(const child of ['<text:p>saved</text:p>','<office:annotation><text:p>comment</text:p></office:annotation>'])await assert.rejects(extractWorkbook(odsFixture(rows(annotations,child,31)),'ods'),{code:'WORKBOOK_LIMIT'});
  await assert.rejects(extractWorkbook(odsFixture(rows(annotations,'',31).replaceAll('table:table-cell','table:covered-table-cell')),'ods'),{code:'WORKBOOK_LIMIT'});
  const small=await extractWorkbook(odsFixture('<table:table-row><table:table-cell '+annotations+' office:string-value="saved"/><table:table-cell '+annotations+' table:formula="of:=1" office:value-type="float" office:value="1"/></table:table-row>'),'ods');
  assert.deepEqual(small.sheets[0].cells.map(c=>[c.value,c.formula,c.blank_style_only]),[['saved',null,undefined],['1','of:=1',undefined]]);assert.equal(small.sheets[0].blank_style_ranges,undefined);
});
