import { inflateRawSync } from 'node:zlib';
import { setImmediate as yieldTurn } from 'node:timers/promises';
import { posix } from 'node:path';
import { XMLParser } from 'fast-xml-parser';
import { DocverError } from '../schema/index.js';
import { readXml, decodeXmlReferences } from '../xml/index.js';
import { cellAddress, workbookID, type WorkbookBlankStyleRangeData, type WorkbookCellData, type WorkbookFormatData, type WorkbookGapData, type WorkbookObservationData, type WorkbookSheetData } from './types.js';

// These are rejection limits, never truncation targets. No workbook code is evaluated.
export const WORKBOOK_LIMITS = Object.freeze({ input: 64 * 1024 * 1024, expanded: 128 * 1024 * 1024, part: 32 * 1024 * 1024, entries: 4096, sheets: 100, cells: 500_000, rows: 1_048_576, columns: 16_384, cellText: 1024 * 1024, xmlNodes: 2_000_000, metadata: 100_000, styleEntries: 2_000_000, text: 64 * 1024 * 1024 });
type Element = { name: string; namespace: string; attrs: Record<string,string>; children: Element[]; text: string; content: (string | Element)[] };
type State = { signal?: AbortSignal; cells: number; nodes: number; text: number; ticks: number; styleEntries: number; blankRanges: number; styleDefinitions: Record<string,Record<string,string>>; styleRefs: WeakMap<Record<string,string>,string>; stylesByCanonical: Map<string,string>; numberFormats: Set<string>; gaps: WorkbookGapData[] };
function fail(code: string, message: string): never { throw new DocverError(code, message); }
const array = <T>(value: T | T[] | undefined): T[] => value === undefined ? [] : Array.isArray(value) ? value : [value];
const children = (node: Element | undefined, name: string) => node?.children.filter(child => child.name === name) ?? [];
const first = (node: Element | undefined, name: string) => children(node, name)[0];
const attr = (node: Element | undefined, name: string) => node?.attrs[name];
const truth = (value: string | undefined) => value === '1' || value === 'true';
function abort(state: State) { if (state.signal?.aborted) fail('CANCELLED', 'Workbook import cancelled'); }
async function checkpoint(state: State, force = false) { abort(state); if (force || ++state.ticks % 1024 === 0) { await yieldTurn(); abort(state); } }
function textBudget(state: State, value: string) { if (value.length > WORKBOOK_LIMITS.cellText) fail('WORKBOOK_LIMIT', 'A workbook text field exceeds 1 MiB'); state.text += value.length; if (state.text > WORKBOOK_LIMITS.text) fail('WORKBOOK_LIMIT', 'Workbook text exceeds limit'); return value; }
function integer(value: string | undefined, fallback: number, max: number, name: string, min = 1) { if (value === undefined) return fallback; if (!/^\d+$/.test(value)) fail('INVALID_WORKBOOK', `Invalid ${name}`); const result = Number(value); if (!Number.isSafeInteger(result) || result < min || result > max) fail('WORKBOOK_LIMIT', `${name} exceeds supported bounds`); return result; }
function gap(gaps: WorkbookGapData[], feature: string, reason: string, sheet_id?: string, address?: string) { if (!gaps.some(item => item.feature === feature && item.sheet_id === sheet_id && item.address === address && item.reason === reason)) gaps.push({ feature, reason, ...(sheet_id ? { sheet_id } : {}), ...(address ? { address } : {}) }); }
function parseAddress(source: string): [number,number] { const match = /^\$?([A-Z]{1,3})\$?([1-9]\d*)$/.exec(source); if (!match) fail('INVALID_WORKBOOK', 'Invalid cell address'); let column = 0; for (const char of match[1]) column = column * 26 + char.charCodeAt(0) - 64; const row = Number(match[2]); if (column > WORKBOOK_LIMITS.columns || row > WORKBOOK_LIMITS.rows) fail('WORKBOOK_LIMIT', 'Cell address exceeds worksheet bounds'); return [row,column]; }
function parseRange(source: string): [number,number,number,number] { const pieces = source.split(':'); if (pieces.length > 2) fail('INVALID_WORKBOOK', 'Invalid cell range'); const [r,c] = parseAddress(pieces[0]), [rr,cc] = parseAddress(pieces[1] ?? pieces[0]); if (rr < r || cc < c) fail('INVALID_WORKBOOK', 'Reversed cell range'); return [r,c,rr,cc]; }
function newSheet(format: WorkbookFormatData, name: string, source_ref: string, index: number): WorkbookSheetData { if (!name || name.length > 255 || source_ref.length > 480) fail('INVALID_WORKBOOK', 'Invalid sheet name'); return { sheet_id: workbookID('sheet', { format, source_ref, name }), name, source_ref, index, hidden: false, row_count: 0, column_count: 0, cells: [], merges: [], row_metadata: [], column_metadata: [], cell_extraction_complete: true, coverage_gaps: [] }; }
function metadataBudget(sheet: WorkbookSheetData) { if (sheet.merges.length > WORKBOOK_LIMITS.metadata || sheet.row_metadata.length > WORKBOOK_LIMITS.metadata || sheet.column_metadata.length > WORKBOOK_LIMITS.metadata) fail('WORKBOOK_LIMIT','Worksheet metadata exceeds 100000 entries'); }
function addAxisMetadata(target: WorkbookSheetData['row_metadata'],item: WorkbookSheetData['row_metadata'][number]) {
  const previous = target.at(-1); if (previous && previous.end + 1 === item.start && previous.hidden === item.hidden && previous.size === item.size) { previous.end = item.end; return; }
  if (target.length >= WORKBOOK_LIMITS.metadata) fail('WORKBOOK_LIMIT','Worksheet axis metadata exceeds limit'); target.push(item);
}
function addCell(state: State, sheet: WorkbookSheetData, cell: WorkbookCellData) {
  if (cell.formula !== null) cell.cache_freshness = 'unknown';
  if (++state.cells > WORKBOOK_LIMITS.cells) fail('WORKBOOK_LIMIT', 'Workbook exceeds 500000 materialized cells');
  if (cell.value !== null) textBudget(state, cell.value); if (cell.formula !== null) textBudget(state, cell.formula);
  internStyle(state,cell);
  sheet.cells.push(cell); sheet.row_count = Math.max(sheet.row_count, cell.row); sheet.column_count = Math.max(sheet.column_count, cell.column);
}
function internStyle(state: State, cell: Pick<WorkbookCellData,'style'|'style_ref'|'number_format'>) {
  // Retain the complete default style, but store and charge each distinct
  // semantic definition once instead of copying it into every source cell.
  let styleRef = state.styleRefs.get(cell.style);
  if (!styleRef) {
    const entries = Object.entries(cell.style).sort(([a],[b]) => a < b ? -1 : a > b ? 1 : 0);
    if (entries.length) {
      const canonical = JSON.stringify(entries); styleRef = state.stylesByCanonical.get(canonical);
      if (!styleRef) {
        if (state.stylesByCanonical.size >= WORKBOOK_LIMITS.metadata) fail('WORKBOOK_LIMIT','Distinct workbook styles exceed metadata limit');
        state.styleEntries += entries.length; if (state.styleEntries > WORKBOOK_LIMITS.styleEntries) fail('WORKBOOK_LIMIT','Distinct semantic style properties exceed limit');
        for (const [key,value] of entries) state.text += key.length + value.length;
        const definition = Object.fromEntries(entries); styleRef = workbookID('wstyle',definition); state.styleDefinitions[styleRef] = definition; state.stylesByCanonical.set(canonical,styleRef);
      }
      state.styleRefs.set(cell.style,styleRef);
    }
  }
  if (styleRef) { cell.style_ref = styleRef; cell.style = {}; }
  if (cell.number_format !== null && !state.numberFormats.has(cell.number_format)) {
    if (state.numberFormats.size >= WORKBOOK_LIMITS.metadata) fail('WORKBOOK_LIMIT','Distinct number formats exceed metadata limit');
    state.numberFormats.add(cell.number_format); state.text += cell.number_format.length;
  }
  if (state.text > WORKBOOK_LIMITS.text) fail('WORKBOOK_LIMIT','Workbook values and distinct styles exceed text limit');
}
function makeCell(sheet: WorkbookSheetData, row: number, column: number): WorkbookCellData { const address = cellAddress(row,column); return { address, row, column, value_type: 'blank', value: null, formula: null, number_format: null, style: {}, cached_result: 'not_applicable', cache_freshness: 'not_applicable', formula_dialect: null, formula_interpretation: 'not_formula', hidden_row: false, hidden_column: false, source_ref: `${sheet.source_ref}!${address}` }; }

type FormulaRange = [number,number,number,number];
function addFormulaRange(ranges: FormulaRange[], range: FormulaRange) { if (ranges.length >= WORKBOOK_LIMITS.metadata) fail('WORKBOOK_LIMIT','Formula ranges exceed metadata budget'); ranges.push(range); }
async function applyFormulaInterpretation(sheet: WorkbookSheetData, ranges: FormulaRange[], wholeSheet: boolean, state: State, saved?: WeakSet<WorkbookCellData>) {
  if (!ranges.length && !wholeSheet) return;
  // Sweep sparse source cells, never expand a potentially million-row rectangle.
  const events = ranges.flatMap(([row,column,endRow,endColumn]) => [{row,column,endColumn,delta:1},{row:endRow + 1,column,endColumn,delta:-1}]).sort((a,b) => a.row - b.row);
  const tree = new Int32Array(WORKBOOK_LIMITS.columns + 2);
  const update = (column: number,delta: number) => { for (let cc = column; cc < tree.length; cc += cc & -cc) tree[cc] += delta; };
  const contains = (column: number) => { let count = 0; for (let cc = column; cc > 0; cc -= cc & -cc) count += tree[cc]; return count > 0; };
  let next = 0;
  for (const cell of sheet.cells) {
    await checkpoint(state);
    while (next < events.length && events[next].row <= cell.row) { const event = events[next++]; update(event.column,event.delta); update(event.endColumn + 1,-event.delta); }
    if (wholeSheet || contains(cell.column)) {
      cell.formula_interpretation = 'unresolved'; cell.cached_result = saved?.has(cell) || cell.value !== null ? 'present' : 'missing'; cell.cache_freshness = 'unknown';
    }
  }
  let rangeChecks=0,unresolvedBlank=false;
  for(const blank of sheet.blank_style_ranges??[]){
    await checkpoint(state);let intersects=wholeSheet;
    if(!intersects)for(const [row,column,endRow,endColumn]of ranges){if(++rangeChecks>2_000_000)fail('WORKBOOK_LIMIT','Formula and blank formatting intersections exceed bounded comparison budget');if(row<=blank.row_end&&endRow>=blank.row_start&&column<=blank.column_end&&endColumn>=blank.column_start){intersects=true;break;}}
    if(intersects){blank.formula_interpretation='unresolved';unresolvedBlank=true;}
  }
  if(unresolvedBlank)gap(sheet.coverage_gaps,'blank_range_formula_interpretation','An explicit blank formatting rectangle intersects an unresolved formula-dependent region. The whole retained rectangle is conservatively unresolved; its absence of a saved value is not certified direct input.',sheet.sheet_id);
  gap(sheet.coverage_gaps,'formula_interpretation',wholeSheet ? 'Formula-dependent ranges cannot be safely resolved; every source cell on this sheet is conservatively unresolved, with saved values only.' : 'Shared/array/matrix source ranges are unresolved; saved follower values are not certified direct inputs or expanded formulas.',sheet.sheet_id);
}

