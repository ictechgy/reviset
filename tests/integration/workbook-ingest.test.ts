import test from 'node:test';
import assert from 'node:assert/strict';
import { unzipSync, zipSync, strToU8 } from 'fflate';
import { extractWorkbook, WORKBOOK_LIMITS } from '../../packages/workbook/ingest.js';
import { WorkbookObservation } from '../../packages/workbook/types.js';
import { xlsxFixture, odsFixture, workbookStyles, defaultStyledXlsxFixture } from '../workbook-fixtures.js';

const code = (value: string) => (error: unknown) => typeof error === 'object' && error !== null && 'code' in error && error.code === value;
const cell = (observation: Awaited<ReturnType<typeof extractWorkbook>>, address: string) => observation.sheets[0].cells.find(item => item.address === address)!;
const style = (observation: Awaited<ReturnType<typeof extractWorkbook>>, address: string) => { const item = cell(observation,address); return item.style_ref ? observation.style_definitions![item.style_ref] : item.style; };

test('XLSX preserves formula source, cache, constants, zero, blank, dates and numeric-looking text independently',async () => {
  const bytes = xlsxFixture('<sheetData><row r="1"><c r="A1"><f>SUM(A2:A3)</f><v>120.00</v></c><c r="B1"><v>120.00</v></c><c r="C1"><f>1+1</f></c><c r="D1" t="str"><f>IF(1,&quot;&quot;,&quot;X&quot;)</f><v/></c><c r="E1" t="inlineStr"><is><t>00120</t></is></c><c r="F1"><v>0</v></c><c r="G1"/><c r="H1" t="b"><v>0</v></c><c r="I1" t="d"><v>2026-10-22T01:00:00Z</v></c></row></sheetData>',{date1904:true});
  const original = bytes.slice(), observed = await extractWorkbook(bytes,'xlsx'); WorkbookObservation.parse(observed); assert.deepEqual(bytes,original);
  assert.equal(cell(observed,'A1').formula,'SUM(A2:A3)'); assert.equal(cell(observed,'A1').value,cell(observed,'B1').value); assert.equal(cell(observed,'B1').formula,null); assert.equal(cell(observed,'A1').formula_dialect,'xlsx_a1'); assert.equal(cell(observed,'A1').cache_freshness,'unknown');
  assert.equal(cell(observed,'C1').value,null); assert.equal(cell(observed,'C1').cached_result,'missing'); assert.equal(cell(observed,'D1').value,''); assert.equal(cell(observed,'D1').cached_result,'present');
  assert.equal(cell(observed,'E1').value,'00120'); assert.equal(cell(observed,'E1').value_type,'string'); assert.equal(cell(observed,'F1').value,'0'); assert.equal(cell(observed,'G1').value_type,'blank'); assert.equal(cell(observed,'H1').value_type,'boolean'); assert.equal(cell(observed,'I1').value_type,'date');
  assert.equal(observed.date_system,'1904'); assert.equal(observed.calc_flags.fullCalcOnLoad,'1'); assert.equal(observed.sheets[0].cell_extraction_complete,true); assert.ok(observed.sheets[0].coverage_gaps.some(gap => gap.feature === 'missing_formula_cache'));
});

test('XLSX hidden sheets/rows/columns, empty metadata, styles and merges remain sparse and semantic',async () => {
  const observed = await extractWorkbook(xlsxFixture('<dimension ref="A1:D9"/><cols><col min="2" max="3" hidden="1" width="18.00"/></cols><sheetData><row r="2" hidden="1" ht="23.5"><c r="B2" s="1"><v>2.000</v></c></row><row r="9" hidden="1"/></sheetData><mergeCells><mergeCell ref="B2:C3"/></mergeCells>',{hidden:true,styles:workbookStyles}),'xlsx');
  assert.equal(observed.sheets[0].hidden,true); assert.equal(observed.sheets[0].row_count,9); assert.equal(observed.sheets[0].cells.length,1); assert.equal(cell(observed,'B2').hidden_row,true); assert.equal(cell(observed,'B2').hidden_column,true); assert.equal(cell(observed,'B2').number_format,'0.000'); assert.equal(style(observed,'B2') ['font.b'],'true'); assert.equal(style(observed,'B2') ['alignment.horizontal'],'right');
  assert.deepEqual(observed.sheets[0].merges,['B2:C3']); assert.deepEqual(observed.sheets[0].column_metadata,[{start:2,end:3,hidden:true,size:'18.00'}]); assert.ok(observed.sheets[0].row_metadata.some(meta => meta.start === 9 && meta.hidden));
});

