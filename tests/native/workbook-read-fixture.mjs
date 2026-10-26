import {appendFileSync,readFileSync} from 'node:fs';
import {join} from 'node:path';
import {createHash} from 'node:crypto';

const root=process.argv[process.argv.indexOf('--root')+1];
let input='';
process.stdin.setEncoding('utf8');
process.stdin.on('data',s=>input+=s);
process.stdin.on('end',()=>{
  const {action,args}=JSON.parse(input);
  const control=JSON.parse(readFileSync(join(root,'control.json'),'utf8'));
  const query=args.args??args;
  let value,error;
  function observedCell(scope,row,column) {
    let label='',n=column;
    while(n>0){n--;label=String.fromCharCode(65+n%26)+label;n=Math.floor(n/26);}
    return {address:label+row,row,column,value:`${control.value??'fresh'}:${scope.revision_occurrence_id}:${scope.sheet_id}:${label+row}`,formula:null,number_format:'General'};
  }
  if(action==='changes'||action==='changeDetail') {
    const scope={project_id:args.project_id,report_id:args.report_id,from:args.from,to:args.to,mode:args.mode,...(args.kind?{kind:args.kind}:{}),...(args.text?{text:args.text}:{})};
    const query_id=createHash('sha256').update(JSON.stringify(scope)).digest('hex');
    const rows=(control.document_changes??[]).filter(change=>(!args.kind||change.kind===args.kind)&&(!args.text||((change.before??'')+' '+(change.after??'')).toLowerCase().includes(args.text.toLowerCase()))&&(args.from!=='occ_b'||change.from_occurrence==='occ_b'));
    if(action==='changes') {
      const offset=args.cursor?Number(args.cursor):0,items=rows.slice(offset,offset+100).map(change=>({...change,before:change.before===null?null:change.before.slice(0,180),after:change.after===null?null:change.after.slice(0,180),evidence:change.evidence.slice(0,8),summary_preview:true,detail_required:true}));
      value={...scope,query_id,items,next_cursor:offset+100<rows.length?String(offset+100):null,total_count:rows.length};
    } else {
      const change=rows.find(change=>change.change_id===args.change_id);if(!change)throw new Error('Unknown document fixture event');
      const serialized=JSON.stringify(change),offset=args.detail_offset??0;let end=Math.min(offset+128*1024,serialized.length);if(end<serialized.length&&/[\uDC00-\uDFFF]/.test(serialized[end]))end--;
      value={...scope,query_id,change_id:args.change_id,detail_offset:offset,json_length:serialized.length,json_chunk:serialized.slice(offset,end),content_sha256:createHash('sha256').update(serialized).digest('hex'),next_detail_offset:end<serialized.length?end:null};
      if(control.mode==='document-wrong-detail')value.report_id='foreign';
    }
  } else if((action==='create'||action==='workbookCreate')&&control.mode==='import-gate') value={project_id:'fixture-created-'+action};
  else if(action==='workbookAnalyze'&&control.mode==='import-gate') error={code:'CONTROLLED_IMPORT_ANALYSIS_STOP',message:'controlled fixture stops after accepted import submission'};
  else if(action==='workbookReports'&&control.mode==='import-gate') value=[];
  else if(action==='workbookProjects'||action==='workbookReleases') value=[];
  else if(action==='workbookView'&&control.report_fixture) value=control.report_fixture;
  else if(action==='workbookGrid') {
    value={...args,items:[control.scoped_cells===true?observedCell(args,args.row_start,args.column_start):{address:'A2',row:2,column:1,value:control.value??'fresh'}]};
    if(control.mode==='grid-fail') error={code:'CONTROLLED_GRID_FAILURE',message:'controlled range read failure'};
  } else if(action==='workbookQuery'&&args.name==='list_workbook_changes') {
    value={...query,items:control.value==='nonempty'?[{change_id:'change'}]:[],total:control.value==='nonempty'?1:0,next_cursor:null};
    // Opt-in bounded pagination for source-selection regressions. Existing
    // response/failure modes retain their original default fixture behavior.
    if(control.pages!==undefined || control.changes!==undefined) {
      const pages=control.pages??[control.changes];
      if(!Array.isArray(pages)||pages.length<1||pages.length>3||pages.some(page=>!Array.isArray(page)||page.length>100))throw new Error('Invalid bounded change pages');
      const index=query.cursor===undefined?0:pages.findIndex((_,i)=>i>0&&query.cursor===`fixture-page-${i+1}`);
      if(index<0)throw new Error('Unexpected fixture change cursor');
      value.items=pages[index];value.total=pages.reduce((sum,page)=>sum+page.length,0);value.next_cursor=index+1<pages.length?`fixture-page-${index+2}`:null;
    }
    if(control.changes_by_mode!==undefined) {
      const map=control.changes_by_mode;
      if(!map||typeof map!=='object'||Array.isArray(map)||Object.keys(map).some(key=>!['history','range_net'].includes(key))||Object.values(map).some(rows=>!Array.isArray(rows)||rows.length>100))throw new Error('Invalid bounded method changes');
      value.items=map[query.mode]??[];value.total=value.items.length;value.next_cursor=null;
    }
    if(control.mode==='changes-limit'&&query.mode==='range_net')error={code:'WORKBOOK_DIFF_LIMIT',message:'controlled net diff limit'};
    if(control.mode!=='changes-supported')value.blank_formatting_comparison='unsupported_across_formats';
    if(control.mode==='changes-fail')error={code:'CONTROLLED_CHANGES_FAILURE',message:'controlled changes read failure'};
    for(const [mode,key] of [['project','project_id'],['report','report_id'],['from','from_revision_occurrence_id'],['to','to_revision_occurrence_id'],['mode','mode']])if(control.mode==='changes-wrong-'+mode)value[key]='foreign';
  } else if(action==='workbookQuery'&&args.name==='get_workbook_cell') {
    const cell=control.scoped_cells===true?observedCell(query,query.row,query.column):{address:'A2',row:2,column:1,value:control.value??'fresh',formula:null,number_format:'General'};
    value={project_id:query.project_id,report_id:query.report_id,revision_occurrence_id:query.revision_occurrence_id,sheet_id:query.sheet_id,availability:'available',items:[cell]};
    if(control.mode==='cell-fail') error={code:'CONTROLLED_CELL_FAILURE',message:'controlled cell read failure'};
    if(control.mode==='missing') {value.availability='not_materialized';value.items=[];}
    if(control.mode==='wrong-project')value.project_id='foreign';
    if(control.mode==='wrong-report')value.report_id='foreign';
    if(control.mode==='bad-second-side'&&query.revision_occurrence_id==='new')value.report_id='foreign';
    if(control.mode==='wrong-revision')value.revision_occurrence_id='foreign';
    if(control.mode==='wrong-sheet')value.sheet_id='foreign';
    if(control.mode==='wrong-address')cell.address='B2';
    if(control.mode==='wrong-row')cell.row=3;
    if(control.mode==='fractional-row')cell.row=2.5;
    if(control.mode==='wrong-column')cell.column=2;
    if(control.mode==='duplicate')value.items=[cell,cell];
    if(control.mode==='absent-available')value.items=[];
    if(control.mode==='present-missing')value.availability='not_materialized';
    if(control.mode==='nonarray-missing') {value.availability='not_materialized';value.items=null;}
    if(control.mode==='unknown-availability')value.availability='unknown';
  } else throw new Error('Unexpected fixture action '+action);
  appendFileSync(join(root,'read-events.jsonl'),JSON.stringify({action,name:args.name,query,mode:control.mode})+'\n');
  if(control.list_delay!==undefined&&(!Number.isInteger(control.list_delay)||control.list_delay<0||control.list_delay>3000))throw new Error('Invalid bounded list delay');
  const delay=action==='changeDetail'?(control.detail_delay??0):action==='workbookQuery'&&args.name==='list_workbook_changes'?(control.list_delay??control.delay??0):(control.delay??0);
  setTimeout(()=>console.log(JSON.stringify({ok:!error,protocol_version:'0.1.0',schema_version:'0.4.0',value,error})),delay);
});