// ZIPs are validated without allocating their claimed expanded content. ZIP64,
// encryption, aliases, traversal, overlapping members and special files fail closed.
type ZipEntry = { name: string; compression: number; compressed: number; size: number; crc: number; offset: number; start: number; end: number };
function zipDirectory(bytes: Uint8Array): ZipEntry[] {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength), u16 = (o: number) => view.getUint16(o,true), u32 = (o: number) => view.getUint32(o,true);
  if (bytes.length < 22) fail('INVALID_WORKBOOK', 'Workbook is not a ZIP package');
  let eocd = bytes.length - 22;
  while (eocd >= Math.max(0,bytes.length - 65_557) && (u32(eocd) !== 0x06054b50 || eocd + 22 + u16(eocd + 20) !== bytes.length)) eocd--;
  if (eocd < Math.max(0,bytes.length - 65_557)) fail('INVALID_WORKBOOK', 'Invalid ZIP directory');
  if (u16(eocd + 4) || u16(eocd + 6) || u16(eocd + 8) !== u16(eocd + 10)) fail('UNSUPPORTED_WORKBOOK', 'Multi-disk ZIP packages are unsupported');
  const count = u16(eocd + 10), length = u32(eocd + 12), offset = u32(eocd + 16);
  if (count === 0xffff || length === 0xffffffff || offset === 0xffffffff) fail('UNSUPPORTED_WORKBOOK', 'ZIP64 workbooks are unsupported');
  if (count > WORKBOOK_LIMITS.entries || offset + length !== eocd) fail('WORKBOOK_LIMIT', 'Workbook ZIP directory exceeds limits');
  let cursor = offset, expanded = 0; const entries: ZipEntry[] = [], names = new Set<string>();
  const decoder = new TextDecoder('utf-8', { fatal: true });
  for (let n = 0; n < count; n++) {
    if (cursor + 46 > eocd || u32(cursor) !== 0x02014b50) fail('INVALID_WORKBOOK', 'Malformed ZIP central directory');
    const flags = u16(cursor + 8), compression = u16(cursor + 10), crc = u32(cursor + 16), compressed = u32(cursor + 20), size = u32(cursor + 24), nameLength = u16(cursor + 28), extra = u16(cursor + 30), comment = u16(cursor + 32), disk = u16(cursor + 34), mode = u32(cursor + 38) >>> 16, memberOffset = u32(cursor + 42);
    const next = cursor + 46 + nameLength + extra + comment;
    if (next > eocd || !nameLength || disk || memberOffset === 0xffffffff || compressed === 0xffffffff || size === 0xffffffff) fail('INVALID_WORKBOOK', 'Unsupported ZIP member');
    if (flags & (1 | 64 | 8192)) fail('ENCRYPTED_WORKBOOK', 'Encrypted workbook packages are unsupported');
    if (flags & ~(8 | 2048 | 2 | 4)) fail('UNSUPPORTED_WORKBOOK', 'Unsupported ZIP member flags');
    if (compression !== 0 && compression !== 8) fail('UNSUPPORTED_WORKBOOK', 'Unsupported ZIP compression');
    if ((mode & 0xf000) && (mode & 0xf000) !== 0x8000 && (mode & 0xf000) !== 0x4000) fail('INVALID_WORKBOOK', 'Special ZIP members are unsupported');
    let name: string; try { name = decoder.decode(bytes.subarray(cursor + 46,cursor + 46 + nameLength)); } catch { fail('INVALID_WORKBOOK', 'ZIP names must be UTF-8'); }
    if (name.includes('\\') || name.startsWith('/') || /^[A-Za-z]:/.test(name) || /[\u0000-\u001f\u007f]/.test(name) || name.split('/').some(piece => piece === '.' || piece === '..') || name.includes('//') || name.length > 1024) fail('INVALID_WORKBOOK', 'Unsafe ZIP member path');
    const key = name.normalize('NFC').toLowerCase(); if (names.has(key)) fail('INVALID_WORKBOOK', 'Duplicate or aliased ZIP member'); names.add(key);
    if (size > WORKBOOK_LIMITS.part || (expanded += size) > WORKBOOK_LIMITS.expanded) fail('WORKBOOK_LIMIT', 'Expanded workbook exceeds ZIP limits');
    if (memberOffset + 30 > offset || u32(memberOffset) !== 0x04034b50) fail('INVALID_WORKBOOK', 'Invalid ZIP local header');
    const localFlags = u16(memberOffset + 6), localCompression = u16(memberOffset + 8), localNameLength = u16(memberOffset + 26), localExtra = u16(memberOffset + 28), start = memberOffset + 30 + localNameLength + localExtra, end = start + compressed;
    if (localFlags !== flags || localCompression !== compression || localNameLength !== nameLength || start > offset || end > offset || !bytes.subarray(memberOffset + 30,memberOffset + 30 + nameLength).every((byte,i) => byte === bytes[cursor + 46 + i])) fail('INVALID_WORKBOOK', 'ZIP local header disagrees with directory');
    if (!(flags & 8) && (u32(memberOffset + 14) !== crc || u32(memberOffset + 18) !== compressed || u32(memberOffset + 22) !== size)) fail('INVALID_WORKBOOK', 'ZIP local sizes disagree with directory');
    if (compression === 0 && compressed !== size) fail('INVALID_WORKBOOK', 'Invalid stored ZIP size');
    entries.push({ name, compression, compressed, size, crc, offset: memberOffset, start, end }); cursor = next;
  }
  if (cursor !== eocd) fail('INVALID_WORKBOOK', 'Unexpected ZIP directory bytes');
  const ordered = [...entries].sort((a,b) => a.offset - b.offset); for (let n = 1; n < ordered.length; n++) if (ordered[n].offset < ordered[n - 1].end) fail('INVALID_WORKBOOK', 'Overlapping ZIP members');
  return entries;
}
const crcTable = new Uint32Array(256); for (let n = 0; n < 256; n++) { let value = n; for (let bit = 0; bit < 8; bit++) value = value & 1 ? 0xedb88320 ^ value >>> 1 : value >>> 1; crcTable[n] = value; }
function crc32(bytes: Uint8Array) { let crc = 0xffffffff; for (const byte of bytes) crc = crcTable[(crc ^ byte) & 255] ^ crc >>> 8; return (crc ^ 0xffffffff) >>> 0; }
async function readPackage(bytes: Uint8Array, state: State): Promise<Map<string,Uint8Array>> {
  const entries = zipDirectory(bytes), result = new Map<string,Uint8Array>();
  for (const entry of entries) {
    await checkpoint(state,true);
    let content: Uint8Array;
    try { content = entry.compression === 0 ? bytes.slice(entry.start,entry.end) : inflateRawSync(bytes.subarray(entry.start,entry.end), { maxOutputLength: Math.max(1,entry.size + 1) }); }
    catch { fail('INVALID_WORKBOOK', 'Corrupt or oversized compressed ZIP member'); }
    if (content.length !== entry.size || crc32(content) !== entry.crc) fail('INVALID_WORKBOOK', 'ZIP member size or CRC mismatch');
    result.set(entry.name,content);
  }
  return result;
}
const ODF_NS = 'urn:oasis:names:tc:opendocument:xmlns:';
const ODS_NUMBER_STYLES = new Set(['number-style','currency-style','percentage-style','date-style','time-style','boolean-style','text-style']);
const MAIN_NS = new Set(['http://schemas.openxmlformats.org/spreadsheetml/2006/main','http://purl.oclc.org/ooxml/spreadsheetml/main']);
const REL_NS = new Set(['http://schemas.openxmlformats.org/officeDocument/2006/relationships','http://purl.oclc.org/ooxml/officeDocument/relationships']);
const NS_PREFIX = new Map<string,string>([...['office','table','text','style','number','manifest','draw','chart','presentation','form','config','meta'].map(prefix => [ODF_NS + (prefix === 'number' ? 'datastyle' : prefix) + ':1.0',prefix] as [string,string]),[ODF_NS + 'svg-compatible:1.0','svg'],[ODF_NS + 'xsl-fo-compatible:1.0','fo'],['http://www.w3.org/1999/xlink','xlink'],['http://www.w3.org/XML/1998/namespace','xml'],...Array.from(REL_NS,uri => [uri,'r'] as [string,string]),['urn:org:documentfoundation:names:experimental:calc:xmlns:calcext:1.0','calcext']]);
type XmlContext = {domain:'xlsx'|'ods'|'manifest'|'rels'|'types';name:string};
const XML_CHILDREN = new Map<string,Map<string,string>>();
function xmlChildren(domain: XmlContext['domain'],parent: string,names: string[],namespace: string) { const key = domain + ':' + parent, map = XML_CHILDREN.get(key) ?? new Map<string,string>(); for (const name of names) map.set(name,namespace); XML_CHILDREN.set(key,map); }
for (const [parent,names] of [
  ['workbook',['sheets','workbookPr','calcPr','definedNames']],['sheets',['sheet']],
  ['worksheet',['dimension','sheetData','cols','mergeCells','conditionalFormatting','dataValidations','tableParts','autoFilter','sheetProtection','extLst','drawing']],['sheetData',['row']],['row',['c']],['c',['f','v','is']],
  ['sst',['si']],['si',['t','r','rPh','phoneticPr']],['is',['t','r','rPh','phoneticPr']],['r',['t','rPr']],
  ['styleSheet',['fonts','fills','borders','cellXfs','cellStyleXfs','numFmts','dxfs','colors','extLst']],['fonts',['font']],['fills',['fill']],['borders',['border']],['cellXfs',['xf']],['cellStyleXfs',['xf']],['xf',['alignment','protection']],['numFmts',['numFmt']],['cols',['col']],['mergeCells',['mergeCell']],
] as const) xmlChildren('xlsx',parent,[...names],'xlsx');
for (const [parent,names,prefix] of [
  ['document-content',['body','automatic-styles'],'office'],['document-styles',['styles','automatic-styles'],'office'],['body',['spreadsheet'],'office'],['spreadsheet',['table','calculation-settings'],'table'],['calculation-settings',['null-date','iteration'],'table'],
  ...['table','table-row-group','table-column-group','table-header-rows','table-rows','table-header-columns','table-columns'].map(parent => [parent,['table-row','table-column','table-row-group','table-column-group','table-header-rows','table-rows','table-header-columns','table-columns'],'table'] as const),
  ['table-row',['table-cell','covered-table-cell'],'table'],['table-cell',['p'],'text'],['covered-table-cell',['p'],'text'],
  ['styles',['style','default-style'],'style'],['automatic-styles',['style','default-style'],'style'],
  ...['style','default-style'].map(parent => [parent,['text-properties','paragraph-properties','table-cell-properties','table-properties','table-row-properties','table-column-properties'],'style'] as const),
  ...['styles','automatic-styles'].map(parent => [parent,[...ODS_NUMBER_STYLES],'datastyle'] as const),
] as const) xmlChildren('ods',parent,[...names],ODF_NS + prefix + ':1.0');
xmlChildren('manifest','manifest',['file-entry'],ODF_NS + 'manifest:1.0'); xmlChildren('manifest','file-entry',['encryption-data'],ODF_NS + 'manifest:1.0');
xmlChildren('rels','Relationships',['Relationship'],'http://schemas.openxmlformats.org/package/2006/relationships');
xmlChildren('types','Types',['Override','Default'],'http://schemas.openxmlformats.org/package/2006/content-types');
const ODS_CELL_ATTRIBUTES = new Map<string,Set<string>>([
  ...['value-type','value','string-value','boolean-value','date-value','time-value','currency'].map(name => [name,new Set([ODF_NS + 'office:1.0',...(name === 'value-type' ? ['urn:org:documentfoundation:names:experimental:calc:xmlns:calcext:1.0'] : [])])] as [string,Set<string>]),
  ...['formula','number-columns-repeated','number-columns-spanned','number-rows-spanned','number-matrix-columns-spanned','number-matrix-rows-spanned','matrix-covered'].map(name => [name,new Set([ODF_NS + 'table:1.0'])] as [string,Set<string>]),
]);
function xmlNamespaceMatches(uri: string,expected: string) { return expected === 'xlsx' ? MAIN_NS.has(uri) : uri === expected; }
function rootContext(name: string,uri: string): XmlContext | null {
  let domain: XmlContext['domain'] | undefined, expected = '';
  if (['workbook','worksheet','sst','styleSheet'].includes(name)) { domain = 'xlsx'; expected = 'xlsx'; }
  else if (name === 'document-content' || name === 'document-styles') { domain = 'ods'; expected = ODF_NS + 'office:1.0'; }
  else if (name === 'manifest') { domain = 'manifest'; expected = ODF_NS + 'manifest:1.0'; }
  else if (name === 'Relationships') { domain = 'rels'; expected = 'http://schemas.openxmlformats.org/package/2006/relationships'; }
  else if (name === 'Types') { domain = 'types'; expected = 'http://schemas.openxmlformats.org/package/2006/content-types'; }
  if (domain && !xmlNamespaceMatches(uri,expected)) fail('UNSUPPORTED_NAMESPACE','Unexpected namespace for workbook root'); return domain ? {domain,name} : null;
}
function scopedAttributeNamespace(context: XmlContext | null,name: string): Set<string> | undefined {
  if (context?.domain === 'ods') {
    if (context.name === 'table-cell' || context.name === 'covered-table-cell') return ODS_CELL_ATTRIBUTES.get(name);
    if (['table-row','table-column','table-row-group','table-column-group'].includes(context.name) && ['number-rows-repeated','number-columns-repeated','visibility','default-cell-style-name','display'].includes(name)) return new Set([ODF_NS + 'table:1.0']);
  }
  if (context?.domain === 'xlsx' && context.name === 'sheet' && name === 'id') return REL_NS;
  return undefined;
}
function expandedName(name: string, namespaces: Map<string,string>, attribute = false): {name:string;uri:string} {
  const index = name.indexOf(':'); if (index < 0) return {name,uri:attribute ? '' : namespaces.get('') ?? ''};
  const prefix = name.slice(0,index), uri = namespaces.get(prefix); if (!uri) fail('UNSUPPORTED_NAMESPACE','Undeclared XML namespace prefix'); return {name:name.slice(index + 1),uri};
}
function parseXml(bytes: Uint8Array, state: State): Element {
  const source = readXml(bytes);
  // Count before allocating a JS XML tree; readXml already bounds depth/markup.
  const tags = source.match(/<(?![!?/])/g)?.length ?? 0; state.nodes += tags; if (state.nodes > WORKBOOK_LIMITS.xmlNodes) fail('WORKBOOK_LIMIT', 'XML node count exceeds workbook limit');
  const raw = new XMLParser({ ignoreAttributes: false, preserveOrder: true, processEntities: false, parseTagValue: false, parseAttributeValue: false, trimValues: false, cdataPropName: '#cdata' }).parse(source) as Record<string,unknown>[];
  const convert = (records: Record<string,unknown>[], inherited = new Map([['xml','http://www.w3.org/XML/1998/namespace']]), parent: XmlContext | null | undefined = undefined): Element[] => {
    const nodes: Element[] = [];
    for (const record of records) for (const [key,value] of Object.entries(record)) {
      if (key.startsWith('?') || key === ':@' || key === '#text' || key === '#cdata') continue;
      const rawAttrs = Object.entries((record[':@'] ?? {}) as Record<string,unknown>).map(([name,value]) => [name.replace(/^@_/,''),decodeXmlReferences(String(value))] as [string,string]);
      const declarations = rawAttrs.filter(([name]) => name === 'xmlns' || name.startsWith('xmlns:')); let namespaces = inherited;
      if (declarations.length) { namespaces = new Map(inherited); for (const [name,value] of declarations) { if (name.length > 255 || value.length > 4096) fail('WORKBOOK_LIMIT','XML namespace declaration exceeds limit'); const prefix = name === 'xmlns' ? '' : name.slice(6); if (prefix === 'xmlns' || prefix === 'xml' && value !== 'http://www.w3.org/XML/1998/namespace' || prefix !== 'xml' && value === 'http://www.w3.org/XML/1998/namespace' || value === 'http://www.w3.org/2000/xmlns/' || prefix && !value) fail('UNSUPPORTED_NAMESPACE','Invalid reserved XML namespace binding'); namespaces.set(prefix,value); } if (namespaces.size > 256) fail('WORKBOOK_LIMIT','XML namespace count exceeds limit'); }
      const nodeName = expandedName(key,namespaces); let context: XmlContext | null = null;
      if (parent === undefined) context = rootContext(nodeName.name,nodeName.uri);
      else if (parent) { const expected = XML_CHILDREN.get(parent.domain + ':' + parent.name)?.get(nodeName.name); if (expected !== undefined) { if (!xmlNamespaceMatches(nodeName.uri,expected)) fail('UNSUPPORTED_NAMESPACE','Unexpected namespace in primary workbook structure'); context = {domain:parent.domain,name:nodeName.name}; } }
      // Unknown/extension subtrees are unmodelled metadata. Their local names
      // never acquire cell-context authority (xm:f is not a stored cell formula).
      const attrs: Record<string,string> = Object.create(null) as Record<string,string>;
      for (const [name,value] of rawAttrs) {
        if (name === 'xmlns' || name.startsWith('xmlns:')) continue; if (value.length > WORKBOOK_LIMITS.cellText) fail('WORKBOOK_LIMIT','XML attribute exceeds text budget');
        const expanded = expandedName(name,namespaces,true), allowed = scopedAttributeNamespace(context,expanded.name); if (expanded.uri && allowed && !allowed.has(expanded.uri)) fail('UNSUPPORTED_NAMESPACE','Unexpected namespace for workbook value/formula attribute');
        const canonical = expanded.uri ? `${NS_PREFIX.get(expanded.uri) ?? '{' + expanded.uri + '}'}:${expanded.name}` : expanded.name;
        if (Object.hasOwn(attrs,canonical)) fail('INVALID_WORKBOOK','Duplicate expanded XML attribute'); attrs[canonical] = value;
      }
      const content = array(value as Record<string,unknown>[]); let text = ''; const elements: Element[] = [], ordered: (string | Element)[] = [];
      for (const item of content) { if ('#text' in item) { const value = decodeXmlReferences(String(item['#text'])); text += value; ordered.push(value); } else if ('#cdata' in item) for (const data of array(item['#cdata'] as Record<string,unknown>[])) { const value = String(data['#text'] ?? ''); text += value; ordered.push(value); } else { const converted = convert([item],namespaces,context); elements.push(...converted); ordered.push(...converted); } }
      nodes.push({ name: nodeName.name, namespace: nodeName.uri, attrs, children: elements, text, content: ordered });
    }
    return nodes;
  };
  const roots = convert(raw); if (roots.length !== 1) fail('INVALID_WORKBOOK', 'XML package part must have one root'); return roots[0];
}
function appendCellText(previous: string,next: string): string { if (next.length > WORKBOOK_LIMITS.cellText - previous.length) fail('WORKBOOK_LIMIT','Expanded primary cell text exceeds limit'); return previous + next; }
function xlsxPrimaryText(container: Element | undefined,gaps: WorkbookGapData[],sheet_id?: string): string {
  let result = '';
  const requireMain = (node: Element) => { if (!MAIN_NS.has(node.namespace)) fail('UNSUPPORTED_NAMESPACE','Foreign namespace cannot supply primary spreadsheet text'); };
  const primary = (node: Element) => { requireMain(node); if (node.children.length) fail('INVALID_WORKBOOK','Nested elements in XLSX primary text'); for (const item of node.content) if (typeof item === 'string') result = appendCellText(result,item); };
  for (const child of container?.children ?? []) {
    if (child.name === 't') primary(child);
    else if (child.name === 'r') { requireMain(child); for (const run of child.children) { if (run.name === 't') primary(run); else if (run.name === 'rPr') gap(gaps,'rich_text','Rich-text run formatting is not retained; primary text is retained.',sheet_id); else gap(gaps,'rich_text_extensions','Unmodelled rich-text extensions are excluded from primary cell text.',sheet_id); } }
    else if (child.name === 'rPh' || child.name === 'phoneticPr') { requireMain(child); gap(gaps,'phonetic_guides','Phonetic pronunciation guides are separate annotations and are excluded from primary cell text.',sheet_id); }
    else gap(gaps,'rich_text_extensions','Unmodelled rich-text extensions are excluded from primary cell text.',sheet_id);
  }
  return xlsxString(result);
}
function requiredPart(parts: Map<string,Uint8Array>, name: string) { const bytes = parts.get(name); if (!bytes) fail('INVALID_WORKBOOK', `Missing workbook package part: ${name}`); return bytes; }
function resolvePart(base: string, target: string): string {
  if (!target || target.includes('\\') || /[\u0000-\u001f?#]/.test(target) || /^[a-z][a-z0-9+.-]*:/i.test(target)) fail('INVALID_WORKBOOK', 'Invalid internal package relationship');
  let decoded: string; try { decoded = decodeURIComponent(target); } catch { fail('INVALID_WORKBOOK', 'Invalid encoded package relationship'); }
  if (decoded.includes('\\') || decoded.includes('\0')) fail('INVALID_WORKBOOK', 'Invalid internal package relationship');
  const resolved = posix.normalize(decoded.startsWith('/') ? decoded.slice(1) : posix.join(posix.dirname(base),decoded));
  if (resolved.startsWith('../') || resolved === '..' || resolved.startsWith('/')) fail('INVALID_WORKBOOK', 'Package relationship escapes archive'); return resolved;
}
type Relationship = { id: string; type: string; target: string; external: boolean };
function relationships(parts: Map<string,Uint8Array>, path: string, state: State): Relationship[] {
  const bytes = parts.get(path); if (!bytes) return [];
  const root = parseXml(bytes,state); if (root.name !== 'Relationships') fail('INVALID_WORKBOOK', 'Invalid relationship part'); const ids = new Set<string>();
  return children(root,'Relationship').map(node => { const id = attr(node,'Id'), type = attr(node,'Type'), target = attr(node,'Target'), mode = attr(node,'TargetMode'); if (!id || !type || !target || ids.has(id) || mode && mode !== 'External' && mode !== 'Internal') fail('INVALID_WORKBOOK', 'Invalid or duplicate relationship'); ids.add(id); return { id, type, target, external: mode === 'External' }; });
}
function xlsxString(value: string) { return value.replace(/_x([0-9a-fA-F]{4})_/g,(_match,hex: string) => String.fromCharCode(parseInt(hex,16))); }
const BUILTIN_FORMATS: Record<number,string> = { 0:'General',1:'0',2:'0.00',3:'#,##0',4:'#,##0.00',9:'0%',10:'0.00%',11:'0.00E+00',12:'# ?/?',13:'# ??/??',14:'mm-dd-yy',15:'d-mmm-yy',16:'d-mmm',17:'mmm-yy',18:'h:mm AM/PM',19:'h:mm:ss AM/PM',20:'h:mm',21:'h:mm:ss',22:'m/d/yy h:mm',37:'#,##0 ;(#,##0)',38:'#,##0 ;[Red](#,##0)',39:'#,##0.00;(#,##0.00)',40:'#,##0.00;[Red](#,##0.00)',45:'mm:ss',46:'[h]:mm:ss',47:'mmss.0',48:'##0.0E+0',49:'@' };
type Style = { number: string | null; values: Record<string,string> };
function styleSegment(name: string): string { return name.replaceAll('%','%25').replaceAll('.','%2E'); }
function styleElementName(node: Element): string { return `${NS_PREFIX.get(node.namespace) ?? '{' + node.namespace + '}'}:${node.name}`; }
function requireOdsProperty(node: Element | undefined): Element | undefined { if (node && node.namespace !== ODF_NS + 'style:1.0') fail('UNSUPPORTED_NAMESPACE','Foreign namespace cannot supply primary ODS style properties'); return node; }
function xmlStyle(node: Element | undefined, prefix: string, result: Record<string,string>, domain: 'xlsx' | 'ods', state: State, root = true) {
  if (!node) return;
  if (domain === 'xlsx' && !MAIN_NS.has(node.namespace)) fail('UNSUPPORTED_NAMESPACE','Foreign namespace cannot supply primary XLSX style properties');
  if (domain === 'ods' && root) requireOdsProperty(node);
  if (prefix.length > 255) fail('WORKBOOK_LIMIT','Style property nesting exceeds supported length');
  for (const [key,value] of Object.entries(node.attrs)) {
    const name = `${prefix}.@${styleSegment(key)}`;
    if (name.length > 255 || value.length > 4096 || Object.keys(result).length >= 256) fail('WORKBOOK_LIMIT','Semantic style exceeds bounded properties');
    // The attribute axis is disjoint from child elements. Each source name is
    // escaped independently so dots/percent escapes inside names cannot add paths.
    result[name] = value;
    if ((domain === 'xlsx' && key.includes(':')) || (domain === 'ods' && !['fo:','style:','table:'].some(prefix => key.startsWith(prefix))) || key.startsWith('{')) gap(state.gaps,'advanced_styles','Namespaced/extension style properties are retained with namespace identity; exact rendering is not evaluated.');
  }
  for (const child of node.children) {
    if (domain === 'xlsx' && child.name === 'extLst') { gap(state.gaps,'advanced_styles','Style extension metadata is excluded from primary semantic properties.'); continue; }
    if (domain === 'xlsx' && !MAIN_NS.has(child.namespace)) fail('UNSUPPORTED_NAMESPACE','Foreign namespace cannot supply primary XLSX style properties');
    if (domain === 'ods' && ![ODF_NS + 'style:1.0',ODF_NS + 'text:1.0',ODF_NS + 'office:1.0',ODF_NS + 'datastyle:1.0'].includes(child.namespace)) gap(state.gaps,'advanced_styles','Foreign style descendants retain namespace identity; exact rendering is not evaluated.');
    if (child.text.trim()) gap(state.gaps,'advanced_styles','Style element text is retained only for attribute-free leaf elements; exact rendering is not evaluated.');
    const name = `${prefix}.${styleSegment(domain === 'xlsx' ? child.name : styleElementName(child))}`;
    if (Object.keys(child.attrs).length === 0 && child.children.length === 0) { if (name.length > 255 || child.text.length > 4096 || Object.keys(result).length >= 256) fail('WORKBOOK_LIMIT','Semantic style exceeds bounded properties'); result[name] = child.text || 'true'; }
    else xmlStyle(child,name,result,domain,state,false);
  }
}
type XlsxStyleResolver = {length:number;get(index:number):Style};
function xlsxStyles(parts: Map<string,Uint8Array>, path: string | undefined, state: State): XlsxStyleResolver {
  if (!path) return {length:0,get:() => fail('INVALID_WORKBOOK','Missing cell style')};
  const root = parseXml(requiredPart(parts,path),state); if (root.name !== 'styleSheet') fail('INVALID_WORKBOOK', 'Invalid XLSX styles');
  const fonts = children(first(root,'fonts'),'font'), fills = children(first(root,'fills'),'fill'), borders = children(first(root,'borders'),'border'), baseXfs = children(first(root,'cellStyleXfs'),'xf'), cellXfs = children(first(root,'cellXfs'),'xf');
  const formats = new Map<number,string>(); for (const node of children(first(root,'numFmts'),'numFmt')) { const id = integer(attr(node,'numFmtId'),0,65535,'number format ID',0), code = attr(node,'formatCode'); if (!code || formats.has(id)) fail('INVALID_WORKBOOK', 'Invalid number format'); formats.set(id,textBudget(state,code)); }
  if (first(root,'dxfs')?.children.length || first(root,'colors')) gap(state.gaps,'advanced_styles','Conditional/differential styles and theme/indexed color resolution are not evaluated.');
  const applyNames = ['applyFont','applyFill','applyBorder','applyAlignment','applyNumberFormat','applyProtection'] as const;
  // Validate small raw booleans even on unused definitions, without resolving
  // or copying any referenced font/fill/border properties.
  for (const nodes of [baseXfs,cellXfs]) for (const node of nodes) for (const name of applyNames) { const raw = attr(node,name); if (raw !== undefined && !['0','1','false','true'].includes(raw)) fail('INVALID_WORKBOOK','Invalid XLSX style application boolean'); }
  const readApply = (node: Element | undefined,values: Record<string,string>,prefix = 'xf') => {
    const flags = new Map<string,boolean>();
    for (const name of applyNames) { const raw = attr(node,name); if (raw === undefined) continue; if (!['0','1','false','true'].includes(raw)) fail('INVALID_WORKBOOK','Invalid XLSX style application boolean'); flags.set(name,truth(raw)); values[`${prefix}.@${styleSegment(name)}`] = raw; }
    return flags;
  };
  type StyleGroup = {values:Record<string,string>;ref:string;count:number};
  const emptyGroup: StyleGroup = {values:{},ref:'empty',count:0}, nodeGroups = new WeakMap<Element,StyleGroup>(), formatRefs = new Map<string|null,string>(), combined = new Map<string,Style>(), resolved = new Map<number,Style>();
  const properties = (node: Element | undefined,prefix: string): StyleGroup => {
    if (!node) return emptyGroup; const known = nodeGroups.get(node); if (known) return known;
    const values: Record<string,string> = {}; xmlStyle(node,prefix,values,'xlsx',state); const count = Object.keys(values).length, result = count ? {values,ref:workbookID('wgroup',values),count} : emptyGroup; nodeGroups.set(node,result); return result;
  };
  const formatRef = (number: string | null) => { const known = formatRefs.get(number); if (known) return known; const ref = workbookID('wformat',number); formatRefs.set(number,ref); return ref; };
  return {length:cellXfs.length,get(index) {
    const cached = resolved.get(index); if (cached) return cached;
    const xf = cellXfs[index]; if (!xf) fail('INVALID_WORKBOOK','Missing cell style');
    const inherited = attr(xf,'xfId') === undefined ? baseXfs[0] : baseXfs[integer(attr(xf,'xfId'),0,Math.max(0,baseXfs.length - 1),'base style index',0)];
    if (attr(xf,'xfId') !== undefined && !inherited) fail('INVALID_WORKBOOK','Missing inherited cell style');
    const rawFlags: Record<string,string> = {}, flags = readApply(xf,rawFlags), groups: StyleGroup[] = []; let number: string | null = null;
    const baseFlags = readApply(inherited,rawFlags,'base'); if (baseFlags.size) gap(state.gaps,'style_application','Base-style application flags are retained as source evidence; exact named-style rendering is not certified.');
    for (const [prop,collection,prefix,flag] of [['fontId',fonts,'font','applyFont'],['fillId',fills,'fill','applyFill'],['borderId',borders,'border','applyBorder']] as const) {
      const lookup = (raw: string | undefined) => { if (raw === undefined) return undefined; const item = collection[integer(raw,0,Math.max(0,collection.length - 1),`${prefix} index`,0)]; if (!item) fail('INVALID_WORKBOOK','Missing semantic style definition'); return item; };
      const direct = lookup(attr(xf,prop)), base = lookup(attr(inherited,prop)), selected = flags.get(flag) === false ? base ?? collection[0] : direct ?? base;
      if (!flags.has(flag) && direct && base && properties(direct,prefix).ref !== properties(base,prefix).ref) gap(state.gaps,'style_application','Some style groups omit apply flags while direct and base properties differ; observed properties are retained and exact Excel application is not certified.');
      groups.push(properties(selected,prefix));
    }
    for (const [name,flag] of [['alignment','applyAlignment'],['protection','applyProtection']] as const) {
      const direct = first(xf,name), base = first(inherited,name), selected = flags.get(flag) === false ? base : direct ?? base;
      if (!flags.has(flag) && direct && properties(direct,name).ref !== properties(base,name).ref) gap(state.gaps,'style_application','Some style groups omit apply flags while direct and base properties differ; observed properties are retained and exact Excel application is not certified.');
      groups.push(properties(selected,name));
    }
    const directNumber = attr(xf,'numFmtId'), baseNumber = attr(inherited,'numFmtId');
    const format = (raw: string | undefined) => { const id = integer(raw,0,65535,'number format ID',0); return formats.get(id) ?? BUILTIN_FORMATS[id] ?? null; };
    const directFormat = directNumber === undefined ? undefined : format(directNumber), baseFormat = format(baseNumber);
    number = flags.get('applyNumberFormat') === false ? baseFormat : directFormat === undefined ? baseFormat : directFormat;
    if (!flags.has('applyNumberFormat') && directFormat !== undefined && directFormat !== baseFormat) gap(state.gaps,'style_application','Some style groups omit apply flags while direct and base properties differ; observed properties are retained and exact Excel application is not certified.');
    if (number === null) gap(state.gaps,'number_format','Some built-in locale-specific number formats are not resolved.');
    // The cache key contains only small stable group/format hashes and six raw
    // flag pairs. Equivalent referenced XFs never stringify/copy a shared huge font again.
    const key = JSON.stringify([rawFlags,groups.map(group => group.ref),formatRef(number)]); let result = combined.get(key);
    if (!result) {
      if (combined.size >= WORKBOOK_LIMITS.metadata) fail('WORKBOOK_LIMIT','Referenced semantic style count exceeds limit');
      if (Object.keys(rawFlags).length + groups.reduce((sum,group) => sum + group.count,0) > 256) fail('WORKBOOK_LIMIT','Combined semantic style exceeds property limit');
      const values = {...rawFlags}; for (const group of groups) Object.assign(values,group.values); result = {number,values}; combined.set(key,result);
    }
    resolved.set(index,result); return result;
  }};
}

function calculationFlags(node: Element | undefined, allowed: readonly string[], state: State, domain: 'xlsx' | 'ods', prefix = '', result: Record<string,string> = {}): Record<string,string> {
  if (!node) return result;
  if (domain === 'xlsx' ? !MAIN_NS.has(node.namespace) : node.namespace !== ODF_NS + 'table:1.0') fail('UNSUPPORTED_NAMESPACE','Foreign namespace cannot supply primary calculation settings');
  for (const [raw,value] of Object.entries(node.attrs)) {
    const key = domain === 'xlsx' ? raw.includes(':') ? null : raw : raw.startsWith('table:') ? raw.slice(6) : null;
    if (key === null || !allowed.includes(key)) { gap(state.gaps,'calculation_metadata','Unmodelled calculation settings are omitted; saved-result freshness remains unknown.'); continue; }
    if (value.length > 128 || Object.keys(result).length >= 32) fail('WORKBOOK_LIMIT','Calculation metadata exceeds bounded fields');
    result[prefix + key] = value;
  }
  return result;
}
function numeric(value: string) { if (!/^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$/.test(value) || !Number.isFinite(Number(value))) fail('INVALID_WORKBOOK','Invalid numeric cell value'); return value; }
function validateBoolean(value: string) { if (!['0','1','true','false'].includes(value)) fail('INVALID_WORKBOOK','Invalid boolean cell value'); return value; }
async function extractXlsx(parts: Map<string,Uint8Array>, state: State): Promise<WorkbookObservationData> {
  if (!parts.has('[Content_Types].xml')) fail('INVALID_WORKBOOK','Missing OPC content types');
  const content = parseXml(requiredPart(parts,'[Content_Types].xml'),state); if (content.name !== 'Types') fail('INVALID_WORKBOOK','Invalid OPC content types');
  if ([...parts.keys()].some(name => /(?:^|\/)(?:vbaProject\.bin|EncryptionInfo|EncryptedPackage)$/i.test(name)) || content.children.some(node => /macroEnabled|vbaProject/i.test(attr(node,'ContentType') ?? ''))) fail('UNSUPPORTED_WORKBOOK','Macro-enabled or encrypted workbooks are unsupported');
  const rootLinks = relationships(parts,'_rels/.rels',state), office = rootLinks.filter(link => /\/officeDocument$/.test(link.type)); if (office.length !== 1 || office[0].external) fail('INVALID_WORKBOOK','Missing internal workbook relationship');
  const path = resolvePart('',office[0].target), root = parseXml(requiredPart(parts,path),state); if (root.name !== 'workbook') fail('INVALID_WORKBOOK','Not an XLSX workbook');
  const relPath = posix.join(posix.dirname(path),'_rels',posix.basename(path) + '.rels'), links = relationships(parts,relPath,state);
  const linkFor = (suffix: string) => { const found = links.filter(link => link.type.endsWith('/' + suffix)); if (found.length > 1 || found.some(link => link.external)) fail('INVALID_WORKBOOK',`Invalid ${suffix} relationship`); return found[0] ? resolvePart(path,found[0].target) : undefined; };
  const styleList = xlsxStyles(parts,linkFor('styles'),state), sharedPath = linkFor('sharedStrings'), shared: string[] = [];
  if (sharedPath) { const strings = parseXml(requiredPart(parts,sharedPath),state); if (strings.name !== 'sst') fail('INVALID_WORKBOOK','Invalid shared strings'); for (const item of children(strings,'si')) { if (shared.length >= WORKBOOK_LIMITS.cells) fail('WORKBOOK_LIMIT','Too many shared strings'); shared.push(textBudget(state,xlsxPrimaryText(item,state.gaps))); } }
  for (const name of parts.keys()) {
    for (const [pattern,feature] of [[/(?:^|\/)externalLinks\//i,'external_links'],[/(?:^|\/)embeddings\//i,'embedded_objects'],[/(?:^|\/)drawings\//i,'drawings'],[/(?:^|\/)charts\//i,'charts'],[/(?:^|\/)(?:pivotTables|pivotCache)\//i,'pivots'],[/(?:^|\/)tables\//i,'structured_tables'],[/(?:^|\/)connections(?:\/|\.xml$)/i,'connections'],[/(?:^|\/)queryTables\//i,'query_tables']] as const) if (pattern.test(name)) gap(state.gaps,feature,`${feature} are outside the compared cell model and are never evaluated or refreshed.`);
    if (/(?:^|\/)comments[^/]*\.xml$/i.test(name)) gap(state.gaps,'comments','Cell comments are not part of compared cell content.');
    if (name.endsWith('.rels') && name !== relPath && name !== '_rels/.rels') for (const link of relationships(parts,name,state)) { if (link.external) gap(state.gaps,'external_relationships','External relationships are recorded as unsupported and never opened or refreshed.'); }
  }
  if (links.some(link => link.external) || rootLinks.some(link => link.external)) gap(state.gaps,'external_relationships','External relationships are never opened or refreshed.');
  if (first(root,'definedNames')) gap(state.gaps,'defined_names','Named ranges/formulas are not modelled independently; formula source is retained.');
  const sheetNodes = children(first(root,'sheets'),'sheet'); if (!sheetNodes.length || sheetNodes.length > WORKBOOK_LIMITS.sheets) fail('WORKBOOK_LIMIT','Workbook must have 1 to 100 sheets');
  const sheets: WorkbookSheetData[] = [], usedPaths = new Set<string>(), names = new Set<string>();
  for (const node of sheetNodes) {
    await checkpoint(state,true);
    const name = attr(node,'name') ?? '', id = attr(node,'r:id') ?? attr(node,'id'), matches = links.filter(link => link.id === id); if (matches.length !== 1 || matches[0].external || !matches[0].type.endsWith('/worksheet')) fail('UNSUPPORTED_WORKBOOK','Non-worksheet or missing worksheet relationship');
    const sheetPath = resolvePart(path,matches[0].target); if (usedPaths.has(sheetPath) || names.has(name.toLowerCase())) fail('INVALID_WORKBOOK','Duplicate sheet identity'); usedPaths.add(sheetPath); names.add(name.toLowerCase());
    const sheet = newSheet('xlsx',name,sheetPath,sheets.length); const visibility = attr(node,'state'); if (visibility && !['visible','hidden','veryHidden'].includes(visibility)) fail('INVALID_WORKBOOK','Invalid sheet visibility'); sheet.hidden = visibility === 'hidden' || visibility === 'veryHidden';
    if (visibility === 'veryHidden') gap(sheet.coverage_gaps,'very_hidden_sheet','Sheet has Excel veryHidden visibility; the observation exposes it for comparison.',sheet.sheet_id);
    const xml = parseXml(requiredPart(parts,sheetPath),state); if (xml.name !== 'worksheet') fail('INVALID_WORKBOOK','Invalid worksheet part');
    const dimension = attr(first(xml,'dimension'),'ref'); if (dimension) { const [,,r,c] = parseRange(dimension); sheet.row_count = r; sheet.column_count = c; }
    const columnNodes = children(first(xml,'cols'),'col');
    if (columnNodes.length > WORKBOOK_LIMITS.metadata) fail('WORKBOOK_LIMIT','Too many column metadata entries');
    const columns = columnNodes.map(col => ({ min: integer(attr(col,'min'),1,WORKBOOK_LIMITS.columns,'column range'), max: integer(attr(col,'max'),1,WORKBOOK_LIMITS.columns,'column range'), hidden: truth(attr(col,'hidden')), style: attr(col,'style') }));
    if (columns.some(column => column.style !== undefined)) gap(sheet.coverage_gaps,'row_column_default_styles','Default row/column styles can cover absent cells; only materialized cell formatting is compared, and blank formatted rectangles are not expanded.',sheet.sheet_id);
    const effectiveColumns: ({hidden:boolean;style:string|undefined}|undefined)[] = new Array(WORKBOOK_LIMITS.columns + 1); let lastColumn = 0;
    for (const [index,col] of columns.entries()) { if (col.max < col.min || col.min <= lastColumn) fail('INVALID_WORKBOOK','Overlapping or unordered column spans'); lastColumn = col.max; addAxisMetadata(sheet.column_metadata,{ start: col.min, end: col.max, hidden: col.hidden, size: attr(columnNodes[index],'width') ?? null }); sheet.column_count = Math.max(sheet.column_count,col.max); for (let column = col.min; column <= col.max; column++) effectiveColumns[column] = col; }
    const addresses = new Set<string>(), formulaRanges: FormulaRange[] = [], savedCells = new WeakSet<WorkbookCellData>(), sharedWithRange = new Set<string>(), sharedWithoutRange = new Set<string>(); let wholeFormulaSheet = false, previousRow = 0;
    for (const rowNode of children(first(xml,'sheetData'),'row')) {
      const row = integer(attr(rowNode,'r'),previousRow + 1,WORKBOOK_LIMITS.rows,'row index'); if (row <= previousRow) fail('INVALID_WORKBOOK','Duplicate or unordered worksheet rows'); previousRow = row; let previousColumn = 0;
      if (attr(rowNode,'s') !== undefined || truth(attr(rowNode,'customFormat'))) gap(sheet.coverage_gaps,'row_column_default_styles','Default row/column styles can cover absent cells; only materialized cell formatting is compared, and blank formatted rectangles are not expanded.',sheet.sheet_id);
      const hidden = truth(attr(rowNode,'hidden')); if (hidden || attr(rowNode,'ht') !== undefined) { addAxisMetadata(sheet.row_metadata,{start: row, end: row, hidden, size: attr(rowNode,'ht') ?? null}); sheet.row_count = Math.max(sheet.row_count,row); }
      for (const node of children(rowNode,'c')) {
        await checkpoint(state); let column = previousColumn + 1; if (attr(node,'r')) { const [cellRow,cellColumn] = parseAddress(attr(node,'r')!); if (cellRow !== row) fail('INVALID_WORKBOOK','Cell address disagrees with row'); column = cellColumn; } if (column <= previousColumn || column > WORKBOOK_LIMITS.columns) fail('INVALID_WORKBOOK','Duplicate or unordered worksheet cells'); previousColumn = column;
        const cell = makeCell(sheet,row,column); if (addresses.has(cell.address)) fail('INVALID_WORKBOOK','Duplicate worksheet cell'); addresses.add(cell.address); cell.hidden_row = hidden; cell.hidden_column = effectiveColumns[column]?.hidden ?? false;
        // CT_Cell@s defaults to0 for an allocated <c>. Axis defaults are
        // unsupported absent-cell coverage, not overrides of this cell's style.
        // https://learn.microsoft.com/en-us/office/open-xml/spreadsheet/how-to-insert-a-chart-into-a-spreadsheet#cell-element
        const styleRaw = attr(node,'s');
        if (state.cells >= WORKBOOK_LIMITS.cells) fail('WORKBOOK_LIMIT','Workbook materialized cell budget exceeded');
        if (styleRaw !== undefined || styleList.length) { const index = integer(styleRaw,0,Math.max(0,styleList.length - 1),'cell style index',0); const style = styleList.get(index); cell.number_format = style.number; cell.style = style.values; }
        if (['f','v','is'].some(name => children(node,name).length > 1)) fail('INVALID_WORKBOOK','Duplicate cell content');
        const f = first(node,'f'), valueNode = first(node,'v'), type = attr(node,'t') ?? 'n', emptyNumericValue = type === 'n' && valueNode?.text === ''; if (f) { cell.formula = f.text; cell.formula_dialect = 'xlsx_a1'; cell.formula_interpretation = 'explicit'; cell.cached_result = !emptyNumericValue && (valueNode || first(node,'is')) ? 'present' : 'missing'; if (attr(f,'t') && attr(f,'t') !== 'normal') { cell.formula_interpretation = 'unresolved'; const ref = attr(f,'ref'), sharedId = attr(f,'si'); if (ref) { addFormulaRange(formulaRanges,parseRange(ref)); if (attr(f,'t') === 'shared' && sharedId !== undefined) sharedWithRange.add(sharedId); } else if (attr(f,'t') === 'shared' && sharedId !== undefined) sharedWithoutRange.add(sharedId); else wholeFormulaSheet = true; gap(sheet.coverage_gaps,'shared_array_formulas','Shared/array/spill/data-table formulas are not expanded; source text and saved values are retained with unresolved interpretation.',sheet.sheet_id); } }
        if (type === 'inlineStr') { cell.value_type = 'string'; cell.value = xlsxPrimaryText(first(node,'is'),sheet.coverage_gaps,sheet.sheet_id); }
        else if (valueNode) { const value = valueNode.text;
          if (type === 's') { const index = integer(value,0,Math.max(0,shared.length - 1),'shared string index',0); if (shared[index] === undefined) fail('INVALID_WORKBOOK','Missing shared string'); cell.value_type = 'string'; cell.value = shared[index]; }
          else if (type === 'str') { cell.value_type = 'string'; cell.value = xlsxString(value); }
          else if (type === 'n') { if (value === '') { cell.value_type = 'blank'; cell.value = null; } else { cell.value_type = 'number'; cell.value = numeric(value); } }
          else if (type === 'b') { cell.value_type = 'boolean'; cell.value = validateBoolean(value); }
          else if (type === 'd') { cell.value_type = 'date'; cell.value = value; }
          else if (type === 'e') { cell.value_type = 'error'; cell.value = value; }
          else fail('UNSUPPORTED_WORKBOOK','Unsupported XLSX cell value type');
        } else if (!['n','s','str','b','d','e'].includes(type)) fail('UNSUPPORTED_WORKBOOK','Unsupported XLSX cell type');
        if (!emptyNumericValue && (valueNode || first(node,'is'))) savedCells.add(cell);
        if (attr(node,'cm') !== undefined || attr(node,'vm') !== undefined) { wholeFormulaSheet = true; gap(sheet.coverage_gaps,'cell_metadata','Cell metadata can encode dynamic arrays or richer types; this sheet is conservatively unresolved.',sheet.sheet_id); }
        if (f && (!valueNode || emptyNumericValue) && type !== 'inlineStr') gap(sheet.coverage_gaps,'missing_formula_cache','Formula has no saved calculation result; formulas are never recalculated.',sheet.sheet_id);
        addCell(state,sheet,cell);
      }
    }
    if ([...sharedWithoutRange].some(id => !sharedWithRange.has(id))) wholeFormulaSheet = true;
    await applyFormulaInterpretation(sheet,formulaRanges,wholeFormulaSheet,state,savedCells);
    for (const merge of children(first(xml,'mergeCells'),'mergeCell')) { const range = attr(merge,'ref'); if (!range) fail('INVALID_WORKBOOK','Missing merged cell range'); const [r,c,rr,cc] = parseRange(range); if (sheet.merges.length >= WORKBOOK_LIMITS.metadata) fail('WORKBOOK_LIMIT','Too many merged ranges'); sheet.merges.push(`${cellAddress(r,c)}:${cellAddress(rr,cc)}`); sheet.row_count = Math.max(sheet.row_count,rr); sheet.column_count = Math.max(sheet.column_count,cc); }
    for (const [tag,feature] of [['conditionalFormatting','conditional_formatting'],['extLst','extension_features'],['drawing','drawings'],['dataValidations','data_validation'],['tableParts','structured_tables'],['autoFilter','filters'],['sheetProtection','protection']] as const) if (first(xml,tag)) gap(sheet.coverage_gaps,feature,`${feature} are not evaluated by the cell comparison model.`,sheet.sheet_id);
    sheets.push(sheet);
  }
  gap(state.gaps,'stored_formula_results','Only saved cell results are observed; their freshness is unknown and no calculation or external data refresh occurs.');
  gap(state.gaps,'display_layout','Exact Excel rendering, row heights, column widths, locale/theme resolution and page layout are outside this cell model.');
  if (truth(attr(first(root,'workbookPr'),'date1904'))) gap(state.gaps,'date_epoch','Workbook uses the 1904 date system. Numeric date serials and number formats are retained without conversion.');
  return { format: 'xlsx', sheets, coverage_gaps: state.gaps, calculation: 'stored_values_only_no_recalculation', date_system: truth(attr(first(root,'workbookPr'),'date1904')) ? '1904' : '1900', calc_flags: calculationFlags(first(root,'calcPr'),['calcId','calcMode','fullCalcOnLoad','refMode','iterate','iterateCount','iterateDelta','fullPrecision','calcCompleted','calcOnSave','concurrentCalc','concurrentManualCount','forceFullCalc'],state,'xlsx') };
}
function descendants(node: Element, name: string): Element[] { const found: Element[] = []; const visit = (current: Element) => { if (current.name === name) found.push(current); for (const child of current.children) visit(child); }; visit(node); return found; }
function odsPrimaryText(paragraphs: Element[],gaps: WorkbookGapData[],sheet_id?: string): string {
  let result = '';
  const write = (value: string) => { result = appendCellText(result,value); };
  const visit = (node: Element) => {
    if (node.namespace !== ODF_NS + 'text:1.0') {
      if (['p','span','s','tab','line-break','ruby','ruby-base','ruby-text'].includes(node.name)) fail('UNSUPPORTED_NAMESPACE','Foreign namespace cannot supply primary ODS text');
      gap(gaps,'rich_text_extensions','Embedded/foreign rich-text annotations are excluded from primary cell text.',sheet_id); return;
    }
    if (node.name === 's') { const count = integer(attr(node,'text:c'),1,WORKBOOK_LIMITS.cellText,'ODS text space repetition'); if (count > WORKBOOK_LIMITS.cellText - result.length) fail('WORKBOOK_LIMIT','Expanded ODS spaces exceed cell text budget'); write(' '.repeat(count)); return; }
    if (node.name === 'tab') { write('\t'); return; } if (node.name === 'line-break') { write('\n'); return; }
    if (node.name === 'ruby' || node.name === 'ruby-text') { gap(gaps,'phonetic_guides','Ruby pronunciation annotations are excluded from primary cell text.',sheet_id); if (node.name === 'ruby') for (const child of children(node,'ruby-base')) visit(child); return; }
    for (const item of node.content) if (typeof item === 'string') write(item); else visit(item);
  };
  for (const [index,paragraph] of paragraphs.entries()) { if (index) write('\n'); visit(paragraph); }
  return result;
}
function canonicalStyle(root: Element,state: State): string {
  // Serialize one nested JSON structure. Re-stringifying child JSON strings at
  // every ancestor would escape them repeatedly and amplify with nesting depth.
  const limit = 16384 - 'ods:'.length, tokens: string[] = []; let length = 0;
  const write = (token: string) => { if (token.length > limit - length) fail('WORKBOOK_LIMIT','ODS number format exceeds 16384 characters'); length += token.length; tokens.push(token); };
  const quote = (value: string) => {
    const available = limit - length; let encoded = 2;
    // Every raw UTF-16 code unit contributes at least one JSON code unit. Reject
    // large fields before JSON.stringify can allocate their escaped equivalent.
    if (value.length > available - 2) fail('WORKBOOK_LIMIT','ODS number format exceeds 16384 characters');
    for (let index = 0; index < value.length; index++) {
      const code = value.charCodeAt(index);
      if (code === 34 || code === 92 || code === 8 || code === 9 || code === 10 || code === 12 || code === 13) encoded += 2;
      else if (code < 32) encoded += 6;
      else if (code >= 0xd800 && code <= 0xdbff) { const next = value.charCodeAt(index + 1); if (next >= 0xdc00 && next <= 0xdfff) { encoded += 2; index++; } else encoded += 6; }
      else encoded += code >= 0xdc00 && code <= 0xdfff ? 6 : 1;
      if (encoded > available) fail('WORKBOOK_LIMIT','ODS number format exceeds 16384 characters');
    }
    write(JSON.stringify(value));
  };
  const visit = (node: Element) => {
    if (![ODF_NS + 'datastyle:1.0',ODF_NS + 'style:1.0',ODF_NS + 'text:1.0'].includes(node.namespace)) gap(state.gaps,'advanced_styles','Foreign number-style descendants retain namespace identity; exact rendering is not evaluated.');
    write('{"namespace":'); quote(NS_PREFIX.get(node.namespace) ?? '{' + node.namespace + '}'); write(',"name":'); quote(node.name); write(',"attrs":{');
    let attribute = 0;
    for (const key of Object.keys(node.attrs).filter(name => !['style:name','style:display-name'].includes(name)).sort()) {
      if (!['number:','style:','fo:','text:'].some(prefix => key.startsWith(prefix))) gap(state.gaps,'advanced_styles','Unqualified/foreign number-style attributes retain namespace identity; exact rendering is not evaluated.');
      if (attribute++) write(','); quote(key); write(':'); quote(node.attrs[key]);
    }
    write('},"content":[');
    for (const [index,item] of node.content.entries()) { if (index) write(','); if (typeof item === 'string') quote(item); else visit(item); }
    write(']}');
  };
  visit(root); return tokens.join('');
}
type OdsStyles = { cell(name?: string): Style; effective(name?: string): boolean; hidden(name?: string): boolean; size(name: string | undefined, kind: 'row' | 'column'): string | null };
type OdsStyleScope = { styles: Map<string,Element>; formats: Map<string,Element> };
function odsStyles(roots: Element[], state: State): OdsStyles {
  const common: OdsStyleScope = {styles:new Map(),formats:new Map()}, automatic: OdsStyleScope[] = roots.map(() => ({styles:new Map(),formats:new Map()}));
  const origin = new WeakMap<Element,OdsStyleScope>(), cellCache = new Map<string,Style>(), effectiveCache = new Map<string,boolean>(); let defaultCell: Element | undefined;
  const supported = new Set(['table-cell','table-row','table-column','table']);
  const collect = (container: Element,scope: OdsStyleScope) => {
    for (const item of container.children) {
      const name = attr(item,'style:name'), family = attr(item,'style:family');
      if (name && name.length > 255) fail('WORKBOOK_LIMIT','ODS style name exceeds 255 characters');
      if (item.name === 'default-style' && family === 'table-cell') { if (defaultCell) fail('INVALID_WORKBOOK','Duplicate default cell style'); defaultCell = item; origin.set(item,scope); }
      else if (item.name === 'style') {
        const key = family + ':' + name; if (!name || !family || scope.styles.has(key)) fail('INVALID_WORKBOOK','Duplicate or unnamed ODS style within one scope'); scope.styles.set(key,item); origin.set(item,scope);
        if (!supported.has(family)) gap(state.gaps,'ods_style_family','Some non-cell/row/column/table style families are outside the compared model.');
      } else if (name && ODS_NUMBER_STYLES.has(item.name)) { if (item.namespace !== ODF_NS + 'datastyle:1.0') fail('UNSUPPORTED_NAMESPACE','Foreign namespace cannot supply primary ODS number styles'); if (scope.formats.has(name)) fail('INVALID_WORKBOOK','Duplicate ODS data style within one scope'); scope.formats.set(name,item); }
      else if (name && /-style$/.test(item.name)) gap(state.gaps,'ods_style_family','Unmodelled named style families are outside the compared model.');
    }
  };
  // Automatic style names are local to their package part. styles.xml page and
  // header styles must not collide with content.xml cell/row/column definitions.
  for (const [index,root] of roots.entries()) { for (const node of children(root,'styles')) collect(node,common); for (const node of children(root,'automatic-styles')) collect(node,automatic[index]); }
  const contentAutomatic = automatic.at(-1); if (!contentAutomatic) fail('INVALID_WORKBOOK','Missing ODS style scope');
  const resolve = (name: string | undefined, family: string): Element[] => {
    const result: Element[] = [], seen = new Set<Element>(); let item = name ? contentAutomatic.styles.get(family + ':' + name) ?? common.styles.get(family + ':' + name) : undefined;
    if (name && !item) fail('INVALID_WORKBOOK','Missing content-scoped ODS style');
    while (item) {
      if (seen.has(item) || result.length >= 100) fail('INVALID_WORKBOOK','Cyclic ODS style inheritance'); seen.add(item); result.unshift(item);
      const parent = attr(item,'style:parent-style-name'); if (!parent) break;
      // Named/common parents win over automatic names. Automatic fallback stays
      // in the originating part; it can never enter styles.xml's unrelated scope.
      const scope = origin.get(item); item = common.styles.get(family + ':' + parent) ?? scope?.styles.get(family + ':' + parent); if (!item) fail('INVALID_WORKBOOK','Missing parent ODS style');
    }
    return result;
  };
  type OdsGroup = {values:Record<string,string>;ref:string;count:number;text:number;number?:string};
  type OdsPlan = {groups:OdsGroup[];number:string|null;ref:string};
  const emptyGroup: OdsGroup = {values:{},ref:'empty',count:0,text:0}, emptyPlan: OdsPlan = {groups:[],number:null,ref:'empty'};
  const nodeGroups = new WeakMap<Element,OdsGroup>(), nodePlans = new WeakMap<Element,OdsPlan>(), namedPlans = new Map<string,OdsPlan>(), composedPlans = new Map<string,OdsPlan>(), planStyles = new WeakMap<OdsPlan,Style>(), signatures = new WeakMap<Style,string>(), semanticStyles = new Map<string,Style>(), formatCache = new WeakMap<Element,string>(), formatRefs = new Map<string|null,string>();
  let defaultPlan: OdsPlan | undefined, resolvedEntries = 0, resolvedText = 0;
  const formatRef = (value: string | null) => { const cached = formatRefs.get(value); if (cached) return cached; const ref = workbookID('ods_format',value); formatRefs.set(value,ref); return ref; };
  const describe = (node: Element): OdsGroup => {
    const known = nodeGroups.get(node); if (known) return known;
    const values: Record<string,string> = {};
    for (const child of node.children) if (['text-properties','paragraph-properties','table-cell-properties'].includes(child.name)) xmlStyle(child,child.name,values,'ods',state); else if (child.name === 'map') gap(state.gaps,'conditional_formatting','ODS conditional style maps are not evaluated.');
    let number: string | undefined; const data = attr(node,'style:data-style-name');
    if (data) { const format = origin.get(node)?.formats.get(data) ?? common.formats.get(data); if (!format) fail('INVALID_WORKBOOK','Missing scoped ODS number format'); number = formatCache.get(format); if (number === undefined) { number = 'ods:' + canonicalStyle(format,state); if (number.length > 16384) fail('WORKBOOK_LIMIT','ODS number format exceeds 16384 characters'); formatCache.set(format,number); } }
    const entries = Object.entries(values), result = entries.length || number !== undefined ? {values,ref:entries.length ? workbookID('ods_group',values) : 'empty',count:entries.length,text:entries.reduce((sum,[key,value]) => sum + key.length + value.length,0),...(number !== undefined ? {number} : {})} : emptyGroup;
    nodeGroups.set(node,result); return result;
  };
  const lookup = (groups: OdsGroup[],key: string) => { for (let index = groups.length - 1; index >= 0; index--) if (Object.hasOwn(groups[index].values,key)) return groups[index].values[key]; return undefined; };
  const compose = (parent: OdsPlan,source: OdsGroup): OdsPlan => {
    if (!source.count && (source.number === undefined || source.number === parent.number)) return parent;
    const inputKey = JSON.stringify([parent.ref,source.ref,source.number === undefined ? 'inherit' : formatRef(source.number)]), known = composedPlans.get(inputKey); if (known) return known;
    // Test only this source node's overrides. Never clone or serialize its large
    // inherited default just to discover that an alias adds no effective format.
    let effective = source;
    if (parent.groups.length && source.count) { const changed = Object.entries(source.values).filter(([key,value]) => lookup(parent.groups,key) !== value); if (!changed.length) effective = emptyGroup; else if (changed.length !== source.count) { const values = Object.fromEntries(changed); effective = {values,ref:workbookID('ods_group',values),count:changed.length,text:changed.reduce((sum,[key,value]) => sum + key.length + value.length,0)}; } }
    const number = source.number ?? parent.number;
    if (!effective.count && number === parent.number) { composedPlans.set(inputKey,parent); return parent; }
    if (composedPlans.size >= WORKBOOK_LIMITS.metadata) fail('WORKBOOK_LIMIT','Resolved ODS style plans exceed metadata budget');
    const plan = {groups:effective.count ? [...parent.groups,effective] : parent.groups,number,ref:workbookID('ods_plan',[parent.ref,effective.ref,formatRef(number)])}; composedPlans.set(inputKey,plan); return plan;
  };
  const planFor = (name?: string): OdsPlan => {
    if (defaultPlan === undefined) defaultPlan = defaultCell ? compose(emptyPlan,describe(defaultCell)) : emptyPlan;
    if (name === undefined) return defaultPlan; const known = namedPlans.get(name); if (known) return known;
    let plan = defaultPlan;
    for (const node of resolve(name,'table-cell')) { const cached = nodePlans.get(node); if (cached) plan = cached; else { plan = compose(plan,describe(node)); nodePlans.set(node,plan); } }
    namedPlans.set(name,plan); return plan;
  };
  const materialize = (plan: OdsPlan): Style => {
    const known = planStyles.get(plan); if (known) return known;
    const final = new Map<string,string>(); for (let index = plan.groups.length - 1; index >= 0; index--) for (const [key,value] of Object.entries(plan.groups[index].values)) if (!final.has(key)) { final.set(key,value); if (final.size > 256) fail('WORKBOOK_LIMIT','Combined ODS semantic style exceeds property limit'); }
    const text = [...final].reduce((sum,[key,value]) => sum + key.length + value.length,plan.number?.length ?? 0);
    // Column/default checks can resolve styles before a cell exists. Bound that
    // derivation separately, before allocating merged maps or canonical hashes.
    if (resolvedEntries + final.size > WORKBOOK_LIMITS.styleEntries || resolvedText + text > WORKBOOK_LIMITS.text) fail('WORKBOOK_LIMIT','ODS style resolution exceeds property/text budget');
    resolvedEntries += final.size; resolvedText += text;
    const values = Object.fromEntries(final), signature = workbookID('ods_semantic',{number:plan.number,values}); let result = semanticStyles.get(signature);
    if (!result) { if (semanticStyles.size >= WORKBOOK_LIMITS.metadata) fail('WORKBOOK_LIMIT','Distinct resolved ODS styles exceed metadata budget'); result = {number:plan.number,values}; semanticStyles.set(signature,result); signatures.set(result,signature); }
    planStyles.set(plan,result); return result;
  };
  const cell = (name?: string): Style => { const known = cellCache.get(name ?? ''); if (known) return known; const result = materialize(planFor(name)); cellCache.set(name ?? '',result); return result; };
  return {
    cell,
    effective(name) { if (name === undefined) return false; const known = effectiveCache.get(name); if (known !== undefined) return known; const plan = planFor(name), baseline = planFor(); const effective = plan === baseline ? false : signatures.get(materialize(plan)) !== signatures.get(materialize(baseline)); effectiveCache.set(name,effective); return effective; },
    hidden(name) { let hidden = false; for (const node of resolve(name,'table')) { const value = attr(requireOdsProperty(first(node,'table-properties')),'table:display'); if (value !== undefined) hidden = value === 'false' || value === '0'; } return hidden; },
    size(name,kind) { let size: string | null = null; for (const node of resolve(name,`table-${kind}`)) { const properties = requireOdsProperty(first(node,`table-${kind}-properties`)); size = attr(properties,kind === 'row' ? 'style:row-height' : 'style:column-width') ?? size; } return size; },
  };
}
function odsVisibility(node: Element): 'visible' | 'collapse' | 'filter' {
  const value = attr(node,'table:visibility'); if (value === undefined) return 'visible';
  if (value !== 'visible' && value !== 'collapse' && value !== 'filter') fail('INVALID_WORKBOOK','Invalid ODS row/column visibility'); return value;
}
type OdsAxisNode = { node: Element; inheritedHidden: boolean };
function flattenOdsAxis(table: Element, axis: 'row' | 'column'): OdsAxisNode[] {
  const result: OdsAxisNode[] = [];
  const visit = (node: Element, inheritedHidden: boolean) => {
    for (const child of node.children) {
      if (child.name === `table-${axis}`) result.push({ node: child, inheritedHidden });
      else if ([`table-header-${axis}s`,`table-${axis}s`,`table-${axis}-group`].includes(child.name)) {
        const display = child.name === `table-${axis}-group` ? attr(child,'table:display') : undefined;
        if (display !== undefined && !['true','false','1','0'].includes(display)) fail('INVALID_WORKBOOK','Invalid ODS group display boolean');
        // A visible inner group cannot reveal rows/columns of a hidden parent.
        visit(child,inheritedHidden || display === 'false' || display === '0');
      }
    }
  };
  visit(table,false); return result;
}
function flattenOdsRows(table: Element): OdsAxisNode[] { return flattenOdsAxis(table,'row'); }
function flattenOdsColumns(table: Element): OdsAxisNode[] { return flattenOdsAxis(table,'column'); }
async function extractOds(parts: Map<string,Uint8Array>, state: State): Promise<WorkbookObservationData> {
  const mime = new TextDecoder('utf-8',{fatal:true}).decode(requiredPart(parts,'mimetype')); if (mime !== 'application/vnd.oasis.opendocument.spreadsheet') fail('INVALID_WORKBOOK','Package is not an ODS spreadsheet');
  const manifest = parseXml(requiredPart(parts,'META-INF/manifest.xml'),state); if (manifest.name !== 'manifest') fail('INVALID_WORKBOOK','Invalid ODS manifest'); if (descendants(manifest,'encryption-data').length) fail('ENCRYPTED_WORKBOOK','Encrypted ODS packages are unsupported');
  if ([...parts.keys()].some(name => /^(?:Basic|Scripts)\//i.test(name))) fail('UNSUPPORTED_WORKBOOK','ODS executable script packages are unsupported');
  const root = parseXml(requiredPart(parts,'content.xml'),state); if (root.name !== 'document-content') fail('INVALID_WORKBOOK','Invalid ODS content');
  const stylesRoot = parts.has('styles.xml') ? parseXml(requiredPart(parts,'styles.xml'),state) : undefined; const styles = odsStyles([...(stylesRoot ? [stylesRoot] : []),root],state);
  const currencyStyles = new WeakMap<Record<string,string>,Map<string,Record<string,string>>>();
  const withCurrency = (base: Record<string,string>,currency: string) => {
    if (currency.length > 4096) fail('WORKBOOK_LIMIT','Currency style value exceeds limit'); let variants = currencyStyles.get(base); if (!variants) { variants = new Map(); currencyStyles.set(base,variants); }
    const known = variants.get(currency); if (known) return known; const derived = {...base,currency}; if (Object.keys(derived).length > 256) fail('WORKBOOK_LIMIT','Currency style exceeds property limit'); variants.set(currency,derived); return derived;
  };

  const spreadsheet = first(first(root,'body'),'spreadsheet'); if (!spreadsheet) fail('INVALID_WORKBOOK','Missing ODS spreadsheet body');
  const tables = children(spreadsheet,'table'); if (!tables.length || tables.length > WORKBOOK_LIMITS.sheets) fail('WORKBOOK_LIMIT','Workbook must have 1 to 100 sheets');
  if (descendants(root,'scripts').length || descendants(root,'event-listener').length) gap(state.gaps,'scripts_events','Scripts/event bindings are not executed or modelled.');
  for (const [tag,feature] of [['frame','drawings'],['object','embedded_objects'],['data-pilot-tables','pivots'],['database-ranges','structured_tables'],['named-expressions','defined_names'],['content-validations','data_validation'],['conditional-formats','conditional_formatting'],['chart','charts'],['filter-condition','filters'],['equation','drawings']] as const) if (descendants(root,tag).length) gap(state.gaps,feature,`${feature} are not evaluated by the cell comparison model.`);
  for (const entry of descendants(manifest,'file-entry')) { const media = attr(entry,'manifest:media-type') ?? ''; if (media === 'application/vnd.oasis.opendocument.chart') gap(state.gaps,'charts','Embedded charts are not evaluated by the cell comparison model.'); else if (media && /(?:^Object|^Pictures\/)/.test(attr(entry,'manifest:full-path') ?? '')) gap(state.gaps,'embedded_objects','Embedded packages/images are not evaluated by the cell comparison model.'); }
  for (const node of descendants(root,'a')) if (attr(node,'xlink:href')) gap(state.gaps,'external_relationships','Linked content is retained only as cell text; targets are never followed.');
  if (descendants(root,'table-source').length || descendants(root,'dde-link').length || descendants(root,'cell-range-source').length) gap(state.gaps,'external_relationships','External/DDE data sources are never opened or refreshed.');
  const sheets: WorkbookSheetData[] = [], names = new Set<string>();
  for (const table of tables) {
    await checkpoint(state,true); const name = attr(table,'table:name') ?? ''; if (names.has(name.toLowerCase())) fail('INVALID_WORKBOOK','Duplicate ODS sheet name'); names.add(name.toLowerCase());
    const sheet = newSheet('ods',name,`content.xml#table/${sheets.length}`,sheets.length), formulaRanges: FormulaRange[] = []; let wholeFormulaSheet = false; sheet.hidden = attr(table,'table:display') === 'false' || styles.hidden(attr(table,'table:style-name'));
    const columns: {start: number; end: number; hidden: boolean; style: string | undefined}[] = []; let nextColumn = 1;
    for (const {node:col,inheritedHidden} of flattenOdsColumns(table)) { const repeat = integer(attr(col,'table:number-columns-repeated'),1,WORKBOOK_LIMITS.columns,'ODS column repetition'), end = nextColumn + repeat - 1; if (end > WORKBOOK_LIMITS.columns) fail('WORKBOOK_LIMIT','ODS column repetition exceeds worksheet bounds'); const visibility = odsVisibility(col), hidden = inheritedHidden || visibility === 'collapse' || visibility === 'filter'; const size = styles.size(attr(col,'table:style-name'),'column'); columns.push({start:nextColumn,end,hidden,style:attr(col,'table:default-cell-style-name')}); if (hidden || size !== null) { addAxisMetadata(sheet.column_metadata,{start:nextColumn,end,hidden,size}); sheet.column_count = Math.max(sheet.column_count,end); } nextColumn = end + 1; }
    const effectiveColumns: ({hidden:boolean;style:string|undefined}|undefined)[] = new Array(WORKBOOK_LIMITS.columns + 1); for (const column of columns) for (let cc = column.start; cc <= column.end; cc++) effectiveColumns[cc] = column;
    // A sparse row can span every column. Index visibility boundaries once so
    // each source row visits only its emitted ranges, never its full cell area.
    // Unmentioned columns are visible; explicit cell styles override defaults.
    const hiddenColumnRunEnds = new Uint16Array(WORKBOOK_LIMITS.columns + 1);
    for (let cc = WORKBOOK_LIMITS.columns; cc >= 1; cc--) {
      if ((cc & 1023) === 0) await checkpoint(state,true);
      hiddenColumnRunEnds[cc] = cc === WORKBOOK_LIMITS.columns || (effectiveColumns[cc]?.hidden ?? false) !== (effectiveColumns[cc + 1]?.hidden ?? false) ? cc : hiddenColumnRunEnds[cc + 1];
    }
    if (columns.some(column => column.style !== undefined)) gap(sheet.coverage_gaps,'row_column_default_styles','Default row/column styles covering absent cells are not expanded. Explicit blank-cell styles are retained as materialized cells or bounded sparse rectangles.',sheet.sheet_id);
    let row = 1;
    for (const {node:rowNode,inheritedHidden} of flattenOdsRows(table)) {
      await checkpoint(state);
      const rowRepeat = integer(attr(rowNode,'table:number-rows-repeated'),1,WORKBOOK_LIMITS.rows,'ODS row repetition'), lastRow = row + rowRepeat - 1; if (lastRow > WORKBOOK_LIMITS.rows) fail('WORKBOOK_LIMIT','ODS row repetition exceeds worksheet bounds');
      const visibility = odsVisibility(rowNode), hiddenRow = inheritedHidden || visibility === 'collapse' || visibility === 'filter', rowSize = styles.size(attr(rowNode,'table:style-name'),'row'); if (hiddenRow || rowSize !== null) { addAxisMetadata(sheet.row_metadata,{start:row,end:lastRow,hidden:hiddenRow,size:rowSize}); sheet.row_count = Math.max(sheet.row_count,lastRow); }
      const rowDefaultStyle = attr(rowNode,'table:default-cell-style-name'); if (rowDefaultStyle !== undefined) gap(sheet.coverage_gaps,'row_column_default_styles','Default row/column styles covering absent cells are not expanded. Explicit blank-cell styles are retained as materialized cells or bounded sparse rectangles.',sheet.sheet_id);
      const rowCells: {node: Element; column: number; repeat: number; style: string | undefined; material: boolean; sparse: boolean}[] = []; let column = 1;
      for (const node of rowNode.children.filter(child => child.name === 'table-cell' || child.name === 'covered-table-cell')) {
        const repeat = integer(attr(node,'table:number-columns-repeated'),1,WORKBOOK_LIMITS.columns,'ODS cell repetition'); if (column + repeat - 1 > WORKBOOK_LIMITS.columns) fail('WORKBOOK_LIMIT','ODS cell repetition exceeds worksheet bounds');
        const directStyle = attr(node,'table:style-name'), style = directStyle ?? rowDefaultStyle;
        // These known non-value annotations do not justify expanding empty
        // repetitions. Their unsupported semantics remain explicit sheet gaps.
        // Unknown attributes, values, formulas, spans and children stay material.
        if (attr(node,'table:content-validation-name') !== undefined) gap(sheet.coverage_gaps,'data_validation','Cell validation rules are not evaluated.',sheet.sheet_id);
        if (attr(node,'table:protect') !== undefined || attr(node,'table:protected') !== undefined) gap(sheet.coverage_gaps,'cell_protection','Cell protection annotations are not evaluated or compared; original source attributes remain in the retained file.',sheet.sheet_id);
        const sourceContent = node.name === 'covered-table-cell' || node.children.length > 0 || Object.keys(node.attrs).some(key => !['table:style-name','table:number-columns-repeated','table:content-validation-name','table:protect','table:protected'].includes(key));
        if (node.name === 'covered-table-cell' && (attr(node,'office:value-type') || attr(node,'table:formula') || node.children.length)) { wholeFormulaSheet = true; gap(sheet.coverage_gaps,'covered_cell_content','Covered source cells contain independent saved content; the sheet is conservatively unresolved.',sheet.sheet_id); }
        if (sourceContent || directStyle !== undefined && styles.effective(directStyle)) rowCells.push({node,column,repeat,style,material:sourceContent,sparse:!sourceContent && repeat * rowRepeat > 64});
        column += repeat;
      }
      const perRow = rowCells.reduce((count,cell) => count + (!cell.sparse ? cell.repeat : 0),0); if (perRow * rowRepeat > WORKBOOK_LIMITS.cells - state.cells) fail('WORKBOOK_LIMIT','ODS materialized repetitions exceed cell budget');
      for (const item of rowCells) if (item.sparse) {
        // Split only at hidden-column boundaries; the explicit cell style overrides
        // column defaults. The rectangle remains independent of its cell area.
        const semantic = styles.cell(item.style); let start = item.column;
        while (start < item.column + item.repeat) {
          await checkpoint(state); const hidden = effectiveColumns[start]?.hidden ?? false, end = Math.min(item.column + item.repeat - 1,hiddenColumnRunEnds[start]);
          if (++state.blankRanges > WORKBOOK_LIMITS.metadata) fail('WORKBOOK_LIMIT','Workbook explicit blank formatting ranges exceed 100000 entries');
          const range: WorkbookBlankStyleRangeData = {row_start:row,row_end:lastRow,column_start:start,column_end:end,number_format:semantic.number,style:semantic.values,hidden_row:hiddenRow,hidden_column:hidden,source_ref:`${sheet.source_ref}!${cellAddress(row,start)}:${cellAddress(lastRow,end)}`};
          internStyle(state,range); (sheet.blank_style_ranges ??= []).push(range);
          sheet.row_count = Math.max(sheet.row_count,lastRow); sheet.column_count = Math.max(sheet.column_count,end); start = end + 1;
        }
      }
      // Empty repeated rows/cells only advance physical coordinates. This is
      // important for Calc's million-row trailing empty representation.
      if (perRow > 0) for (let rr = row; rr <= lastRow; rr++) for (const item of rowCells) if (!item.sparse) for (let cc = item.column; cc < item.column + item.repeat; cc++) {
        await checkpoint(state); const node = item.node, cell = makeCell(sheet,rr,cc), col = effectiveColumns[cc], semantic = styles.cell(item.style ?? col?.style); cell.style = semantic.values; cell.number_format = semantic.number; if (!item.material) cell.blank_style_only = true; cell.hidden_row = hiddenRow; cell.hidden_column = col?.hidden ?? false; cell.formula = attr(node,'table:formula') ?? null; if (cell.formula !== null) { cell.formula_dialect = 'ods_openformula'; cell.formula_interpretation = 'explicit'; }
        const type = attr(node,'office:value-type'), extensionType = attr(node,'calcext:value-type'), explicitString = attr(node,'office:string-value'), paragraphs = children(node,'p'), unknownExtension = extensionType !== undefined && extensionType !== 'error' && extensionType !== type;
        if (extensionType === 'error') {
          // Actual LibreOffice26.8 saves errors with an empty office string
          // placeholder; the displayed paragraph contains the saved error code.
          const savedError = paragraphs.length ? odsPrimaryText(paragraphs,sheet.coverage_gaps,sheet.sheet_id) : explicitString; cell.value_type = 'error'; cell.value = savedError === '' || savedError === undefined ? null : savedError;
          if (cell.value === null) gap(sheet.coverage_gaps,'missing_error_cache','A Calc error type is present but its saved error text is unavailable.',sheet.sheet_id);
        }
        else if (unknownExtension) {
          cell.value_type = 'blank'; cell.value = null; cell.formula_interpretation = 'unresolved'; cell.cached_result = 'missing'; cell.cache_freshness = 'unknown'; gap(sheet.coverage_gaps,'unknown_calc_value_type','Unmodelled Calc extension value type prevents a certified cache interpretation; this is not an empty-string result.',sheet.sheet_id);
        }
        else if (type === 'string' || explicitString !== undefined || (!type && paragraphs.length && cell.formula === null)) { cell.value_type = 'string'; cell.value = explicitString ?? odsPrimaryText(paragraphs,sheet.coverage_gaps,sheet.sheet_id); }
        else if (type === 'float' || type === 'percentage' || type === 'currency') { const value = attr(node,'office:value'); cell.value_type = 'number'; cell.value = value === undefined ? null : numeric(value); const currency = attr(node,'office:currency'); if (type === 'currency' && currency !== undefined) cell.style = withCurrency(cell.style,currency); }
        else if (type === 'boolean') { const value = attr(node,'office:boolean-value'); cell.value_type = 'boolean'; cell.value = value === undefined ? null : validateBoolean(value); }
        else if (type === 'date') { cell.value_type = 'date'; cell.value = attr(node,'office:date-value') ?? null; }
        else if (type === 'time') { cell.value_type = 'time'; cell.value = attr(node,'office:time-value') ?? null; }
        else if (type === 'void' || type === undefined) { cell.value_type = 'blank'; cell.value = null; }
        else fail('UNSUPPORTED_WORKBOOK',`Unsupported ODS cell type: ${type}`);
        if (!unknownExtension && extensionType !== 'error' && cell.formula === null && cell.value === null && ['float','percentage','currency','boolean','date','time'].includes(type ?? '')) fail('INVALID_WORKBOOK','Typed ODS value has no source value');
        if (cell.formula !== null) cell.cached_result = cell.value === null ? 'missing' : 'present';
        if (cell.formula !== null && cell.value === null) gap(sheet.coverage_gaps,'missing_formula_cache','Formula has no saved calculation result; formulas are never recalculated.',sheet.sheet_id);
        const columnSpan = integer(attr(node,'table:number-columns-spanned'),1,WORKBOOK_LIMITS.columns,'ODS merge column span'), rowSpan = integer(attr(node,'table:number-rows-spanned'),1,WORKBOOK_LIMITS.rows,'ODS merge row span');
        if (columnSpan > 1 || rowSpan > 1) { if (rr + rowSpan - 1 > WORKBOOK_LIMITS.rows || cc + columnSpan - 1 > WORKBOOK_LIMITS.columns) fail('WORKBOOK_LIMIT','ODS merged range exceeds worksheet bounds'); if (sheet.merges.length >= WORKBOOK_LIMITS.metadata) fail('WORKBOOK_LIMIT','Too many merged ranges'); sheet.merges.push(`${cell.address}:${cellAddress(rr + rowSpan - 1,cc + columnSpan - 1)}`); sheet.row_count = Math.max(sheet.row_count,rr + rowSpan - 1); sheet.column_count = Math.max(sheet.column_count,cc + columnSpan - 1); }
        if (first(node,'annotation')) gap(sheet.coverage_gaps,'comments','Cell comments are not part of compared cell content.',sheet.sheet_id);
        if (cell.formula && /(?:file|https?|ftp):\/\//i.test(cell.formula)) gap(sheet.coverage_gaps,'external_links','Formula source refers to external content; it is never opened or refreshed.',sheet.sheet_id);
        if (truth(attr(node,'table:matrix-covered')) || attr(node,'table:number-matrix-columns-spanned') || attr(node,'table:number-matrix-rows-spanned')) {
          cell.formula_interpretation = 'unresolved'; cell.cache_freshness = 'unknown'; cell.cached_result = cell.value === null ? 'missing' : 'present';
          const matrixColumns = attr(node,'table:number-matrix-columns-spanned'), matrixRows = attr(node,'table:number-matrix-rows-spanned');
          if (matrixColumns !== undefined || matrixRows !== undefined) { const endColumn = cc + integer(matrixColumns,1,WORKBOOK_LIMITS.columns,'ODS matrix column span') - 1, endRow = rr + integer(matrixRows,1,WORKBOOK_LIMITS.rows,'ODS matrix row span') - 1; if (endColumn > WORKBOOK_LIMITS.columns || endRow > WORKBOOK_LIMITS.rows) fail('WORKBOOK_LIMIT','ODS matrix range exceeds worksheet bounds'); addFormulaRange(formulaRanges,[rr,cc,endRow,endColumn]); } else wholeFormulaSheet = true;
          gap(sheet.coverage_gaps,'array_formulas','Matrix/spill relationships are unresolved; source formula and stored values are retained.',sheet.sheet_id);
        }
        addCell(state,sheet,cell);
      }
      row = lastRow + 1;
    }
    await applyFormulaInterpretation(sheet,formulaRanges,wholeFormulaSheet,state);
    sheets.push(sheet);
  }
  gap(state.gaps,'stored_formula_results','Only saved cell results are observed; freshness is unknown, formulas and external data are never evaluated.');
  gap(state.gaps,'display_layout','Exact Calc rendering, locale, rich-text styling, conditional formatting and page layout are outside this cell model.');
  return {format:'ods',sheets,coverage_gaps:state.gaps,calculation:'stored_values_only_no_recalculation',date_system:'iso8601',calc_flags:(() => { const settings = first(spreadsheet,'calculation-settings'), result = calculationFlags(settings,['case-sensitive','precision-as-shown','search-criteria-must-apply-to-whole-cell','automatic-find-labels','use-regular-expressions','use-wildcards','null-year'],state,'ods'); calculationFlags(first(settings,'null-date'),['date-value'],state,'ods','null-date.',result); calculationFlags(first(settings,'iteration'),['status','steps','maximum-difference'],state,'ods','iteration.',result); return result; })()};
}
async function extractCsv(bytes: Uint8Array, state: State): Promise<WorkbookObservationData> {
  let source: string; try { source = new TextDecoder('utf-8',{fatal:true}).decode(bytes); } catch { fail('UNSUPPORTED_WORKBOOK','CSV must use valid UTF-8 encoding'); }
  if (source.includes('\0') || source.startsWith('\ufffe') || source.startsWith('\uffff')) fail('INVALID_WORKBOOK','CSV contains forbidden binary characters');
  const sheet = newSheet('csv','Sheet1','csv/Sheet1',0); let field = '', row = 1, column = 1, quoted = false, afterQuote = false, started = false;
  const emit = () => { if (row > WORKBOOK_LIMITS.rows || column > WORKBOOK_LIMITS.columns) fail('WORKBOOK_LIMIT','CSV exceeds worksheet bounds'); const cell = makeCell(sheet,row,column); cell.value_type = field === '' ? 'blank' : 'string'; cell.value = field === '' ? null : field; addCell(state,sheet,cell); field = ''; afterQuote = false; started = false; column++; };
  for (let i = 0; i < source.length; i++) {
    if ((i & 4095) === 0) await checkpoint(state,true); const char = source[i];
    if (quoted) { if (char === '"') { if (source[i + 1] === '"') { field += '"'; i++; } else { quoted = false; afterQuote = true; } } else field += char; }
    else if (char === ',') emit();
    else if (char === '\r' || char === '\n') { emit(); if (char === '\r' && source[i + 1] === '\n') i++; row++; column = 1; }
    else if (afterQuote) fail('INVALID_WORKBOOK','Unexpected content after quoted CSV field');
    else if (char === '"') { if (started || field !== '') fail('INVALID_WORKBOOK','Quote inside unquoted CSV field'); quoted = true; started = true; }
    else { field += char; started = true; }
    if (field.length > WORKBOOK_LIMITS.cellText) fail('WORKBOOK_LIMIT','CSV field exceeds text budget');
  }
  if (quoted) fail('INVALID_WORKBOOK','Unterminated quoted CSV field');
  if (field !== '' || started || afterQuote || column > 1) emit();
  gap(state.gaps,'untyped_csv','UTF-8 comma-delimited CSV has one sheet and textual fields only; numeric/date types, formulas, cached results, styles, merges and hidden state cannot be recovered. Formula-looking text is never executed.');
  return {format:'csv',sheets:[sheet],coverage_gaps:state.gaps,calculation:'stored_values_only_no_recalculation',date_system:'unknown',calc_flags:{}};
}
export async function extractWorkbook(bytes: Uint8Array, format: WorkbookFormatData, options: {signal?: AbortSignal} = {}): Promise<WorkbookObservationData> {
  const state: State = {signal:options.signal,cells:0,nodes:0,text:0,ticks:0,styleEntries:0,blankRanges:0,styleDefinitions:Object.create(null) as Record<string,Record<string,string>>,styleRefs:new WeakMap(),stylesByCanonical:new Map(),numberFormats:new Set(),gaps:[]}; abort(state);
  if (bytes.byteLength > WORKBOOK_LIMITS.input) fail('WORKBOOK_LIMIT','Workbook input exceeds 64 MiB');
  if (bytes.length >= 8 && Buffer.from(bytes.subarray(0,8)).equals(Buffer.from([0xd0,0xcf,0x11,0xe0,0xa1,0xb1,0x1a,0xe1]))) fail('UNSUPPORTED_WORKBOOK','Legacy binary or encrypted Office workbooks are unsupported');
  await checkpoint(state,true);
  const result = format === 'csv' ? await extractCsv(bytes,state) : format === 'xlsx' ? await extractXlsx(await readPackage(bytes,state),state) : format === 'ods' ? await extractOds(await readPackage(bytes,state),state) : fail('UNSUPPORTED_WORKBOOK','Unsupported workbook format');
  for (const sheet of result.sheets) metadataBudget(sheet); if (Object.keys(state.styleDefinitions).length) result.style_definitions = state.styleDefinitions; abort(state); return result;
}
