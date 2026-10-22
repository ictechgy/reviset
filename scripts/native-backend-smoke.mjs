import { spawnSync,spawn } from 'node:child_process';
import { mkdtemp,readFile,writeFile,rm,mkdir } from 'node:fs/promises';
import { resolve,join } from 'node:path';
import { tmpdir } from 'node:os';
import { createHash } from 'node:crypto';
import assert from 'node:assert/strict';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';
const app=resolve('release/Reviset.app/Contents'),node=join(app,'Helpers/node'),script=join(app,'Resources/backend/bridge.mjs');
const root=await mkdtemp(join(tmpdir(),'docver-packaged-')),folder=resolve('output/native-backend');await mkdir(folder,{recursive:true});
const env={PATH:'/usr/bin:/bin',HOME:process.env.HOME};
function call(action,args={},expected){const p=spawnSync(node,[script,'--root',root],{cwd:'/',env,input:JSON.stringify({action,args}),encoding:'utf8',timeout:60000,maxBuffer:32*1024*1024});assert.ifError(p.error);const r=JSON.parse(p.stdout);assert.equal(r.protocol_version,'0.1.0');if(expected){assert.equal(r.error?.code,expected);return r;}assert.equal(r.ok,true,JSON.stringify(r.error));return r.value;}
const checks=[];
try{
 const demo=join(app,'Resources/demo/lifecycle-five'),manifest=JSON.parse(await readFile(join(demo,'manifest.json'),'utf8'));
 const p=call('create',{title:'Packaged backend',revisions:manifest.revisions.map(v=>({label:v.label,files:v.files.map(f=>join(demo,f))}))}),project_id=p.project_id;
 const result=call('analyze',{project_id});assert.equal(call('reports',{project_id}).length,0);
 const stage=join(root,'staging-v4',result.staged_name),original=await readFile(stage);await writeFile(stage,'tampered');call('commit',{project_id,result},'STAGED_HASH');await writeFile(stage,original);call('commit',{project_id,result});checks.push('two-phase commit + tamper rejection');
 const report_id=result.report_id,view=call('view',{project_id,report_id}),first=view.revisions[0].pages[0];assert.equal(first.elements,undefined);assert.ok(call('page',{project_id,report_id,page_id:first.page_id}).page.elements.length);checks.push('compact metadata + lazy hashed source');
 const changes=call('changes',{project_id,report_id,mode:'history'});assert.equal(changes.filter(c=>c.kind==='text_modified').length,2);
 const target=join(root,'export');call('export',{project_id,report_id,folder:target});const full=JSON.parse(await readFile(join(target,'report.json'),'utf8'));assert.deepEqual(full.changes.map(c=>c.change_id),changes.map(c=>c.change_id));checks.push('export/query parity');
 const second=call('analyze',{project_id});call('recover',{run_id:second.analysis_run_id});await writeFile(join(root,'staging-v4',second.staged_name),original);call('commit',{project_id,result:second},'INVALID_RUN');checks.push('cancel/recovery cannot commit');
 const third=call('analyze',{project_id});call('reorder',{project_id,order:[4,3,2,1,0]});call('commit',{project_id,result:third},'STALE_RUN');call('recover',{run_id:third.analysis_run_id});assert.equal(call('reports',{project_id}).length,1);assert.equal(call('view',{project_id,report_id}).report_id,report_id);checks.push('stale draft rejection + immutable past report');
 const fourth=call('analyze',{project_id});call('commit',{project_id,result:fourth});assert.notEqual(fourth.report_id,report_id);assert.equal(call('reports',{project_id}).length,2);checks.push('reorder makes new snapshot');
 const config=JSON.parse(call('mcpConfig',{project_id})).mcpServers.reviset;assert.equal(config.command,node);
 const db=join(root,'docver.sqlite'),digest=async()=>createHash('sha256').update(await readFile(db)).digest('hex');
 const before=await digest(),transport=new StdioClientTransport({...config,env,stderr:'pipe'}),client=new Client({name:'native-packaged-smoke',version:'1.0.0'});
 await client.connect(transport);try{const r=await client.callTool({name:'get_report',arguments:{project_id,report_id}});assert.equal(r.isError,undefined);const denied=await client.callTool({name:'get_report',arguments:{project_id:'prj_other',report_id}});assert.equal(denied.isError,true);}finally{await client.close();}
 assert.equal(await digest(),before);checks.push('packaged read-only MCP + project scope + SQLite hash');
 // Terminate actual packaged compute after its first progress event, then recover.
 const child=spawn(node,[script,'--root',root],{cwd:'/',env,stdio:['pipe','pipe','pipe']});let stopped=false;child.stderr.on('data',d=>{if(!stopped&&String(d).includes('progress')){stopped=true;child.kill('SIGTERM');}});child.stdin.end(JSON.stringify({action:'analyze',args:{project_id}}));await new Promise((res,rej)=>{const timer=setTimeout(()=>{child.kill('SIGKILL');rej(new Error('cancel test timeout'));},15000);child.on('error',rej);child.on('exit',()=>{clearTimeout(timer);res();});});assert.ok(stopped);call('recover');assert.equal(call('reports',{project_id}).length,2);checks.push('actual compute process termination retains committed reports');
 await writeFile(join(folder,'result.json'),JSON.stringify({checks,project_id,report_id,packaged_runtime:node},null,2));console.log(JSON.stringify({checks,passed:checks.length},null,2));
}finally{await rm(root,{recursive:true,force:true});}
