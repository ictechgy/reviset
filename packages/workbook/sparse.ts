import { DocverError } from '../schema/index.js';
import { cellAddress, type WorkbookBlankStyleRangeData, type WorkbookCellData, type WorkbookSheetData } from './types.js';

export function rangeAddress(range: Pick<WorkbookBlankStyleRangeData,'row_start'|'row_end'|'column_start'|'column_end'>) {
  return `${cellAddress(range.row_start,range.column_start)}:${cellAddress(range.row_end,range.column_end)}`;
}
export function blankRangeCell(sheet: WorkbookSheetData, range: WorkbookBlankStyleRangeData, row: number, column: number): WorkbookCellData {
  return {address:cellAddress(row,column),row,column,value_type:'blank',value:null,formula:null,cached_result:range.formula_interpretation==='unresolved'?'missing':'not_applicable',cache_freshness:range.formula_interpretation==='unresolved'?'unknown':'not_applicable',formula_dialect:null,formula_interpretation:range.formula_interpretation??'not_formula',number_format:range.number_format,style:range.style,...(range.style_ref ? {style_ref:range.style_ref} : {}),hidden_row:range.hidden_row,hidden_column:range.hidden_column,blank_style_only:true,source_range:rangeAddress(range),source_ref:`${sheet.source_ref}!${cellAddress(row,column)}`};
}

// Only bounded viewports synthesize cells. Search and endpoint diff retain the
// source rectangles and never ask to expand an entire million-row worksheet.
export function blankCellsInViewport(sheet: WorkbookSheetData, rowStart: number, rowEnd: number, columnStart: number, columnEnd: number) {
  const ranges=(sheet.blank_style_ranges ?? []).filter(r=>r.row_start<rowEnd&&r.row_end>=rowStart&&r.column_start<columnEnd&&r.column_end>=columnStart);
  if(!ranges.length)return [];
  if((rowEnd-rowStart)*(columnEnd-columnStart)>40_000)throw new DocverError('WORKBOOK_RANGE_LIMIT','Blank formatting expansion requires a viewport of at most 40000 cells; read formatting ranges for larger regions');
  const cells:WorkbookCellData[]=[];
  for(const range of ranges)for(let row=Math.max(rowStart,range.row_start);row<Math.min(rowEnd,range.row_end+1);row++)for(let column=Math.max(columnStart,range.column_start);column<Math.min(columnEnd,range.column_end+1);column++)cells.push(blankRangeCell(sheet,range,row,column));
  return cells;
}

// A fixed 16,384-column segment tree bounds validation by O((ranges+cells)log C).
// It rejects overlapping rectangles or overlapping source cells without area
// expansion, including a hostile full-sheet repeated blank rectangle.
export function validateBlankRangeLayout(sheet: WorkbookSheetData) {
  const ranges=sheet.blank_style_ranges ?? []; if(!ranges.length)return;
  const maxima=new Int32Array(65_536),lazy=new Int32Array(65_536);
  const update=(left:number,right:number,delta:number,node=1,lo=1,hi=16_384):void=>{if(left<=lo&&hi<=right){maxima[node]+=delta;lazy[node]+=delta;return;}const mid=(lo+hi)>>1;if(left<=mid)update(left,right,delta,node*2,lo,mid);if(right>mid)update(left,right,delta,node*2+1,mid+1,hi);maxima[node]=lazy[node]+Math.max(maxima[node*2],maxima[node*2+1]);};
  const query=(left:number,right:number,node=1,lo=1,hi=16_384):number=>{if(left<=lo&&hi<=right)return maxima[node];const mid=(lo+hi)>>1;let value=0;if(left<=mid)value=Math.max(value,query(left,right,node*2,lo,mid));if(right>mid)value=Math.max(value,query(left,right,node*2+1,mid+1,hi));return lazy[node]+value;};
  const events=ranges.flatMap((range,index)=>[{row:range.row_start,index,delta:1},{row:range.row_end+1,index,delta:-1}]).sort((a,b)=>a.row-b.row||a.delta-b.delta);
  const cells=[...sheet.cells].sort((a,b)=>a.row-b.row||a.column-b.column);let at=0;
  for(const cell of cells){while(at<events.length&&events[at].row<=cell.row){const event=events[at++],range=ranges[event.index];if(event.delta>0&&query(range.column_start,range.column_end)>0)throw new DocverError('WORKBOOK_RANGE_OVERLAP','Explicit blank formatting rectangles overlap');update(range.column_start,range.column_end,event.delta);}if(query(cell.column,cell.column)>0)throw new DocverError('WORKBOOK_RANGE_OVERLAP','Explicit blank formatting rectangle overlaps a materialized cell');}
  while(at<events.length){const event=events[at++],range=ranges[event.index];if(event.delta>0&&query(range.column_start,range.column_end)>0)throw new DocverError('WORKBOOK_RANGE_OVERLAP','Explicit blank formatting rectangles overlap');update(range.column_start,range.column_end,event.delta);}
}

