import { parseArgs } from 'node:util';
import { Store } from '../../packages/storage/index.js';
import { QueryService } from '../../packages/query/index.js';
import { serveMcp } from './server.js';
import { WorkbookService } from '../../packages/workbook/service.js';
const {values}=parseArgs({options:{store:{type:'string',default:'.docver'},project:{type:'string',multiple:true}},strict:true});
if(!values.project?.length) {console.error('MCP requires at least one explicit --project ID');process.exit(2);}
const store=new Store(values.store,true);
const documentIds=new Set(store.projects().map(p=>p.project_id)),workbooks=new WorkbookService(store),workbookIds=new Set(workbooks.projects().map(p=>p.project_id));
for(const project of values.project) if(!documentIds.has(project)&&!workbookIds.has(project)){console.error('Unknown configured project');store.close();process.exit(2);}
await serveMcp(new QueryService(store,new Set(values.project.filter(p=>documentIds.has(p)))),new Set(values.project.filter(p=>workbookIds.has(p))));
process.once('SIGINT',()=>{store.close();process.exit(0);});
process.once('SIGTERM',()=>{store.close();process.exit(0);});