test('XLSX semantic formatting is independent of custom format index',async () => {
  const source = '<sheetData><row r="1"><c r="A1" s="1"><v>7</v></c></row></sheetData>';
  const a = await extractWorkbook(xlsxFixture(source,{styles:workbookStyles}),'xlsx'), b = await extractWorkbook(xlsxFixture(source,{styles:workbookStyles.replaceAll('164','170')}),'xlsx'); assert.deepEqual(cell(a,'A1'),cell(b,'A1'));
});

test('XLSX shared and inline rich text preserve XML/OOXML escaping and Unicode order',async () => {
  const bytes = xlsxFixture('<sheetData><row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="inlineStr"><is><r><t>한글&amp;</t></r><r><t>😀_x000A_끝_x005F_x0041_</t></r></is></c></row></sheetData>',{shared:'<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><si><r><t>A</t></r><r><rPr><b/></rPr><t>&lt;B&gt;</t></r></si></sst>'});
  const observed = await extractWorkbook(bytes,'xlsx'); assert.equal(cell(observed,'A1').value,'A<B>'); assert.equal(cell(observed,'B1').value,'한글&😀\n끝_x0041_'); assert.ok(observed.coverage_gaps.some(gap => gap.feature === 'rich_text'));
});

test('XLSX shared formula followers retain present-but-empty formula source and explicit gap',async () => {
  const observed = await extractWorkbook(xlsxFixture('<sheetData><row r="1"><c r="A1"><f t="shared" si="0" ref="A1:B1">1+1</f><v>2</v></c><c r="B1"><f t="shared" si="0"/><v>2</v></c></row></sheetData>'),'xlsx'); assert.equal(cell(observed,'B1').formula,''); assert.equal(cell(observed,'B1').cached_result,'present'); assert.ok(observed.sheets[0].coverage_gaps.some(gap => gap.feature === 'shared_array_formulas'));
});

test('ODS preserves typed lexical cache, empty strings, rich paragraphs, formulas, styles and hidden metadata',async () => {
  const automatic = '<style:style style:name="ce1" style:family="table-cell"><style:text-properties fo:font-weight="bold"/></style:style><style:style style:name="co1" style:family="table-column"><style:table-column-properties style:column-width="2.3cm"/></style:style><style:style style:name="ta1" style:family="table"><style:table-properties table:display="false"/></style:style>';
  const observed = await extractWorkbook(odsFixture('<table:table table:name="예산" table:style-name="ta1"><table:table-column table:style-name="co1" table:visibility="collapse"/><table:table-row table:visibility="collapse"><table:table-cell office:value-type="float" office:value="120.00" table:formula="of:=SUM([.A2:.A3])" table:style-name="ce1" table:number-columns-spanned="2"><text:p>120</text:p></table:table-cell><table:covered-table-cell/><table:table-cell office:value-type="string"><text:p>A<text:span>B</text:span>C<text:s text:c="2"/>D<text:tab/>E<text:line-break/>F</text:p><text:p>한글😀</text:p></table:table-cell><table:table-cell office:value-type="string" office:string-value="" table:formula="of:=&quot;&quot;"/><table:table-cell table:formula="of:=2+2"/></table:table-row></table:table>',{automatic}),'ods');
  WorkbookObservation.parse(observed); assert.equal(observed.date_system,'iso8601'); assert.equal(observed.sheets[0].hidden,true); assert.equal(cell(observed,'A1').value,'120.00'); assert.equal(cell(observed,'A1').formula,'of:=SUM([.A2:.A3])'); assert.equal(cell(observed,'A1').formula_dialect,'ods_openformula'); assert.equal(style(observed,'A1') ['text-properties.font-weight'],'bold'); assert.equal(cell(observed,'A1').hidden_column,true); assert.equal(cell(observed,'C1').value,'ABC  D\tE\nF\n한글😀'); assert.equal(cell(observed,'D1').value,''); assert.equal(cell(observed,'D1').cached_result,'present'); assert.equal(cell(observed,'E1').cached_result,'missing'); assert.deepEqual(observed.sheets[0].merges,['A1:B1']); assert.equal(observed.sheets[0].column_metadata[0].size,'2.3cm');
});

