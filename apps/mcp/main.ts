import { parseArgs } from 'node:util';
import { Store } from '../../packages/storage/index.js';
import { QueryService } from '../../packages/query/index.js';
import { serveMcp } from './server.js';
const {values}=parseArgs({options:{store:{type:'string',default:'.docver'},project:{type:'string',multiple:true}},strict:true});
if(!values.project?.length) {console.error('MCP requires at least one explicit --project ID');process.exit(2);}
const store=new Store(values.store,true);
for(const project of values.project) if(!store.projects().some(p=>p.project_id===project)){console.error('Unknown configured project');store.close();process.exit(2);}
await serveMcp(new QueryService(store,new Set(values.project)));
process.once('SIGINT',()=>{store.close();process.exit(0);});
process.once('SIGTERM',()=>{store.close();process.exit(0);});
