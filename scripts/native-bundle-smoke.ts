import {mkdtemp,mkdir,writeFile,readFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {spawn} from 'node:child_process';
import {randomUUID,createHash} from 'node:crypto';
import assert from 'node:assert/strict';
import {Client} from '@modelcontextprotocol/sdk/client/index.js';
import {StdioClientTransport} from '@modelcontextprotocol/sdk/client/stdio.js';
import {makePptx,makePdf} from './generate-fixtures.js';
import {byteHash} from '../packages/schema/index.js';
import type {QueryResult} from '../packages/query/index.js';

// Own synthetic input only. Runs the actual packaged model/actions and rendered
// native sheets, then a second process and read-only MCP. This is not OS input.
const output=resolve(process.argv[2]??'output/native-bundle'),userData=await mkdtemp(join(tmpdir(),'docver-native-bundle-')),fixtures=join(userData,'fixtures');await mkdir(output,{recursive:true});await mkdir(fixtures);
const revisions=[],large=process.argv.includes('--large'),pageCount=large?300:2;
for(const index of [0,1]){
 const slides=[{key:'alpha',title:'Alpha revenue',body:`Revenue ${index?120:100} million`,notes:'Independent PPTX notes retained'},{key:'bravo',title:'Bravo staff',body:'Staff 200 employees'},...Array.from({length:pageCount-2},(_,i)=>({key:`topic_${i+3}`,title:`Topic ${String(i+3).padStart(4,'0')}`,body:`Bundle reference ${createHash('sha256').update(String(i+3)).digest('hex').slice(0,48)}`}))],pptx=join(fixtures,`v${index+1}.pptx`),pdf=join(fixtures,`v${index+1}.pdf`);await writeFile(pptx,await makePptx(slides));await writeFile(pdf,await makePdf([...slides].reverse()));revisions.push({label:`v${index+1}`,files:[pptx,pdf]});
}
const files=revisions.flatMap(r=>r.files),hashes=async()=>Object.fromEntries(await Promise.all(files.map(async path=>[path,byteHash(await readFile(path))]))),before=await hashes();
async function launch(folder:string,extra:Record<string,unknown>){
 await mkdir(folder,{recursive:true});for(const file of ['result.json','failure.json','process.json'])await rm(join(folder,file),{force:true});const nonce=randomUUID(),request=join(folder,'request.json');await writeFile(request,JSON.stringify({output:folder,smoke_invocation_id:nonce,...extra}));
 const child=spawn(resolve('release/Docver.app/Contents/MacOS/Docver'),[],{cwd:'/',env:{PATH:'/usr/bin:/bin',DOCVER_TEST_USER_DATA:userData,DOCVER_SMOKE_REQUEST:request,DOCVER_SMOKE_OUTPUT:join(folder,'failure.json')},stdio:['ignore','pipe','pipe']});let stdout='',stderr='';child.stdout.on('data',d=>stdout+=d);child.stderr.on('data',d=>stderr+=d);
 const code=await new Promise<number|null>((res,rej)=>{const timer=setTimeout(()=>{child.kill('SIGKILL');rej(Error('Native bundle app timeout'));},180000);child.on('error',rej);child.on('exit',c=>{clearTimeout(timer);res(c);});});await writeFile(join(folder,'process.json'),JSON.stringify({code,userData,stdout,stderr,interaction_scope:'production model/actions and rendered native sheets; not OS input'},null,2));assert.equal(code,0,stderr);
 let failure:unknown;try{failure=JSON.parse(await readFile(join(folder,'failure.json'),'utf8'));}catch(e){if((e as NodeJS.ErrnoException).code!=='ENOENT')throw e;}assert.equal(failure,undefined,JSON.stringify(failure));const result=JSON.parse(await readFile(join(folder,'result.json'),'utf8'));assert.equal(result.smoke_invocation_id,nonce);assert.equal(result.error,'');return result;
}
const result=await launch(output,{bundle_revisions:revisions,bundle_mapping_checks:true,...(large?{bundle_sheet_page:240}:{})});assert.deepEqual(result.pages,[pageCount,pageCount]);const checks=result.bundle_mapping_checks;
for(const key of ['native_context_contract','native_sheet_cancel_no_write','stale_write_rejected','source_and_pdf_preview_authority','displaced_source_stays_unlinked','append_only_link_unlink_relink','old_snapshot_unchanged'])assert.equal(checks[key],true,key);assert.equal(checks.reopen_history_count,3);
const database=join(userData,'library/docver.sqlite'),databaseBefore=byteHash(await readFile(database)),config=JSON.parse(result.mcp_config).mcpServers.docver,client=new Client({name:'native-bundle-validator',version:'1.0.0'}),transport=new StdioClientTransport({...config,env:{PATH:'/usr/bin:/bin'},stderr:'pipe'});await client.connect(transport);
try{
 const tools=await client.listTools();assert.ok(tools.tools.some(t=>t.name==='list_bundle_decisions'));assert.ok(!tools.tools.some(t=>t.name==='bundleMapping'));
 const scope={project_id:result.project_id,report_id:result.report_id,revision_id:checks.revision_occurrence_id,max_output_tokens:8000},items:Record<string,unknown>[]=[];let cursor:string|undefined;
 do{const response=await client.callTool({name:'list_bundle_decisions',arguments:{...scope,...(cursor?{cursor}:{})}});assert.notEqual(response.isError,true);const page=response.structuredContent as QueryResult;items.push(...page.items);cursor=page.next_cursor??undefined;}while(cursor);
 assert.equal(items.length,3);assert.equal(items[0].reason,checks.verbatim_first_reason);assert.deepEqual(items.map(d=>d.action),['link','unlink','link']);
 const old=await client.callTool({name:'get_report',arguments:{project_id:result.project_id,report_id:checks.original_report_id,max_output_tokens:8000}});assert.notEqual(old.isError,true);assert.equal((old.structuredContent as QueryResult).items[0].truncated,undefined);assert.equal((old.structuredContent as QueryResult).items[0].bundle_decision_count,0);const denied=await client.callTool({name:'list_bundle_decisions',arguments:{...scope,project_id:'foreign_project'}});assert.equal(denied.isError,true);
}finally{await client.close();}
assert.equal(byteHash(await readFile(database)),databaseBefore);const reopened=await launch(join(output,'reopen'),{existing_project_id:result.project_id,existing_report_id:result.report_id});assert.equal(reopened.report_id,result.report_id);assert.deepEqual(reopened.pages,[pageCount,pageCount]);assert.deepEqual(await hashes(),before);
await writeFile(join(output,'validation.json'),JSON.stringify({project_id:result.project_id,report_id:result.report_id,userData,checks,read_only_mcp_history_and_scope:true,sqlite_hash_unchanged_by_mcp:true,second_app_process_reopen:true,original_input_hashes_unchanged:true,original_input_hashes:before},null,2));console.log(JSON.stringify({output,userData,checks,read_only_mcp_history_and_scope:true,second_app_process_reopen:true},null,2));
