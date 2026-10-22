import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,writeFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {odsFixture,xlsxFixture} from '../workbook-fixtures.js';
import {extractWorkbook} from '../../packages/workbook/ingest.js';
import {diffWorkbooks,type WorkbookRevisionData} from '../../packages/workbook/diff.js';
import {WorkbookService} from '../../packages/workbook/service.js';
import {WorkbookQueryService} from '../../packages/workbook/query.js';
import {Store} from '../../packages/storage/index.js';

const styles='<number:number-style style:name="N1"><number:number number:decimal-places="2"/></number:number-style>'+
  '<style:style style:name="paint" style:family="table-cell"><style:table-cell-properties fo:background-color="#ffff00"/></style:style>'+
  '<style:style style:name="red" style:family="table-cell"><style:table-cell-properties fo:background-color="#ff0000"/></style:style>'+
  '<style:style style:name="numeric" style:family="table-cell" style:data-style-name="N1"><style:table-cell-properties fo:background-color="#ffff00"/></style:style>';
const blank=(columns:number,style='paint',split=false):string=>columns===0?'':split?Array.from({length:columns},()=>blank(1,style)).join(''):`<table:table-cell table:style-name="${style}" table:number-columns-repeated="${columns}"/>`;
const text=(value:string)=>`<table:table-cell table:style-name="paint" office:value-type="string"><text:p>${value}</text:p></table:table-cell>`;
const payloads=[
  {name:'value',ods:text('payload'),xlsx:'<c r="B1" t="inlineStr"><is><t>payload</t></is></c>',value:'payload',formula:null},
  {name:'zero',ods:'<table:table-cell table:style-name="paint" office:value-type="float" office:value="0"/>',xlsx:'<c r="B1"><v>0</v></c>',value:'0',formula:null},
  {name:'formula',ods:'<table:table-cell table:style-name="paint" table:formula="of:=1+1" office:value-type="float" office:value="2"/>',xlsx:'<c r="B1"><f>1+1</f><v>2</v></c>',value:'2',formula:'1+1'},
] as const;
async function revision(source:Uint8Array,format:'ods'|'xlsx',index:number):Promise<WorkbookRevisionData>{
  return {...await extractWorkbook(source,format),revision_occurrence_id:'revision_'+index,label:String(index),index,asset_id:'sha256:'+String(index).repeat(64)};
}
const ods=(xml:string)=>odsFixture(xml,{automatic:styles});

test('matched content moves retain physical style, number-format and hidden-row observations at blank endpoints',async()=>{
  for(const columns of [2,64,65,100])for(const split of [false,true])for(const payload of payloads){
    const content='<table:table-row>'+text('key')+payload.ods+blank(columns-2,'paint',split)+'</table:table-row>';
    const before=await revision(ods(content+'<table:table-row>'+blank(columns,'paint',split)+'</table:table-row>'),'ods',0);
    for(const change of ['none','style','number_format','visibility'] as const){
      const after=await revision(ods(`<table:table-row${change==='visibility'?' table:visibility="collapse"':''}>`+blank(columns,change==='style'?'red':change==='number_format'?'numeric':'paint',split)+'</table:table-row>'+content),'ods',1);
      for(const reverse of [false,true]){
        const events=diffWorkbooks(...(reverse?[after,before]:[before,after]) as [WorkbookRevisionData,WorkbookRevisionData]);
        const move=events.filter(c=>c.kind==='row_position');assert.equal(move.length,1);assert.equal(move[0].association,'inferred');assert.equal(move[0].before_address,reverse?'A2':'A1');assert.equal(move[0].after_address,reverse?'A1':'A2');
        const physical=events.filter(c=>c.alignment_method==='physical_blank_content_coordinate');
        assert.equal(physical.length,change==='none'?0:2,`${columns}, split=${split}, ${payload.name}, ${change}, reverse=${reverse}`);
        for(const event of physical){
          assert.equal(event.kind,change);assert.equal(event.association,'needs_review');assert.equal(event.before_address,event.after_address);assert.ok(['A1','B1'].includes(event.before_address!));assert.ok(event.before&&event.after);
          assert.equal(event.before.blank_style_only===true,reverse);assert.equal(event.after.blank_style_only===true,!reverse);
          if(event.before_address==='B1')assert.equal((reverse?event.after:event.before).value,payload.value);
        }
        assert.equal(new Set(physical.map(c=>c.change_id)).size,physical.length);
        assert.ok(!events.some(c=>['cell_observation','stored_value','formula','value_type','row_correspondence'].includes(c.kind)));
        if(change==='none')assert.equal(events.length,1);
      }
    }
  }
});

test('moved content keeps inferred visibility changes distinct from physical hidden-column observations',async()=>{
  const content='<table:table-row>'+text('key')+payloads[1].ods+'</table:table-row>';
  const before=await revision(ods(content+'<table:table-row>'+blank(65)+'</table:table-row>'),'ods',0);
  const after=await revision(ods('<table:table-column/><table:table-column table:visibility="collapse"/><table:table-row>'+blank(65)+'</table:table-row>'+content),'ods',1);
  for(const reverse of [false,true]){
    const events=diffWorkbooks(...(reverse?[after,before]:[before,after]) as [WorkbookRevisionData,WorkbookRevisionData]);
    const physical=events.filter(c=>c.kind==='visibility'&&c.alignment_method==='physical_blank_content_coordinate');
    assert.deepEqual(physical.map(c=>c.before_address).sort(),['B1','B2']);
    assert.ok(physical.every(c=>c.association==='needs_review'&&c.before_address===c.after_address&&c.before?.hidden_column===reverse&&c.after?.hidden_column===!reverse));
    const inferred=events.filter(c=>c.kind==='visibility'&&c.association==='inferred');assert.equal(inferred.length,1);assert.equal(inferred[0].before_address,reverse?'B2':'B1');assert.equal(inferred[0].after_address,reverse?'B1':'B2');
    assert.equal(events.filter(c=>c.kind==='row_position').length,1);
  }
});

