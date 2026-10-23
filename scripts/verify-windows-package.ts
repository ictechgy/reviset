import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {execFileSync} from 'node:child_process';
import {Client} from '@modelcontextprotocol/sdk/client/index.js';
import {StdioClientTransport} from '@modelcontextprotocol/sdk/client/stdio.js';
import {Store} from '../packages/storage/index.js';
import {WorkbookService} from '../packages/workbook/service.js';
import {byteHash} from '../packages/schema/index.js';

if(process.platform!=='win32')throw new Error('Actual Windows package verification requires Windows');
const bundle=resolve(process.argv[2]??'release/Reviset-Windows-x64'),output=resolve(process.argv[3]??'artifacts/windows-native');
const smoke=JSON.parse(await readFile(join(output,'result.json'),'utf8'));
assert.equal(smoke.passed,true);const library=join(output,'profile/library');
assert.equal(resolve(smoke.library),resolve(library));
const info=JSON.parse(await readFile(join(bundle,'build-info.json'),'utf8')),node=join(bundle,'runtime/node.exe'),server=join(bundle,'backend/mcp.mjs');
assert.equal(info.source_dirty,false);if(process.env.GITHUB_SHA)assert.equal(info.source_head,process.env.GITHUB_SHA);
assert.equal(byteHash(await readFile(node)),info.node.sha256);assert.equal(execFileSync(node,['--version'],{encoding:'utf8'}).trim(),'v'+info.node.version);
const database=join(library,'docver.sqlite'),before=byteHash(await readFile(database));
const store=new Store(library,true),workbooks=new WorkbookService(store);
const checks:unknown[]=[];
try {
  for(const kind of ['document','workbook'] as const){
    const project=String(smoke[kind+'_project_id']),reportId=String(smoke[kind+'_report_id']);assert.notEqual(reportId,'latest');
    const config=JSON.parse(await readFile(join(output,kind+'-mcp.json'),'utf8')).mcpServers.reviset;
    assert.equal(resolve(config.command),node);assert.deepEqual(config.args,[server,'--store',library,'--project',project]);
    const transport=new StdioClientTransport({command:config.command,args:config.args,stderr:'pipe'}),client=new Client({name:'reviset-windows-qualification',version:'1.0.0'});
    await client.connect(transport);
    try{
      const tools=(await client.listTools()).tools;assert.ok(tools.length>10);assert.ok(tools.every(t=>t.annotations?.readOnlyHint===true));assert.ok(!tools.some(t=>/create|commit|execute|publish|export|analy[sz]e/u.test(t.name)));
      let rawItems=0;
      const invoke=async(name:string,args:Record<string,unknown>)=>{
        const result=await client.callTool({name,arguments:{project_id:project,report_id:reportId,max_output_tokens:8000,...args}});assert.notEqual(result.isError,true,JSON.stringify(result));return result.structuredContent as Record<string,any>;
      };
      if(kind==='document'){
        const report=store.report(project,reportId);
        for(const revision of report.revisions)for(const page of revision.pages){
          const result=await invoke('get_page_content',{revision_id:revision.revision_occurrence_id,page_id:page.page_id,section:'source',text_length:1000});
          assert.equal(result.report_id,reportId);assert.equal(result.items[0].text,page.text);rawItems++;
        }
        const changes=await invoke('list_changes',{mode:'history'});assert.ok(changes.items.length>0);
      }else{
        const report=workbooks.report(project,reportId);
        for(const revision of report.revisions)for(const sheet of revision.sheets)for(const cell of sheet.cells.slice(0,50)){
          const args={revision_occurrence_id:revision.revision_occurrence_id,sheet_id:sheet.sheet_id,row:cell.row,column:cell.column,text_length:4096};
          for(const field of ['value','formula'] as const){
            let offset=0,reconstructed='';const seen=new Set<number>();
            while(true){
              assert.ok(!seen.has(offset),'MCP continuation must advance');seen.add(offset);
              const result=await invoke('get_workbook_cell',{...args,text_offset:offset});assert.equal(result.report_id,reportId);
              const item=result.items[0],part=item[field],continuation=item.text_continuations[field];
              if(cell[field]===null){assert.equal(part,null);break;}
              assert.equal(part,cell[field]!.slice(continuation.offset,continuation.offset+part.length));
              assert.ok(continuation.offset<=reconstructed.length,'MCP source continuation skipped a range');
              reconstructed=reconstructed.slice(0,continuation.offset)+part;
              if(continuation.next_offset===null)break;
              assert.ok(continuation.next_offset>offset);offset=continuation.next_offset;
            }
            if(cell[field]!==null)assert.equal(reconstructed,cell[field]);
          }
          rawItems++;
        }
      }
      const denied=await client.callTool({name:kind==='document'?'get_report':'get_workbook_report',arguments:{project_id:'foreign_project',report_id:reportId,max_output_tokens:8000}});assert.equal(denied.isError,true);assert.match(JSON.stringify(denied),/PROJECT_SCOPE/u);
      checks.push({kind,project_id:project,report_id:reportId,raw_items:rawItems,read_only_tools:tools.length,foreign_scope_denied:true});
    }finally{await client.close();await transport.close();}
  }
}finally{store.close();}
assert.equal(byteHash(await readFile(database)),before,'Bundled MCP reads changed SQLite bytes');
const result={passed:true,source_head:info.source_head,bundled_node:info.node,database_sha256:before,checks};
await writeFile(join(output,'bundled-mcp-result.json'),JSON.stringify(result,null,2)+'\n');console.log(JSON.stringify(result));