test('ODS skips a million empty repeated rows without materializing them and rejects expansion beyond limits',async () => {
  const observed = await extractWorkbook(odsFixture('<table:table-row><table:table-cell office:value-type="string"><text:p>One</text:p></table:table-cell></table:table-row><table:table-row table:number-rows-repeated="1048575"><table:table-cell table:number-columns-repeated="16384"/></table:table-row>'),'ods'); assert.equal(observed.sheets[0].cells.length,1); assert.equal(observed.sheets[0].row_count,1);
  await assert.rejects(extractWorkbook(odsFixture('<table:table-row table:number-rows-repeated="1048577"/>'),'ods'),code('WORKBOOK_LIMIT'));
  await assert.rejects(extractWorkbook(odsFixture('<table:table-row table:number-rows-repeated="500001"><table:table-cell office:value-type="float" office:value="1"/></table:table-row>'),'ods'),code('WORKBOOK_LIMIT'));
  await assert.rejects(extractWorkbook(odsFixture('<table:table-row><table:table-cell table:number-columns-repeated="16385"/></table:table-row>'),'ods'),code('WORKBOOK_LIMIT'));
});

test('ODS styled empty cells are retained, including repeated styles and blank rows/column visibility',async () => {
  const observed = await extractWorkbook(odsFixture('<table:table-column table:visibility="collapse" table:number-columns-repeated="2"/><table:table-row table:number-rows-repeated="2" table:visibility="filter"><table:table-cell table:style-name="ce1" table:number-columns-repeated="2"/></table:table-row>',{automatic:'<style:style style:name="ce1" style:family="table-cell"><style:table-cell-properties fo:background-color="#ffee00"/></style:style>'}),'ods'); assert.equal(observed.sheets[0].cells.length,4); assert.equal(cell(observed,'B2').value_type,'blank'); assert.equal(cell(observed,'B2').hidden_row,true); assert.equal(style(observed,'B2') ['table-cell-properties.background-color'],'#ffee00'); assert.deepEqual(observed.sheets[0].row_metadata,[{start:1,end:2,hidden:true,size:null}]);
});

test('UTF-8 CSV preserves quoted newlines, quotes, numeric text, blank, formula-looking text and Unicode',async () => {
  const observed = await extractWorkbook(strToU8('\ufeff00120,"한글😀\n둘째","a""b",,=SUM(A1:A2)\r\n0,120,,,\r\n'),'csv'); WorkbookObservation.parse(observed); assert.equal(cell(observed,'A1').value,'00120'); assert.equal(cell(observed,'B1').value,'한글😀\n둘째'); assert.equal(cell(observed,'C1').value,'a"b'); assert.equal(cell(observed,'D1').value_type,'blank'); assert.equal(cell(observed,'E1').formula,null); assert.equal(cell(observed,'E1').value,'=SUM(A1:A2)'); assert.equal(observed.sheets[0].row_count,2); assert.equal(observed.sheets[0].column_count,5); assert.ok(observed.coverage_gaps.some(gap => gap.feature === 'untyped_csv'));
  const empty = await extractWorkbook(new Uint8Array(),'csv'); assert.equal(empty.sheets[0].cells.length,0);
});

test('CSV rejects malformed quotes, invalid UTF-8, binary NUL and oversized fields without truncation',async () => {
  for (const text of ['"unfinished','one"two','"closed"junk','a\0b']) await assert.rejects(extractWorkbook(strToU8(text),'csv'),code('INVALID_WORKBOOK'));
  await assert.rejects(extractWorkbook(new Uint8Array([0xff,0xfe,0x31,0]),'csv'),code('UNSUPPORTED_WORKBOOK'));
  await assert.rejects(extractWorkbook(strToU8('x'.repeat(WORKBOOK_LIMITS.cellText + 1)),'csv'),code('WORKBOOK_LIMIT'));
});

test('cross-format observations expose capability gaps rather than inventing CSV types or recalculation',async () => {
  const xlsx = await extractWorkbook(xlsxFixture('<sheetData><row r="1"><c r="A1"><v>42</v></c></row></sheetData>'),'xlsx'), ods = await extractWorkbook(odsFixture('<table:table-row><table:table-cell office:value-type="float" office:value="42"/></table:table-row>'),'ods'), csv = await extractWorkbook(strToU8('42'),'csv');
  assert.equal(cell(xlsx,'A1').value,cell(ods,'A1').value); assert.equal(cell(csv,'A1').value_type,'string'); for (const item of [xlsx,ods,csv]) assert.equal(item.calculation,'stored_values_only_no_recalculation'); assert.notEqual(xlsx.sheets[0].sheet_id,ods.sheets[0].sheet_id);
});

