import {appendFileSync,readFileSync} from 'node:fs';
import {join} from 'node:path';

const root=process.argv[process.argv.indexOf('--root')+1];
let input='';
process.stdin.setEncoding('utf8');
process.stdin.on('data',s=>input+=s);
process.stdin.on('end',()=>{
  const {action,args}=JSON.parse(input);
  const control=JSON.parse(readFileSync(join(root,'control.json'),'utf8'));
  const query=args.args??args;
  let value,error;
  if(action==='workbookProjects') value=[];
  else if(action==='workbookGrid') {
    value={...args,items:[{address:'A2',row:2,column:1,value:control.value??'fresh'}]};
    if(control.mode==='grid-fail') error={code:'CONTROLLED_GRID_FAILURE',message:'controlled range read failure'};
  } else if(action==='workbookQuery'&&args.name==='get_workbook_cell') {
    const cell={address:'A2',row:2,column:1,value:control.value??'fresh',formula:null,number_format:'General'};
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
  appendFileSync(join(root,'read-events.jsonl'),JSON.stringify({action,query,mode:control.mode})+'\n');
  setTimeout(()=>console.log(JSON.stringify({ok:!error,protocol_version:'0.1.0',schema_version:'0.4.0',value,error})),control.delay??0);
});
