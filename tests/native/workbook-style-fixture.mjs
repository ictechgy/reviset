import {appendFileSync,readFileSync} from 'node:fs';
import {join} from 'node:path';

const root=process.argv[process.argv.indexOf('--root')+1];
let input='';process.stdin.setEncoding('utf8');process.stdin.on('data',s=>input+=s);
process.stdin.on('end',()=>{
  const {action,args}=JSON.parse(input),q=args.args,control=JSON.parse(readFileSync(join(root,'control.json'),'utf8'));
  if(action!=='workbookQuery'||args.name!=='get_workbook_cell'||q.component!=='style'||q.limit!==1)throw Error('Unexpected style fixture request');
  const keys=['border.bottom','border.diagonal','border.left','border.right','border.top','fill.background','fill.foreground','fill.pattern','font.name','long.value'];
  const index=q.cursor===undefined?0:Number(q.cursor.replace('key-',''));
  if(!Number.isInteger(index)||index<0||index>=keys.length||q.cursor!==undefined&&q.cursor!==`key-${index}`)throw Error('Unexpected cursor');
  const text=index===8?(q.revision_occurrence_id==='old'?'Calibri':'Arial'):index===9?'😀한글🧑‍💻'.repeat(1600):'same';
  const start=q.text_offset??0;let end=Math.min(text.length,start+4096);if(end<text.length&&/[\uD800-\uDBFF]/.test(text[end-1]))end--;
  const item={key:keys[index],value:text.slice(start,end),text_continuations:{value:{offset:start,next_offset:end<text.length?end:null,total_length:text.length,state:text.length===0?'empty':end<text.length||start>0?'truncated':'complete'}}};
  const value={schema_version:'workbook.1',project_id:q.project_id,report_id:q.report_id,revision_occurrence_id:q.revision_occurrence_id,sheet_id:q.sheet_id,availability:'available',component:'style',items:[item],total:keys.length,next_cursor:index+1<keys.length?`key-${index+1}`:null};
  let error;
  if(control.mode==='fail')error={code:'CONTROLLED_STYLE_FAILURE',message:'controlled style failure'};
  if(control.mode==='missing'){value.availability='not_materialized';value.items=[];value.total=0;value.next_cursor=null;}
  if(control.mode==='empty'){value.items=[];value.total=0;value.next_cursor=null;}
  if(control.mode==='wrong-project')value.project_id='foreign';
  if(control.mode==='wrong-report')value.report_id='foreign';
  if(control.mode==='wrong-revision')value.revision_occurrence_id='foreign';
  if(control.mode==='wrong-sheet')value.sheet_id='foreign';
  if(control.mode==='wrong-component')value.component='cell';
  if(control.mode==='wrong-key')item.key='foreign-property';
  if(control.mode==='bad-offset')item.text_continuations.value.offset++;
  if(control.mode==='bad-next')item.text_continuations.value.next_offset=start;
  if(control.mode==='nonarray')value.items=null;
  if(control.mode==='fractional-total')value.total=10.5;
  if(control.mode==='same-cursor')value.next_cursor=q.cursor;
  if(control.mode==='complete-short'){item.value='A';item.text_continuations.value={offset:0,next_offset:null,total_length:100,state:'complete'};}
  if(control.mode==='complete-next')item.text_continuations.value.next_offset=end;
  if(control.mode==='empty-nonempty')item.text_continuations.value.state='empty';
  if(control.mode==='truncated-missing-next'){item.value='A';item.text_continuations.value={offset:0,next_offset:null,total_length:100,state:'truncated'};}
  if(control.mode==='truncated-full-initial')item.text_continuations.value.state='truncated';
  if(control.mode==='missing-next')delete item.text_continuations.value.next_offset;
  if(control.mode==='empty-value'){item.value='';item.text_continuations.value={offset:0,next_offset:null,total_length:0,state:'empty'};}

  appendFileSync(join(root,'style-events.jsonl'),JSON.stringify({q,mode:control.mode})+'\n');
  setTimeout(()=>console.log(JSON.stringify({ok:!error,protocol_version:'0.1.0',schema_version:'0.4.0',value,error})),control.delay??0);
});