test('ZIP traversal, duplicate names, compression size lies, CRC corruption and expanded budgets fail closed',async () => {
  const source = xlsxFixture('<sheetData/>'), raw = unzipSync(source);
  for (const name of ['../outside','/absolute','a\\b','xl/../alias','XL/WORKBOOK.XML']) await assert.rejects(extractWorkbook(zipSync({...raw,[name]:strToU8('x')}),'xlsx'),code('INVALID_WORKBOOK'));
  const corrupt = source.slice(), view = new DataView(corrupt.buffer); let central = 0; for (; central < corrupt.length - 46; central++) if (view.getUint32(central,true) === 0x02014b50) break; view.setUint32(central + 24,WORKBOOK_LIMITS.part + 1,true); await assert.rejects(extractWorkbook(corrupt,'xlsx'),code('WORKBOOK_LIMIT'));
  const stored = zipSync(raw,{level:0}), changed = stored.slice(), v = new DataView(changed.buffer); const offset = 30 + v.getUint16(26,true) + v.getUint16(28,true); changed[offset] ^= 1; await assert.rejects(extractWorkbook(changed,'xlsx'),code('INVALID_WORKBOOK'));
  const encrypted = source.slice(), encryptedView = new DataView(encrypted.buffer); encryptedView.setUint16(central + 8,encryptedView.getUint16(central + 8,true) | 1,true); await assert.rejects(extractWorkbook(encrypted,'xlsx'),code('ENCRYPTED_WORKBOOK'));
});

test('XML declarations/entities/depth, malformed addresses, relationships and duplicate cell identities reject',async () => {
  await assert.rejects(extractWorkbook(xlsxFixture('<!DOCTYPE worksheet [<!ENTITY x "boom">]><worksheet><sheetData/></worksheet>'),'xlsx'),code('XML_DTD'));
  await assert.rejects(extractWorkbook(xlsxFixture('<sheetData>' + '<x>'.repeat(101) + '</x>'.repeat(101) + '</sheetData>'),'xlsx'),code('XML_DEPTH'));
  for (const sheet of ['<sheetData><row r="1"><c r="A0"/></row></sheetData>','<sheetData><row r="1"><c r="A1"/><c r="A1"/></row></sheetData>','<sheetData><row r="1"><c r="XFE1"/></row></sheetData>','<sheetData><row r="1"><c r="A1"><v>1</v><v>2</v></c></row></sheetData>']) await assert.rejects(extractWorkbook(xlsxFixture(sheet),'xlsx'));
  await assert.rejects(extractWorkbook(xlsxFixture('<sheetData/>',{relationships:'<Relationships><Relationship Id="sheet1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="../../../outside"/></Relationships>'}),'xlsx'),code('INVALID_WORKBOOK'));
});

test('external links never open; missing caches, scripts, encrypted ODS and binary XLS are explicit',async () => {
  const external = '<Relationships><Relationship Id="remote" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink" TargetMode="External" Target="file:///private/not-opened"/></Relationships>';
  const observed = await extractWorkbook(xlsxFixture('<sheetData/>',{extra:{'xl/worksheets/_rels/sheet1.xml.rels':external}}),'xlsx'); assert.ok(observed.coverage_gaps.some(gap => gap.feature === 'external_relationships'));
  await assert.rejects(extractWorkbook(xlsxFixture('<sheetData/>',{extra:{'xl/vbaProject.bin':new Uint8Array([1])}}),'xlsx'),code('UNSUPPORTED_WORKBOOK'));
  await assert.rejects(extractWorkbook(odsFixture('<table:table-row/>',{manifest:'<manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0"><manifest:encryption-data/></manifest>'}),'ods'),code('ENCRYPTED_WORKBOOK'));
  await assert.rejects(extractWorkbook(odsFixture('<table:table-row/>',{extra:{'Scripts/python/x.py':'print(1)'}}),'ods'),code('UNSUPPORTED_WORKBOOK'));
  await assert.rejects(extractWorkbook(new Uint8Array([0xd0,0xcf,0x11,0xe0,0xa1,0xb1,0x1a,0xe1]),'xlsx'),code('UNSUPPORTED_WORKBOOK'));
});

