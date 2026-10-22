import { parseArgs } from 'node:util';
import { readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { Store } from '../../packages/storage/index.js';
import { Manifest, DocverError } from '../../packages/schema/index.js';
import { analyze } from '../../packages/engine/index.js';
import { QueryService, querySchemas, type QueryName } from '../../packages/query/index.js';
import { exportReport } from '../../packages/export/index.js';
import { renderPdf, convertPptx } from '../../packages/render/index.js';
import { handleWorkbookAction } from '../bridge/workbook.js';
const {positionals,values}=parseArgs({allowPositionals:true,strict:true,options:{store:{type:'string',default:'.docver'},manifest:{type:'string'},project:{type:'string'},report:{type:'string',default:'latest'},out:{type:'string'},tool:{type:'string'},args:{type:'string',default:'{}'},file:{type:'string'},page:{type:'string',default:'1'},converter:{type:'string'}}});
const command=positionals[0];
let store:Store|undefined;
try {
  if(command==='workbook-analyze') {
    if(!values.manifest)throw new Error('--manifest is required');
    const path=resolve(values.manifest),input=JSON.parse(await readFile(path,'utf8'));
    if(!input||typeof input.title!=='string'||!Array.isArray(input.revisions))throw new DocverError('INVALID_INPUT','Workbook manifest requires title and revisions');
    const revisions=input.revisions.map((r:any)=>({label:r.label,path:typeof r.path==='string'?resolve(dirname(path),r.path):r.path,expected_sha256:r.expected_sha256}));
    store=new Store(values.store);const project=await handleWorkbookAction(store,'workbookCreate',{title:input.title,revisions});
    if(!project||typeof project!=='object'||!('project_id' in project)||typeof project.project_id!=='string')throw new DocverError('WORKBOOK_PROTOCOL','Workbook creation response is invalid');
    const staged=await handleWorkbookAction(store,'workbookAnalyze',{project_id:project.project_id});
    console.log(JSON.stringify(await handleWorkbookAction(store,'workbookCommit',{project_id:project.project_id,result:staged}),null,2));
  }else if(command==='workbook-query'||command==='workbook-export') {
    if(!values.project)throw new Error('--project is required');
    if(command==='workbook-export'&&!values.out)throw new Error('--out is required');
    store=new Store(values.store,command==='workbook-query');
    const result=command==='workbook-query'?await handleWorkbookAction(store,'workbookQuery',{name:values.tool??'get_workbook_report',args:{...JSON.parse(values.args),project_id:values.project,report_id:values.report}}):
      await handleWorkbookAction(store,'workbookExport',{project_id:values.project,report_id:values.report,folder:values.out?resolve(values.out):undefined});
    console.log(JSON.stringify(result,null,2));
  }else if(command==='analyze') {
    if(!values.manifest)throw new Error('--manifest is required');
    const path=resolve(values.manifest),manifest=Manifest.parse(JSON.parse(await readFile(path,'utf8')));
    store=new Store(values.store);const controller=new AbortController();process.once('SIGINT',()=>controller.abort());
    const {report,analysis_run_id}=await analyze(manifest,dirname(path),store,controller.signal);
    console.log(JSON.stringify({analysis_run_id,report_id:report.report_id,project_id:report.project_id,revisions:report.revisions.map(r=>({label:r.label,status:r.status,errors:r.errors})),changes:report.changes.length,coverage_gaps:report.coverage_gaps.length},null,2));
    if(report.revisions.some(r=>r.status!=='success'))process.exitCode=2;
  } else if(command==='query'||command==='export') {
    if(!values.project)throw new Error('--project is required');
    store=new Store(values.store,true);const service=new QueryService(store,new Set([values.project]));
    if(command==='export') {
      if(!values.out)throw new Error('--out is required');console.log(JSON.stringify({report_id:await exportReport(service,values.project,values.report,resolve(values.out)),output:resolve(values.out)}));
    } else {
      const tool=values.tool??'get_report';if(!(tool in querySchemas))throw new Error('Unknown query tool');
      const args=JSON.parse(values.args);
      console.log(JSON.stringify(service.query(tool as QueryName,{...args,...(tool!=='list_projects'?{project_id:values.project}:{}),...(!['list_projects','list_reports'].includes(tool)?{report_id:values.report}:{})}),null,2));
    }
  } else if(command==='preview') {
    if(!values.file||!values.out)throw new Error('--file and --out are required');
    const bytes=values.file.toLowerCase().endsWith('.pptx')?await convertPptx(values.file,values.converter):await readFile(values.file);
    await writeFile(values.out,await renderPdf(bytes,Number(values.page)));console.log(JSON.stringify({preview:values.out}));
  } else {
    console.log(`Reviset — document and spreadsheet history\n\nCommands:\n  npm run fixtures\n  npm run cli -- analyze --manifest tests/fixtures/generated/forward/manifest.json\n  npm run cli -- query --project prj_forward --tool list_changes --args '{"kind":"text_modified"}'\n  npm run cli -- export --project prj_forward --out artifacts/forward\n  npm run cli -- preview --file example.pdf --out preview.png\n  npm run cli -- workbook-analyze --manifest workbook-manifest.json\n  npm run cli -- workbook-query --project wprj_ID --tool list_workbook_revisions\n  npm run cli -- workbook-export --project wprj_ID --out artifacts/workbook\n  npm run mcp -- --store .docver --project prj_forward\n\nUse revision_occurrence_id when the same revision appears multiple times. No LLM account is required.`);
  }
} catch(e) {console.error(JSON.stringify({code:e instanceof DocverError?e.code:'COMMAND_FAILED',message:(e as Error).message}));process.exitCode=1;}
finally {store?.close();}