// Compare physical blank formatting without interpreting row identity or
// allocating a cell per coordinate. Equivalent repeated/split encodings give
// the same result; work and resulting observations have independent limits.
export function compareBlankRanges(before: WorkbookSheetData, after: WorkbookSheetData, identity:(range:WorkbookBlankStyleRangeData,side:0|1)=>string, signal?:AbortSignal) {
  const collect=(sheet:WorkbookSheetData):WorkbookBlankStyleRangeData[]=>[...(sheet.blank_style_ranges??[]),...sheet.cells.filter(c=>c.blank_style_only).map(c=>({row_start:c.row,row_end:c.row,column_start:c.column,column_end:c.column,style:c.style,...(c.style_ref?{style_ref:c.style_ref}:{}),number_format:c.number_format,hidden_row:c.hidden_row,hidden_column:c.hidden_column,...(c.formula_interpretation==='unresolved'?{formula_interpretation:'unresolved' as const}:{}),source_ref:c.source_ref}))];
  const sides=[collect(before),collect(after)] as const;
  const events=sides.flatMap((ranges,side)=>ranges.flatMap((range,index)=>[{row:range.row_start,side,index,delta:1},{row:range.row_end+1,side,index,delta:-1}])).sort((a,b)=>a.row-b.row||a.delta-b.delta);
  const active=[new Map<number,WorkbookBlankStyleRangeData>(),new Map<number,WorkbookBlankStyleRangeData>()],signatures=[new Map<WorkbookBlankStyleRangeData,string>(),new Map<WorkbookBlankStyleRangeData,string>()];
  const signature=(range:WorkbookBlankStyleRangeData,side:0|1)=>{let value=signatures[side].get(range);if(value===undefined){value=identity(range,side);signatures[side].set(range,value);}return value;};
  const output:{before:WorkbookBlankStyleRangeData|null;after:WorkbookBlankStyleRangeData|null}[]=[];let at=0,work=0;
  while(at<events.length){signal?.throwIfAborted();const row=events[at].row;while(at<events.length&&events[at].row===row){const event=events[at++];if(event.delta<0)active[event.side].delete(event.index);else active[event.side].set(event.index,sides[event.side][event.index]);}if(at===events.length)break;const endRow=events[at].row-1;
    const sorted=active.map(map=>[...map.values()].sort((a,b)=>a.column_start-b.column_start));work+=sorted[0].length+sorted[1].length;if(work>2_000_000)throw new DocverError('WORKBOOK_DIFF_LIMIT','Blank formatting comparison exceeds 2000000 active interval observations');
    const boundaries=[...new Set(sorted.flatMap(ranges=>ranges.flatMap(r=>[r.column_start,r.column_end+1])))].sort((a,b)=>a-b),indices=[0,0];
    for(let i=0;i+1<boundaries.length;i++){const column=boundaries[i],endColumn=boundaries[i+1]-1;const found=sorted.map((ranges,side)=>{while(indices[side]<ranges.length&&ranges[indices[side]].column_end<column)indices[side]++;const range=ranges[indices[side]];return range&&range.column_start<=column?range:null;});if((found[0]?signature(found[0],0):null)===(found[1]?signature(found[1],1):null))continue;
      if(output.length>=100_000)throw new DocverError('WORKBOOK_DIFF_LIMIT','Blank formatting comparison exceeds 100000 range observations');
      const clip=(range:WorkbookBlankStyleRangeData|null)=>range?{...range,row_start:row,row_end:endRow,column_start:column,column_end:endColumn}:null;output.push({before:clip(found[0]),after:clip(found[1])});
    }
  }
  return output;
}
