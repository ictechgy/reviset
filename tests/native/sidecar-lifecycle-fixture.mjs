import {readFileSync,appendFileSync} from 'node:fs';
import {join} from 'node:path';
const library=process.argv[process.argv.indexOf('--root')+1],{action,args}=JSON.parse(readFileSync(0,'utf8'));
const record=event=>appendFileSync(join(library,'sidecar-events.jsonl'),JSON.stringify({event,action,args,pid:process.pid})+'\n');
record('started');
process.once('SIGTERM',()=>{record('cancelled');process.exit(143);});
setTimeout(()=>{record('finished');console.log(JSON.stringify({ok:true,protocol_version:'0.1.0',schema_version:'0.4.0',value:{tag:args.tag??'',closed:action==='sidecarClose'}}));},action==='sidecarCreate'?5000:action==='changes'?300:0);