test('workbook import cooperatively cancels before parsing and during dense CSV without publishing partial observations',async () => {
  const before = new AbortController(); before.abort(); await assert.rejects(extractWorkbook(strToU8('a'),'csv',{signal:before.signal}),code('CANCELLED'));
  const during = new AbortController(), pending = extractWorkbook(strToU8('a,b,c\n'.repeat(30000)),'csv',{signal:during.signal}); setImmediate(() => during.abort()); await assert.rejects(pending,code('CANCELLED'));
});

test('advanced XLSX and ODS features produce individually named coverage gaps',async () => {
  const xlsx = await extractWorkbook(xlsxFixture('<sheetData><row r="1"><c r="A1"><f t="array" ref="A1">1</f><v>1</v></c></row></sheetData><conditionalFormatting sqref="A1"/><dataValidations/><tableParts/>',{extra:{'xl/charts/chart1.xml':'<chart/>','xl/pivotTables/pivot1.xml':'<pivot/>','xl/connections.xml':'<connections/>','xl/externalLinks/link1.xml':'<externalLink/>','xl/tables/table1.xml':'<table/>'}}),'xlsx');
  const xlsxGaps = new Set([...xlsx.coverage_gaps,...xlsx.sheets[0].coverage_gaps].map(gap => gap.feature)); for (const name of ['charts','pivots','connections','external_links','structured_tables','conditional_formatting','data_validation','shared_array_formulas']) assert.ok(xlsxGaps.has(name),name);
  const ods = await extractWorkbook(odsFixture('<table:table table:name="Sheet1"><table:named-expressions/><table:data-pilot-tables/><table:database-ranges/><table:content-validations/><table:table-row><table:table-cell table:content-validation-name="v1" office:value-type="float" office:value="1"/></table:table-row></table:table>',{manifest:'<manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0"><manifest:file-entry manifest:media-type="application/vnd.oasis.opendocument.chart" manifest:full-path="Object1/"/></manifest>'}),'ods');
  const odsGaps = new Set([...ods.coverage_gaps,...ods.sheets[0].coverage_gaps].map(gap => gap.feature)); for (const name of ['charts','pivots','defined_names','structured_tables','data_validation']) assert.ok(odsGaps.has(name),name);
});

test('repeated long semantic styles are interned once without imposing an artificial cell limit',async () => {
  const bytes = odsFixture('<table:table-row table:number-rows-repeated="20000"><table:table-cell table:style-name="ce1" office:value-type="float" office:value="1"/></table:table-row>',{automatic:`<style:style style:name="ce1" style:family="table-cell"><style:text-properties fo:font-family="${'x'.repeat(4096)}"/></style:style>`});
  const observed = await extractWorkbook(bytes,'ods'); assert.equal(observed.sheets[0].cells.length,20000); assert.equal(Object.keys(observed.style_definitions ?? {}).length,1); assert.equal(style(observed,'A1')['text-properties.font-family'].length,4096); assert.equal(cell(observed,'A1').style_ref,cell(observed,'A20000').style_ref); assert.deepEqual(cell(observed,'A20000').style,{});
});

test('calculation flags are known bounded metadata and never arbitrary unpaged XML attributes',async () => {
  const workbook = '<workbook xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Sheet1" sheetId="1" r:id="sheet1"/></sheets><calcPr calcMode="manual" privatePayload="' + 'x'.repeat(4096) + '"/></workbook>';
  const observed = await extractWorkbook(xlsxFixture('<sheetData/>',{workbook}),'xlsx'); assert.deepEqual(observed.calc_flags,{calcMode:'manual'}); assert.ok(observed.coverage_gaps.some(gap => gap.feature === 'calculation_metadata'));
  await assert.rejects(extractWorkbook(xlsxFixture('<sheetData/>',{workbook:workbook.replace('calcMode="manual"','calcMode="' + 'x'.repeat(129) + '"')}),'xlsx'),code('WORKBOOK_LIMIT'));
});