test('cross-format blank/content confidence is independent of repeat compression and cell count',async()=>{
  for(const columns of [1,64,65,100])for(const payload of payloads){
    const filled=await revision(xlsxFixture('<sheetData><row r="1"><c r="A1" t="inlineStr"><is><t>key</t></is></c>'+payload.xlsx+'</row></sheetData>'),'xlsx',1);
    for(const reverse of [false,true]){
      const summaries=[];
      for(const split of [false,true]){
        const empty=await revision(ods('<table:table-row>'+text('key')+blank(columns,'paint',split)+'</table:table-row>'),'ods',0);
        if(columns>64)assert.equal((empty.sheets[0].blank_style_ranges?.length??0)>0,!split);
        const events=diffWorkbooks(...(reverse?[filled,empty]:[empty,filled]) as [WorkbookRevisionData,WorkbookRevisionData]);
        const transition=events.filter(c=>c.alignment_method==='physical_blank_content_coordinate');assert.equal(transition.length,1);
        const event=transition[0];assert.equal(event.kind,'cell_observation');assert.equal(event.association,'needs_review');assert.equal(event.before_address,'B1');assert.equal(event.after_address,'B1');assert.ok(event.before&&event.after);
        const blankEndpoint=reverse?event.after:event.before,contentEndpoint=reverse?event.before:event.after;
        assert.equal(blankEndpoint.blank_style_only,true);assert.equal(blankEndpoint.value,null);assert.equal(contentEndpoint.value,payload.value);assert.equal(contentEndpoint.formula,payload.formula);
        assert.ok(!events.some(c=>['stored_value','value_type','formula','style','number_format','formatting_range','row_correspondence'].includes(c.kind)));
        summaries.push(events.map(c=>[c.kind,c.association,c.alignment_method,c.before_address,c.after_address,c.before?.value,c.after?.value]));
      }
      assert.deepEqual(summaries[0],summaries[1]);
    }
  }
});

test('persisted MCP history and net queries retain moved-blank formatting and cross-format endpoint confidence',async()=>{
  const root=await mkdtemp(join(tmpdir(),'reviset-moved-blank-formatting-')),store=new Store(join(root,'library'));
  try{
    const service=new WorkbookService(store);
    const content='<table:table-row>'+text('key')+payloads[1].ods+'</table:table-row>';
    const cases=[
      {title:'moved format',extension:'ods',before:ods(content+'<table:table-row>'+blank(65)+'</table:table-row>'),after:ods('<table:table-row>'+blank(65,'red')+'</table:table-row>'+content),expected:'style'},
      {title:'split cross-format',extension:'xlsx',before:ods('<table:table-row>'+text('key')+blank(65,'paint',true)+'</table:table-row>'),after:xlsxFixture('<sheetData><row r="1"><c r="A1" t="inlineStr"><is><t>key</t></is></c>'+payloads[2].xlsx+'</row></sheetData>'),expected:'cell_observation'},
    ];
    for(const [index,entry]of cases.entries()){
      const before=join(root,index+'-before.ods'),after=join(root,index+'-after.'+entry.extension);await writeFile(before,entry.before);await writeFile(after,entry.after);
      const project=await service.create(entry.title,[{label:'before',path:before},{label:'after',path:after},{label:'restored',path:before}]),stage=await service.run(project.project_id);await service.commit(project.project_id,stage);
      const report=service.report(project.project_id,stage.report_id),query=new WorkbookQueryService(service,new Set([project.project_id])),scope={project_id:project.project_id,report_id:report.report_id};
      const changes=report.changes.filter(c=>c.alignment_method==='physical_blank_content_coordinate');assert.equal(changes.length,entry.expected==='style'?4:2);
      for(const change of changes){
        assert.equal(change.kind,entry.expected);assert.equal(change.association,'needs_review');
        for(const component of ['before','after']){
          const details=await query.query('get_workbook_change',{...scope,change_id:change.change_id,component,max_output_tokens:8000}),item=details.items[0];
          assert.equal(item.association,'needs_review');assert.equal(item.alignment_method,'physical_blank_content_coordinate');assert.equal(item.before_observation,'available');assert.equal(item.after_observation,'available');assert.equal(item[component].address,change.before_address);assert.ok(item[component].source_ref);
        }
      }
      const interval={...scope,from_revision_occurrence_id:report.revisions[0].revision_occurrence_id,to_revision_occurrence_id:report.revisions[2].revision_occurrence_id,max_output_tokens:8000};
      assert.equal((await query.query('list_workbook_changes',{...interval,mode:'range_net'})).total,0);
      assert.equal((await query.query('list_workbook_changes',{...interval,mode:'history'})).total,report.changes.length);
    }
  }finally{store.close();await rm(root,{recursive:true,force:true});}
});
