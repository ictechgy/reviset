import { parseArgs } from 'node:util';
import { readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { Store } from '../../packages/storage/index.js';
import { Manifest, DocverError } from '../../packages/schema/index.js';
import { analyze } from '../../packages/engine/index.js';
import { QueryService, querySchemas, type QueryName } from '../../packages/query/index.js';
import { exportReport } from '../../packages/export/index.js';
import { renderPdf, convertPptx } from '../../packages/render/index.js';
const {positionals,values}=parseArgs({allowPositionals:true,strict:true,options:{store:{type:'string',default:'.docver'},manifest:{type:'string'},project:{type:'string'},report:{type:'string',default:'latest'},out:{type:'string'},tool:{type:'string'},args:{type:'string',default:'{}'},file:{type:'string'},page:{type:'string',default:'1'},converter:{type:'string'}}});
const command=positionals[0];
let store:Store|undefined;
try {
  if(command==='analyze') {
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
    console.log(`Document Version Tracker — first implementation checkpoint\n\nCommands:\n  npm run fixtures\n  npm run cli -- analyze --manifest tests/fixtures/generated/forward/manifest.json\n  npm run cli -- query --project prj_forward --tool list_changes --args '{"kind":"text_modified"}'\n  npm run cli -- export --project prj_forward --out artifacts/forward\n  npm run cli -- preview --file example.pdf --out preview.png\n  npm run mcp -- --store .docver --project prj_forward\n\nUse revision_occurrence_id when the same revision appears multiple times. No LLM account is required.`);
  }
} catch(e) {console.error(JSON.stringify({code:e instanceof DocverError?e.code:'COMMAND_FAILED',message:(e as Error).message}));process.exitCode=1;}
finally {store?.close();}
