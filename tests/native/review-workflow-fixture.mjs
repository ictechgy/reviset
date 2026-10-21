import{appendFileSync,readFileSync,writeFileSync}from'node:fs';import{join}from'node:path';
const root=process.argv[process.argv.indexOf('--root')+1],events=join(root,'review-events.jsonl');let input='';process.stdin.setEncoding('utf8');process.stdin.on('data',s=>input+=s);process.stdin.on('end',()=>{
 const {action,args}=JSON.parse(input),project=args.project_id;let value,delay=0,count=0,error;
 if(action==='mcpConfig'){
  const path=join(root,project+'-count');try{count=Number(readFileSync(path,'utf8'));}catch{}count++;writeFileSync(path,String(count));delay=project==='prj_a'&&count<=2?350:10;if(project==='prj_mcp_retry'&&count===1)error={code:'CONTROLLED_MCP_FAILURE',message:'controlled MCP failure'};value=JSON.stringify({mcpServers:{docver:{command:'fixture',args:['--project',project],generation:count}}});
 }else if(action==='projects')value=['a','b'].map(k=>({project_id:'prj_'+k,title:k,last_report_id:'rpt_'+k,dirty:false,revisions:[],mapping_decisions:[],mapping_relations:[],bundle_decision_count:0,draft_hash:'a'.repeat(64)}));
 else if(action==='reports'){delay=project==='prj_a'?350:0;value=[{report_id:'rpt_'+project.slice(4)}];}
 else if(action==='view')value={project_id:project,report_id:'rpt_'+project.slice(4),revisions:[],matches:[]};
 else if(action==='create'){if(args.title==='fail'){delay=150;error={code:'CONTROLLED_CREATE_FAILURE',message:'controlled create failure'};}else value={project_id:'prj_b'};}
 else if(action==='analyze'){delay=150;error={code:'CONTROLLED_RUN_FAILURE',message:'controlled run failure'};}
 else if(action==='recover')value=[];
 else if(action==='changes'){if(project.startsWith('prj_pending'))delay=300;if(args.report_id==='rpt_range_fail')error={code:'CONTROLLED_RANGE_FAILURE',message:'controlled range failure'};value=args.report_id==='rpt_history'?[{change_id:'chg_history',kind:'text_modified',from_occurrence:'occ_b',to_occurrence:'occ_c',evidence:[{revision_occurrence_id:'occ_b',page_id:'page_b'},{revision_occurrence_id:'occ_c',page_id:'page_c'}]}]:[];}
 else throw new Error('Unexpected action '+action);
 appendFileSync(events,JSON.stringify({action,project:action==='create'?'create:'+args.title:project??'',count,event:'started'})+'\n');setTimeout(()=>console.log(JSON.stringify({ok:!error,protocol_version:'0.1.0',schema_version:'0.4.0',value,error})),delay);
});