test('shared and array formula followers remain unresolved instead of certifying formula removal or direct inputs',async () => {
  const shared = await extractWorkbook(xlsxFixture('<sheetData><row r="1"><c r="A1"><f t="shared" si="0" ref="A1:B1">C1+1</f><v>2</v></c><c r="B1"><f t="shared" si="0"/><v>3</v></c><c r="C1"><v>1</v></c></row></sheetData>'),'xlsx');
  const expanded = await extractWorkbook(xlsxFixture('<sheetData><row r="1"><c r="A1"><f>C1+1</f><v>2</v></c><c r="B1"><f>D1+1</f><v>3</v></c><c r="C1"><v>1</v></c></row></sheetData>'),'xlsx');
  assert.equal(cell(shared,'B1').formula,''); assert.equal(cell(shared,'B1').formula_interpretation,'unresolved'); assert.equal(cell(expanded,'B1').formula_interpretation,'explicit'); assert.equal(cell(shared,'B1').value,cell(expanded,'B1').value); assert.equal(cell(shared,'B1').cached_result,'present'); assert.equal(cell(shared,'C1').formula_interpretation,'not_formula');
  const array = await extractWorkbook(xlsxFixture('<sheetData><row r="1"><c r="A1"><f t="array" ref="A1:B2">ROW(A1:B2)</f><v>1</v></c><c r="B1"><v>1</v></c><c r="C1"><v>99</v></c></row><row r="2"><c r="A2"><v>2</v></c><c r="B2"/></row></sheetData>'),'xlsx');
  assert.equal(cell(array,'B1').formula,null); assert.equal(cell(array,'B1').formula_interpretation,'unresolved'); assert.equal(cell(array,'B1').cached_result,'present'); assert.equal(cell(array,'B1').cache_freshness,'unknown'); assert.equal(cell(array,'B2').cached_result,'missing'); assert.equal(cell(array,'C1').formula_interpretation,'not_formula');
});

test('ODS matrix spans classify ordinary and covered saved followers without expanding the rectangular range',async () => {
  const observed = await extractWorkbook(odsFixture('<table:table-row><table:table-cell table:formula="of:=TRANSPOSE([.A5:.B6])" table:number-matrix-columns-spanned="2" table:number-matrix-rows-spanned="2" office:value-type="float" office:value="1"/><table:table-cell office:value-type="float" office:value="2"/><table:table-cell office:value-type="float" office:value="99"/></table:table-row><table:table-row><table:table-cell office:value-type="float" office:value="3"/><table:covered-table-cell/></table:table-row>'),'ods');
  assert.equal(cell(observed,'A1').formula_interpretation,'unresolved'); assert.equal(cell(observed,'B1').formula,null); assert.equal(cell(observed,'B1').formula_interpretation,'unresolved'); assert.equal(cell(observed,'B1').value,'2'); assert.equal(cell(observed,'B1').cached_result,'present'); assert.equal(cell(observed,'B2').cached_result,'missing'); assert.equal(cell(observed,'B2').formula_interpretation,'unresolved'); assert.equal(cell(observed,'C1').formula_interpretation,'not_formula');
  const huge = await extractWorkbook(xlsxFixture('<sheetData><row r="1"><c r="A1"><f t="array" ref="A1:XFD1048576">1</f><v>1</v></c></row></sheetData>'),'xlsx'); assert.equal(huge.sheets[0].cells.length,1);
});

test('nested ODS row/column groups preserve inherited hidden state and source visibility toggles',async () => {
  const row = (number: number, visibility = '') => `<table:table-row${visibility ? ` table:visibility="${visibility}"` : ''}>${[1,2,3,4].map(column => `<table:table-cell office:value-type="float" office:value="${number * 10 + column}"/>`).join('')}</table:table-row>`;
  const source = (hidden: boolean) => odsFixture(`<table:table table:name="Groups"><table:table-column-group table:display="${hidden ? 'false' : 'true'}"><table:table-column/><table:table-column-group table:display="true"><table:table-column/></table:table-column-group><table:table-column-group table:display="false"><table:table-column/></table:table-column-group></table:table-column-group><table:table-column/><table:table-row-group table:display="${hidden ? 'false' : 'true'}">${row(1)}<table:table-row-group table:display="true">${row(2)}</table:table-row-group><table:table-row-group table:display="false">${row(3)}</table:table-row-group>${row(4,'filter')}</table:table-row-group>${row(5)}</table:table>`);
  const hidden = await extractWorkbook(source(true),'ods'), visible = await extractWorkbook(source(false),'ods');
  for (const address of ['A1','B1','C1','A2','B2','C2','A3']) { assert.equal(cell(hidden,address).hidden_row,true,address); assert.equal(cell(hidden,address).hidden_column,true,address); }
  assert.equal(cell(hidden,'D1').hidden_column,false); assert.equal(cell(hidden,'A5').hidden_row,false);
  assert.equal(cell(visible,'A1').hidden_row,false); assert.equal(cell(visible,'B2').hidden_row,false); assert.equal(cell(visible,'B2').hidden_column,false); assert.equal(cell(visible,'C2').hidden_column,true); assert.equal(cell(visible,'A3').hidden_row,true); assert.equal(cell(visible,'A4').hidden_row,true);
  assert.equal(cell(hidden,'B2').value,cell(visible,'B2').value); assert.deepEqual(hidden.sheets[0].row_metadata.map(item => [item.start,item.end,item.hidden]),[[1,1,true],[2,2,true],[3,3,true],[4,4,true]]); assert.deepEqual(visible.sheets[0].row_metadata.map(item => [item.start,item.end,item.hidden]),[[3,3,true],[4,4,true]]);
  assert.deepEqual(visible.sheets[0].column_metadata.map(item => [item.start,item.end,item.hidden]),[[3,3,true]]);
});

