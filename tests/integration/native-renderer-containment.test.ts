import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,mkdir,readFile,writeFile,rm,lstat,realpath} from 'node:fs/promises';
import {existsSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {execFileSync,spawn} from 'node:child_process';
import {onlyOfficeSidecarPolicy,rethrowSidecarConversionError} from '../../packages/render/onlyoffice-sidecar.js';
import {runTool} from '../../packages/runtime/tools.js';

test('actual renderer guard confines direct IO, broker lookup, signals, resources and cancellation',{skip:process.platform!=='darwin',timeout:30000},async()=>{
  const root=await realpath(await mkdtemp(join(tmpdir(),'docver-render-containment-'))),vendor=join(root,'vendor');
  const owned=new Set<number>(),sentinel=process.env.DOCVER_PARENT_SENTINEL;process.env.DOCVER_PARENT_SENTINEL='public-parent-marker';
  try{
    await mkdir(vendor,{mode:0o700});const probe=join(vendor,'probe');
    execFileSync('clang',['-O2','-Wall','-Wextra','-Werror','-Wno-deprecated-declarations',resolve('tests/native/RendererContainment.c'),'-o',probe],{timeout:10000,stdio:'pipe'});
    execFileSync(process.execPath,['--import','tsx',resolve('scripts/build-renderer-guard.ts')],{timeout:15000,stdio:'pipe'});
    // Read-only bootstrap lookup succeeds outside confinement. A denial inside
    // therefore cannot be explained by an absent broker. No preference is set.
    assert.equal(JSON.parse(execFileSync(probe,['broker-baseline','','',''],{encoding:'utf8'})).mach_result,0);
    const outside=join(root,'unexpected-write'),canary=join(root,'canary');await writeFile(canary,'public synthetic canary');
    // Each wait fixture attempts both escape syscalls before publishing its PID.
    // Thus immediate cancellation/monitor death is synchronized AFTER escape
    // attempts, not a separate escape-only or cleanup-only control.
    const modes=['probe','fsize','aggregate','symlink','output','timeout','escape',...Array.from({length:12},()=>['cancel','supervisor-kill']).flat()];
    for(const [iteration,mode] of modes.entries()){
      const folder=join(root,mode+'-'+iteration);await mkdir(folder,{mode:0o700});const controller=new AbortController(),wait=['cancel','timeout','supervisor-kill','escape'].includes(mode);
      if(mode==='probe')await writeFile(join(folder,'inside-canary'),'Public regular-file canary');
      let monitor=0;
      const pending=runTool(resolve('dist/native/DocverRendererGuard'),[folder,'/usr/bin/sandbox-exec','-p',onlyOfficeSidecarPolicy(folder,vendor,probe),probe,wait&&mode!=='escape'?'wait':mode,folder,outside,canary],{supervised:true,onSupervisorPid:pid=>{monitor=pid;},inheritEnv:false,env:{PATH:'/usr/bin:/bin',HOME:folder,TMPDIR:folder},signal:controller.signal,timeout:mode==='timeout'?1500:10000,maxBytes:1024*1024}).then(stdout=>({stdout,error:undefined}),error=>({stdout:'',error:error as Error&{code:string}}));
      let pids:number[]=[];
      if(wait){for(let i=0;i<100&&!existsSync(join(folder,'pids.json'));i++)await new Promise(r=>setTimeout(r,10));assert.ok(existsSync(join(folder,'pids.json')));const owners=JSON.parse(await readFile(join(folder,'pids.json'),'utf8'));assert.ok(monitor>1);assert.equal(owners.converter,owners.group);assert.equal(owners.converter,owners.session);assert.equal(owners.setpgid_denied,true);assert.equal(owners.setsid_denied,true);pids=[owners.converter,monitor];for(const pid of pids)owned.add(pid);if(mode==='cancel')controller.abort();if(mode==='supervisor-kill')process.kill(monitor,'SIGKILL');}
      const result=await pending;
      if(mode==='probe'){
        assert.ifError(result.error);const observed=JSON.parse(result.stdout);
        for(const key of ['inside_read_allowed','mach_denied','signal_denied','read_denied','write_denied','network_denied','fork_denied','exec_denied','env_absent'])assert.equal(observed[key],true,key);
        assert.equal(observed.mach_result,1100);assert.equal(existsSync(outside),false);
      }else if(mode==='escape'){assert.ifError(result.error);
      }else{
        assert.ok(result.error);
        if(mode==='fsize'){assert.match(String(result.error),/ftruncate_result=-1 errno=27/u);assert.ok((await lstat(join(folder,'big.bin'))).size<=128*1024*1024);}
        if(mode==='aggregate')assert.match(String(result.error),/DOCVER_RESOURCE_LIMIT: Aggregate256MiB/u);
        if(['aggregate','symlink'].includes(mode))assert.throws(()=>rethrowSidecarConversionError(result.error),(error:any)=>error.code==='SIDECAR_LIMIT');
        if(mode==='symlink')assert.match(String(result.error),/DOCVER_RESOURCE_LIMIT: Output symlink refused/u);
        if(mode==='output')assert.equal(result.error.code,'TOOL_OUTPUT_LIMIT');
        if(mode==='cancel')assert.equal(result.error.code,'CANCELLED');
        if(mode==='timeout')assert.equal(result.error.code,'TOOL_TIMEOUT');
      }
      for(const pid of pids){let alive=true;for(let i=0;i<100&&alive;i++){try{process.kill(pid,0);await new Promise(r=>setTimeout(r,10));}catch{alive=false;}}assert.equal(alive,false,'Owned process must terminate');owned.delete(pid);}
    }
    const folder=join(root,'parent-death');await mkdir(folder,{mode:0o700});const owner=spawn(process.execPath,['--import','tsx',resolve('tests/native/renderer-parent-fixture.ts'),resolve('dist/native/DocverRendererGuard'),probe,folder,onlyOfficeSidecarPolicy(folder,vendor,probe)],{stdio:'ignore'});
    try{
      for(let i=0;i<200&&!existsSync(join(folder,'pids.json'));i++)await new Promise(r=>setTimeout(r,10));assert.ok(existsSync(join(folder,'pids.json')));
      const exited=new Promise<void>((resolveExit,reject)=>{owner.once('exit',()=>resolveExit());owner.once('error',reject);});owner.kill('SIGKILL');await exited;
      const pids:number[]=[JSON.parse(await readFile(join(folder,'pids.json'),'utf8')).converter,JSON.parse(await readFile(join(folder,'monitor.json'),'utf8')).monitor];
      for(const pid of pids)owned.add(pid);
      for(const pid of pids){let alive=true;for(let i=0;i<200&&alive;i++){try{process.kill(pid,0);await new Promise(r=>setTimeout(r,10));}catch{alive=false;}}assert.equal(alive,false,'Parent death must terminate guarded descendants');owned.delete(pid);}
    }finally{if(owner.exitCode===null&&owner.signalCode===null)owner.kill('SIGKILL');}
    assert.equal(await readFile(canary,'utf8'),'public synthetic canary');
  }finally{for(const pid of owned)try{process.kill(pid,'SIGKILL');}catch{}if(sentinel===undefined)delete process.env.DOCVER_PARENT_SENTINEL;else process.env.DOCVER_PARENT_SENTINEL=sentinel;await rm(root,{recursive:true,force:true});}
});
