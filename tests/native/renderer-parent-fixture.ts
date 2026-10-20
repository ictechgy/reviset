import {writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {runTool} from '../../packages/runtime/tools.js';
const [guard,probe,folder,policy]=process.argv.slice(2);
await runTool(guard,[folder,'/usr/bin/sandbox-exec','-p',policy,probe,'wait',folder,'',''],{supervised:true,onSupervisorPid:pid=>writeFileSync(join(folder,'monitor.json'),JSON.stringify({monitor:pid})),inheritEnv:false,env:{PATH:'/usr/bin:/bin',HOME:folder,TMPDIR:folder},timeout:10000});