test('hidden ODS groups retain million-row sparse metadata without expanding repeated blanks',async () => {
  const bytes = odsFixture('<table:table table:name="SparseGroups"><table:table-column-group table:display="false"><table:table-column-group table:display="true"><table:table-column table:number-columns-repeated="16384"/></table:table-column-group></table:table-column-group><table:table-row-group table:display="false"><table:table-row-group table:display="true"><table:table-row table:number-rows-repeated="1048576"><table:table-cell table:number-columns-repeated="16384"/></table:table-row></table:table-row-group></table:table-row-group></table:table>');
  const observed = await extractWorkbook(bytes,'ods'), sheet = observed.sheets[0]; assert.equal(sheet.cells.length,0); assert.equal(sheet.row_count,1048576); assert.equal(sheet.column_count,16384); assert.deepEqual(sheet.row_metadata,[{start:1,end:1048576,hidden:true,size:null}]); assert.deepEqual(sheet.column_metadata,[{start:1,end:16384,hidden:true,size:null}]);
  await assert.rejects(extractWorkbook(odsFixture('<table:table-row-group table:display="false"><table:table-row table:number-rows-repeated="1048577"/></table:table-row-group>'),'ods'),code('WORKBOOK_LIMIT'));
});

test('ordinary Excel default formatting is interned and remains semantically compared',async () => {
  const source = defaultStyledXlsxFixture(20000), original = source.slice(), observed = await extractWorkbook(source,'xlsx'); assert.deepEqual(source,original); assert.equal(observed.sheets[0].cells.length,20000); assert.equal(Object.keys(observed.style_definitions ?? {}).length,1); assert.equal(style(observed,'A1')['font.name.val'],'Calibri'); assert.equal(cell(observed,'A1').style_ref,cell(observed,'CV200').style_ref); assert.deepEqual(cell(observed,'A1').style,{});
  const parts = unzipSync(source); parts['xl/styles.xml'] = strToU8(new TextDecoder().decode(parts['xl/styles.xml']).replace('Calibri','Aptos')); const changed = await extractWorkbook(zipSync(parts),'xlsx'); assert.notEqual(cell(observed,'A1').style_ref,cell(changed,'A1').style_ref); assert.equal(style(changed,'A1')['font.name.val'],'Aptos');
});

test('ODS document-default column/row styles leave trailing million-row empty ranges sparse',async () => {
  const styles = '<style:default-style style:family="table-cell"><style:text-properties fo:font-size="10pt"/></style:default-style><style:style style:name="Default" style:family="table-cell"/>';
  const observed = await extractWorkbook(odsFixture('<table:table-column table:number-columns-repeated="1024" table:default-cell-style-name="Default"/><table:table-row><table:table-cell office:value-type="float" office:value="7"/></table:table-row><table:table-row table:number-rows-repeated="1048575" table:default-cell-style-name="Default"><table:table-cell table:number-columns-repeated="1024"/></table:table-row>',{styles}),'ods'); assert.equal(observed.sheets[0].cells.length,1); assert.equal(observed.sheets[0].row_count,1); assert.equal(style(observed,'A1')['text-properties.font-size'],'10pt');
  const nondefault = await extractWorkbook(odsFixture('<table:table-column table:default-cell-style-name="Color"/><table:table-row><table:table-cell/></table:table-row>',{styles:styles + '<style:style style:name="Color" style:family="table-cell"><style:table-cell-properties fo:background-color="#ffff00"/></style:style>'}),'ods'); assert.equal(nondefault.sheets[0].cells.length,1); assert.equal(style(nondefault,'A1')['table-cell-properties.background-color'],'#ffff00');
});

