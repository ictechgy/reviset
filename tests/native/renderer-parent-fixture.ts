import {runTool} from '../../packages/runtime/tools.js';
const [guard,probe,folder,policy]=process.argv.slice(2);
await runTool(guard,[folder,'/usr/bin/sandbox-exec','-p',policy,probe,'wait',folder,'',''],{inheritEnv:false,env:{PATH:'/usr/bin:/bin',HOME:folder,TMPDIR:folder},timeout:10000});
