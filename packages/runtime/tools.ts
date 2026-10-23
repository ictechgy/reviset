import { z } from 'zod';
import { spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import { readFile,mkdtemp,rm } from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {nativeHelperLaunch} from './native-isolation.js';
import { dirname,join,resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { byteHash,DocverError } from '../schema/index.js';

const active=new Map<number,()=>void>();
function kill(pid:number,signal:NodeJS.Signals='SIGTERM'){try{process.kill(-pid,signal);}catch{/* already exited */}}
function stop(){for(const cancel of active.values())cancel();}
export function cancelActiveTools(){stop();}
const terminate=()=>stop(),interrupt=()=>stop();
export async function runTool(executable:string,args:string[],options:{input?:string;cwd?:string;timeout?:number;signal?:AbortSignal;maxBytes?:number;env?:NodeJS.ProcessEnv;inheritEnv?:boolean;supervised?:boolean;onSupervisorPid?:(pid:number)=>void}={}):Promise<string>{
  options.signal?.throwIfAborted();
  // The Windows native host owns the engine in a kill-on-close Job Object.
  // This POSIX supervisor has no qualified Windows external-tool adapter;
  // taskkill cannot safely reap a tree whose leader has already exited.
  if(process.platform==='win32')throw new DocverError('TOOL_PLATFORM_UNSUPPORTED','External document processors require a qualified Windows confinement adapter');
  return new Promise((resolveRun,reject)=>{
    const child=spawn(executable,args,{cwd:options.cwd,detached:true,stdio:options.supervised?['pipe','pipe','pipe','pipe']:['pipe','pipe','pipe'],env:{...(options.inheritEnv===false?{}:process.env),SAL_DISABLE_OPENCL:'1',...options.env}});
    const output={chunks:[] as Buffer[],bytes:0},diagnostic={chunks:[] as Buffer[],bytes:0};let failure:Error|undefined;
    let status='',monitor:number|undefined,monitorOK=!options.supervised;
    const abort=(error:Error)=>{if(failure)return;failure=error;if(child.pid)kill(child.pid,'SIGKILL');};
    const cancelled=()=>abort(new DocverError('CANCELLED','Local document processing cancelled'));
    if(child.pid){if(!active.size){process.once('SIGTERM',terminate);process.once('SIGINT',interrupt);}active.set(child.pid,cancelled);}
    options.signal?.addEventListener('abort',cancelled,{once:true});
    const timer=setTimeout(()=>abort(new DocverError('TOOL_TIMEOUT','Local document processor timed out')),options.timeout??120_000);
    const collect=(stream:typeof output,chunk:Buffer)=>{if(stream.bytes+chunk.length>(options.maxBytes??16*1024*1024)){abort(new DocverError('TOOL_OUTPUT_LIMIT','Local processor output limit exceeded'));return;}stream.chunks.push(chunk);stream.bytes+=chunk.length;};
    child.stdout!.on('data',d=>collect(output,d));child.stderr!.on('data',d=>collect(diagnostic,d));
    // fd3 belongs only to the trusted guard monitor. The session-leader
    // converter closes it before exec, so a crashed monitor fails closed.
    const statusPipe=options.supervised?child.stdio[3]:undefined;
    if(statusPipe&&'on' in statusPipe){
      let statusBytes=0;
      statusPipe.on('data',(chunk:Buffer)=>{
        statusBytes+=chunk.length;status+=chunk.toString('utf8');
        if(statusBytes>128){abort(new DocverError('TOOL_SUPERVISOR','Invalid renderer monitor status'));return;}
        for(let end;(end=status.indexOf('\n'))>=0;){
          const line=status.slice(0,end);status=status.slice(end+1);
          if(monitor===undefined){
            const match=/^M ([1-9][0-9]*)$/u.exec(line),pid=match?Number(match[1]):0;
            if(!Number.isSafeInteger(pid)||pid<=1||pid>2147483647||pid===child.pid){abort(new DocverError('TOOL_SUPERVISOR','Invalid renderer monitor identity'));return;}
            monitor=pid;options.onSupervisorPid?.(pid);
          }else if(line==='OK'&&!monitorOK)monitorOK=true;
          else {monitorOK=false;abort(new DocverError('TOOL_SUPERVISOR','Invalid renderer monitor status'));return;}
        }
        if(monitorOK&&status.length){monitorOK=false;abort(new DocverError('TOOL_SUPERVISOR','Invalid renderer monitor status'));}
      });
      const monitorClosed=()=>{if(!monitorOK||status.length)abort(new DocverError('TOOL_SUPERVISOR','Renderer monitor exited before completion'));};
      statusPipe.on('end',monitorClosed);statusPipe.on('error',monitorClosed);statusPipe.on('close',monitorClosed);
    }
    const clean=()=>{clearTimeout(timer);options.signal?.removeEventListener('abort',cancelled);if(child.pid)active.delete(child.pid);if(!active.size){process.removeListener('SIGTERM',terminate);process.removeListener('SIGINT',interrupt);}};
    child.on('error',e=>{clean();reject(e);});
    // A failed supervisor may leave descendants holding its stdio open. Kill
    // the owned detached group at exit, before waiting for the close event.
    child.on('exit',code=>{if(code!==0&&child.pid)kill(child.pid,'SIGKILL');});
    child.on('close',(code,signal)=>{clean();const stdout=Buffer.concat(output.chunks,output.bytes),stderr=Buffer.concat(diagnostic.chunks,diagnostic.bytes);if(failure)reject(failure instanceof DocverError&&failure.code==='TOOL_SUPERVISOR'?new DocverError(failure.code,failure.message+' (exit '+code+', signal '+(signal??'none')+'): '+stderr.toString('utf8').slice(-500)):failure);else if(code!==0)reject(new DocverError('TOOL_FAILED','Local processor failed (exit '+code+(signal?', signal '+signal:'')+'): '+(stderr.length?stderr:stdout).toString('utf8').slice(-500)));else if(!monitorOK)reject(new DocverError('TOOL_SUPERVISOR','Renderer monitor did not confirm completion'));else resolveRun(stdout.toString('utf8'));});
    child.stdin!.on('error',()=>{});child.stdin!.end(options.input);
    if(options.signal?.aborted)cancelled();
  });
}
const repository=resolve(dirname(fileURLToPath(import.meta.url)),'../..');
export function visionExecutable():string|undefined {
  if(process.platform==='win32')return undefined;
  return [join(dirname(process.execPath),'DocverVision'),process.env.DOCVER_VISION,join(repository,'dist/native/DocverVision')].find(p=>p&&existsSync(p));
}
export function officeExecutable():string|undefined {
  // The shipped confinement adapter is macOS-specific. Do not discover and
  // launch an unconfined Windows Office installation as an implicit fallback.
  if(process.platform==='win32')return undefined;
  return [join(dirname(process.execPath),'LibreOffice.app/Contents/MacOS/soffice'),process.env.DOCVER_SOFFICE,join(repository,'dist/tools/LibreOffice.app/Contents/MacOS/soffice'),'/Applications/LibreOffice.app/Contents/MacOS/soffice'].find(p=>p&&existsSync(p));
}
const HelperInfo=z.object({version:z.string().min(1),os:z.string().min(1),revision:z.literal(3),languages:z.array(z.string()).refine(l=>l.includes('ko-KR')&&l.includes('en-US')),language_correction:z.literal(false),font_inventory_sha256:z.string().regex(/^[a-f0-9]{64}$/),font_families:z.array(z.string())}).passthrough();
let infoPromise:Promise<Record<string,any>|undefined>|undefined;
async function probeVisionInfo(signal?:AbortSignal):Promise<Record<string,any>|undefined>{
  signal?.throwIfAborted();const executable=visionExecutable();if(!executable)return undefined;
  const folder=await mkdtemp(join(tmpdir(),'docver-vision-info-'));
  try{const launch=await nativeHelperLaunch(executable,folder);return {...HelperInfo.parse(JSON.parse(await runTool(launch.executable,[...launch.args,'--info'],{timeout:30_000,signal,cwd:folder,inheritEnv:false,env:launch.env}))),binary_sha256:byteHash(await readFile(executable)),isolation_policy:launch.policy};}
  catch(e){signal?.throwIfAborted();if(e instanceof DocverError&&e.code==='CANCELLED')throw e;return undefined;}
  finally{await rm(folder,{recursive:true,force:true});}
}
export function visionInfo(signal?:AbortSignal):Promise<Record<string,any>|undefined>{
  // A cancellable optional viewer owns its probe. Cancelling it must not abort
  // or poison another caller's shared processing-environment inspection.
  if(signal)return probeVisionInfo(signal);
  if(!infoPromise){const pending=probeVisionInfo();infoPromise=pending;
    pending.then(value=>{if(!value&&infoPromise===pending)infoPromise=undefined;},()=>{if(infoPromise===pending)infoPromise=undefined;});}
  return infoPromise;
}