test('ODS automatic style names are scoped to their part and common parent styles retain precedence',async () => {
  const common = '<style:style style:name="Base" style:family="table-cell"><style:text-properties fo:font-weight="bold"/></style:style>';
  const stylesAutomatic = '<style:style style:name="ce1" style:family="table-cell"><style:text-properties fo:color="#ff0000"/></style:style><style:style style:name="Base" style:family="table-cell"><style:text-properties fo:font-style="italic"/></style:style>';
  const automatic = '<style:style style:name="ce1" style:family="table-cell" style:parent-style-name="Base"><style:text-properties fo:color="#008800"/></style:style><style:style style:name="Base" style:family="table-cell"><style:text-properties fo:font-style="italic"/></style:style>';
  const observed = await extractWorkbook(odsFixture('<table:table-row><table:table-cell table:style-name="ce1" office:value-type="float" office:value="1"/></table:table-row>',{styles:common,stylesAutomatic,automatic}),'ods'); assert.equal(style(observed,'A1')['text-properties.color'],'#008800'); assert.equal(style(observed,'A1')['text-properties.font-weight'],'bold'); assert.equal(style(observed,'A1')['text-properties.font-style'],undefined);
  await assert.rejects(extractWorkbook(odsFixture('<table:table-row><table:table-cell table:style-name="ce1" office:value-type="float" office:value="1"/></table:table-row>',{stylesAutomatic}),'ods'),code('INVALID_WORKBOOK'));
});

test('valid namespace aliases retain ODS values/formulas and XLSX relationship IDs; wrong URIs fail explicitly',async () => {
  const source = odsFixture('<table:table-row><table:table-cell office:value-type="float" office:value="42" table:formula="of:=6*7"/></table:table-row>'), parts = unzipSync(source);
  const rebind = (value: string,from: string,to: string) => value.replaceAll(`xmlns:${from}=`,`xmlns:${to}=`).replace(new RegExp(`(<\\/?|\\s)${from}:`,'g'),`$1${to}:`);
  let content = new TextDecoder().decode(parts['content.xml']); for (const [from,to] of [['office','o'],['table','t'],['style','s']]) content = rebind(content,from,to); parts['content.xml'] = strToU8(content); const aliased = await extractWorkbook(zipSync(parts),'ods'); assert.equal(cell(aliased,'A1').value,'42'); assert.equal(cell(aliased,'A1').formula,'of:=6*7');
  parts['content.xml'] = strToU8(content.replace('xmlns:o="urn:oasis:names:tc:opendocument:xmlns:office:1.0"','xmlns:o="urn:wrong:office"')); await assert.rejects(extractWorkbook(zipSync(parts),'ods'),code('UNSUPPORTED_NAMESPACE'));
  const attributeOnly = unzipSync(source); attributeOnly['content.xml'] = strToU8(new TextDecoder().decode(attributeOnly['content.xml']).replace('office:value-type="float"','bad:value-type="float" xmlns:bad="urn:wrong:office"')); await assert.rejects(extractWorkbook(zipSync(attributeOnly),'ods'),code('UNSUPPORTED_NAMESPACE'));
  const book = unzipSync(xlsxFixture('<sheetData/>')); book['xl/workbook.xml'] = strToU8(rebind(new TextDecoder().decode(book['xl/workbook.xml']),'r','rel')); assert.equal((await extractWorkbook(zipSync(book),'xlsx')).sheets.length,1);
});

test('ODS repeated blanks crossing default and nondefault columns materialize only effective style runs',async () => {
  const styles = '<style:style style:name="Default" style:family="table-cell"/><style:style style:name="Color" style:family="table-cell"><style:table-cell-properties fo:background-color="#ffff00"/></style:style>';
  const observed = await extractWorkbook(odsFixture('<table:table-column table:default-cell-style-name="Color"/><table:table-column table:number-columns-repeated="16383" table:default-cell-style-name="Default"/><table:table-row table:number-rows-repeated="100"><table:table-cell table:number-columns-repeated="16384"/></table:table-row>',{styles}),'ods'); assert.equal(observed.sheets[0].cells.length,100); assert.equal(observed.sheets[0].column_count,1); assert.equal(style(observed,'A100')['table-cell-properties.background-color'],'#ffff00');
  const override = await extractWorkbook(odsFixture('<table:table-column table:default-cell-style-name="Color"/><table:table-row table:number-rows-repeated="1048576"><table:table-cell table:style-name="Default"/></table:table-row>',{styles}),'ods'); assert.equal(override.sheets[0].cells.length,0);
});
