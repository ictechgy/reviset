import {appendFileSync,readFileSync,writeFileSync} from 'node:fs';
import {join} from 'node:path';
const root=process.argv[process.argv.indexOf('--root')+1];
let input='';
process.stdin.setEncoding('utf8');process.stdin.on('data',part=>input+=part);
process.stdin.on('end',()=>{
  const {action,args={}}=JSON.parse(input);
  let control={};try{control=JSON.parse(readFileSync(join(root,'control.json'),'utf8'));}catch{}
  const mode=control.mode??'ok',project=args.project_id??'project',run='run_'+mode;
  const revisions=['a','b','c'].map(k=>({revision_occurrence_id:'occ_'+k,label:k,assets:[{asset_id:'asset_'+k,format:'pdf'}],pages:[1,2].map(n=>({page_id:'page_'+k+n,asset_id:'asset_'+k,page:n}))}));
  const workbookRevisions=['old','new'].map((k,index)=>({revision_occurrence_id:k,index,label:k,sheets:[{sheet_id:'sheet-'+k,name:'Sheet',row_count:100,column_count:12}]}));
  let value,error,delay=control.delayAction===action?250:0;
  appendFileSync(join(root,'reliability-events.jsonl'),JSON.stringify({mode,action,args})+'\n');
  if(action==='projects')value=[{project_id:'project',last_report_id:'retained',revisions:[]}];
  else if(action==='reports')value=[{report_id:'retained'},{report_id:'saved_'+mode}];
  else if(action==='view')value={project_id:project,report_id:args.report_id,revisions,matches:[],quality_counts:{}};
  else if(action==='changes')value={project_id:args.project_id,report_id:args.report_id,query_id:'a'.repeat(64),items:[],next_cursor:null,total_count:0};
  else if(action==='create')value={project_id:'created-input'};
  else if(action==='recover'){
    if(!args.run_id)error={code:'CLEANUP_FAILURE',message:'controlled startup staging cleanup failure'};
    else value=[];
  }else if(action==='workbookRecover')value=[];
  else if(action==='sidecarRecover')value={skipped:0};
  else if(action==='analyze'){
    if(mode!=='unowned-failure')process.stderr.write(JSON.stringify({event:'progress',progress:{analysis_run_id:run,phase:'extract',current:0,total:1}})+'\n');
    if(mode==='owned-failure'||mode==='unowned-failure'){delay=40;error={code:'ANALYZE_FAILURE',message:'controlled analyze failure'};}
    else value={analysis_run_id:run,project_id:project,report_id:'staged_'+mode};
  }else if(action==='commit'){
    if(mode==='cleanup'||mode==='superseded-cleanup'){value={report_id:'saved_'+mode,status:'complete',cleanup_pending:true};if(mode==='superseded-cleanup')delay=300;}
    else if(mode==='normal')value={report_id:'saved_'+mode,status:'complete',cleanup_pending:false};
    else if(mode==='superseded-unknown'){setTimeout(()=>process.exit(71),300);return;}
    else process.exit(71); // Simulate a reply lost after the commit boundary.
  }else if(action==='runStatus'){
    if(mode==='unknown'||mode==='superseded-unknown')error={code:'STATUS_UNAVAILABLE',message:'controlled run status unavailable'};
    else value={project_id:mode==='wrong-scope'?'foreign':project,analysis_run_id:args.analysis_run_id,status:mode==='noncommitted'?'running':mode==='partial'?'partial':'success',report_id:mode==='noncommitted'?null:'saved_'+mode,cleanup_pending:mode==='lost-cleanup'};
  }else if(action==='workbookProjects')value=[];
  else if(action==='workbookReports')value=[{report_id:'workbook-report'}];
  else if(action==='workbookView')value={project_id:project,report_id:args.report_id,revisions:workbookRevisions,coverage_gaps:[]};
  else if(action==='workbookGrid')value={...args,items:[{address:'A2',row:2,column:1,value:mode}]};
  else if(action==='workbookReleases')value=[];
  else if(action==='workbookMcpConfig')value='fixture config';
  else if(action==='workbookQuery'){
    const q=args.args;
    if(args.name==='get_workbook_cell')value={...q,availability:'available',items:[{address:'A2',row:2,column:1,value:mode}]};
    else if(args.name==='get_workbook_cell_history')value={items:[{revision_occurrence_id:'new',address:'A2',value:mode}],total:1,next_cursor:null};
    else value={...q,items:[{change_id:'change',from_revision_occurrence_id:'old',to_revision_occurrence_id:'new'}],total:1,next_cursor:null};
    if(control.delayQuery===args.name)delay=250;
  }else if(action==='workbookCreate'){
    // The following reads use fresh data after the interrupted request ends.
    writeFileSync(join(root,'control.json'),JSON.stringify({mode:'restored'}));
    delay=control.createDelay??0;error={code:'SOURCE_CHANGED',message:'The selected input changed before import.'};
  }else throw new Error('Unexpected action '+action);
  setTimeout(()=>console.log(JSON.stringify({ok:!error,protocol_version:'0.1.0',schema_version:'0.4.0',value,error})),delay);
});
