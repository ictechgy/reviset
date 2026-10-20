import { McpServer, ResourceTemplate } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { QueryService, querySchemas, Envelope, type QueryName } from '../../packages/query/index.js';
import { DocverError } from '../../packages/schema/index.js';
import { ZodError } from 'zod';
import { MCP_API_VERSION, mcpInstructions, registerReadingPrompts, toolDescriptions } from './guidance.js';
export function createMcpServer(service:QueryService):McpServer {
  const server=new McpServer({name:'document-version-tracker',version:MCP_API_VERSION},{instructions:mcpInstructions});
  for(const [name,schema] of Object.entries(querySchemas)) server.registerTool(name,{
    description:toolDescriptions[name as QueryName],
    inputSchema:schema,outputSchema:Envelope,annotations:{readOnlyHint:true,destructiveHint:false,idempotentHint:true,openWorldHint:false}
  },async(args:any)=> {
    try {
      const response=(result:ReturnType<QueryService['query']>)=>({structuredContent:result,content:[{type:'text' as const,text:JSON.stringify(result)}]});
      const result=service.query(name as QueryName,args,result=>Buffer.byteLength(JSON.stringify(response(result))));
      return response(result);
    }
    catch(e) {
      const error=e instanceof DocverError?{code:e.code,message:e.message}:e instanceof ZodError?{code:'INVALID_INPUT',message:'Query input is invalid',issues:e.issues.slice(0,8).map(i=>({path:i.path,code:i.code}))}:{code:'INTERNAL_ERROR',message:'Query failed'};
      return {isError:true,content:[{type:'text' as const,text:JSON.stringify(error)}]};
    }
  });
  const prefix='docver://projects/{project_id}/reports/{report_id}';
  const definitions:[string,string,QueryName,(v:Record<string,any>)=>Record<string,any>][]=[
    ['manifest',prefix+'/manifest','get_report',()=>({})],
    ['page',prefix+'/revisions/{revision_id}/pages/{page_id}','get_page',v=>({revision_id:v.revision_id,page_id:v.page_id})],
    ['page-content',prefix+'/revisions/{revision_id}/pages/{page_id}/content','get_page_content',v=>({revision_id:v.revision_id,page_id:v.page_id})],
    ['page-notes',prefix+'/revisions/{revision_id}/pages/{page_id}/notes','get_page_content',v=>({revision_id:v.revision_id,page_id:v.page_id,section:'notes'})],
    ['change',prefix+'/changes/{change_id}','list_changes',v=>({change_id:v.change_id})],
    ['change-detail',prefix+'/changes/{change_id}/detail','get_change',v=>({change_id:v.change_id})],
    ['coverage',prefix+'/coverage-gaps','list_coverage_gaps',()=>({})],
    ['page-relations',prefix+'/pages/{page_id}/relations','list_page_relations',v=>({page_id:v.page_id})],
    ['entity',prefix+'/entities/{entity_id}','get_entity_history',v=>({entity_id:v.entity_id})],
    ['evidence',prefix+'/evidence/{observation_id}','get_evidence',v=>({observation_id:v.observation_id})]
  ];
  for(const [name,template,query,extra] of definitions) server.registerResource(name,new ResourceTemplate(template,{list:name==='manifest'?async()=>({resources:[...service.allowedProjects].flatMap(project_id=>service.store.reports(project_id).map(r=>({uri:`docver://projects/${project_id}/reports/${r.report_id}/manifest`,name:String(r.report_id),mimeType:'application/json'})))}):undefined}),
    {mimeType:'application/json'},async(uri,variables)=> {
      if(!/^docver:\/\/projects\/[a-zA-Z0-9_-]+\/reports\/[a-zA-Z0-9_-]+\//.test(uri.href)||uri.search||uri.hash||uri.href.includes('%')) throw new DocverError('INVALID_RESOURCE','Only registered internal IDs are accepted');
      const result=service.query(query,{project_id:variables.project_id,report_id:variables.report_id,...extra(variables),max_output_tokens:4000});
      return {contents:[{uri:uri.href,mimeType:'application/json',text:JSON.stringify(result)}]};
    });
  registerReadingPrompts(server,service);
  return server;
}
export async function serveMcp(service:QueryService) { const server=createMcpServer(service);await server.connect(new StdioServerTransport());return server; }
