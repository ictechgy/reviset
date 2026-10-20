import { z } from 'zod';
import { spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import { readFile } from 'node:fs/promises';
import { dirname,join,resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { byteHash,DocverError } from '../schema/index.js';

const active=new Map<number,()=>void>();
function kill(pid:number,signal:NodeJS.Signals='SIGTERM'){try{process.kill(-pid,signal);}catch{/* already exited */}}
function stop(){for(const cancel of active.values())cancel();}
const terminate=()=>stop(),interrupt=()=>stop();
export async function runTool(executable:string,args:string[],options:{input?:string;timeout?:number;signal?:AbortSignal;maxBytes?:number;env?:NodeJS.ProcessEnv;inheritEnv?:boolean}={}):Promise<string>{
  options.signal?.throwIfAborted();
  return new Promise((resolveRun,reject)=>{
    const child=spawn(executable,args,{detached:true,stdio:['pipe','pipe','pipe'],env:{...(options.inheritEnv===false?{}:process.env),SAL_DISABLE_OPENCL:'1',...options.env}});
    let stdout:Buffer=Buffer.alloc(0),stderr:Buffer=Buffer.alloc(0),failure:Error|undefined;
    const abort=(error:Error)=>{if(failure)return;failure=error;if(child.pid)kill(child.pid,'SIGKILL');};
    const cancelled=()=>abort(new DocverError('CANCELLED','Local document processing cancelled'));
    if(child.pid){if(!active.size){process.once('SIGTERM',terminate);process.once('SIGINT',interrupt);}active.set(child.pid,cancelled);}
    options.signal?.addEventListener('abort',cancelled,{once:true});
    const timer=setTimeout(()=>abort(new DocverError('TOOL_TIMEOUT','Local document processor timed out')),options.timeout??120_000);
    const collect=(value:Buffer,chunk:Buffer)=>{if(value.length+chunk.length>(options.maxBytes??16*1024*1024)){abort(new DocverError('TOOL_OUTPUT_LIMIT','Local processor output limit exceeded'));return value;}return Buffer.concat([value,chunk]);};
    child.stdout.on('data',d=>{stdout=collect(stdout,d);});child.stderr.on('data',d=>{stderr=collect(stderr,d);});
    const clean=()=>{clearTimeout(timer);options.signal?.removeEventListener('abort',cancelled);if(child.pid)active.delete(child.pid);if(!active.size){process.removeListener('SIGTERM',terminate);process.removeListener('SIGINT',interrupt);}};
    child.on('error',e=>{clean();reject(e);});
    // A failed supervisor may leave descendants holding its stdio open. Kill
    // the owned detached group at exit, before waiting for the close event.
    child.on('exit',code=>{if(code!==0&&child.pid)kill(child.pid,'SIGKILL');});
    child.on('close',code=>{clean();if(failure)reject(failure);else if(code!==0)reject(new DocverError('TOOL_FAILED','Local processor failed (exit '+code+'): '+(stderr.length?stderr:stdout).toString('utf8').slice(-500)));else resolveRun(stdout.toString('utf8'));});
    child.stdin.on('error',()=>{});child.stdin.end(options.input);
    if(options.signal?.aborted)cancelled();
  });
}
const repository=resolve(dirname(fileURLToPath(import.meta.url)),'../..');
export function visionExecutable():string|undefined {
  return [process.env.DOCVER_VISION,join(dirname(process.execPath),'DocverVision'),join(repository,'dist/native/DocverVision')].find(p=>p&&existsSync(p));
}
export function officeExecutable():string|undefined {
  return [process.env.DOCVER_SOFFICE,join(dirname(process.execPath),'LibreOffice.app/Contents/MacOS/soffice'),join(repository,'dist/tools/LibreOffice.app/Contents/MacOS/soffice'),'/Applications/LibreOffice.app/Contents/MacOS/soffice'].find(p=>p&&existsSync(p));
}
const HelperInfo=z.object({version:z.string().min(1),os:z.string().min(1),revision:z.literal(3),languages:z.array(z.string()).refine(l=>l.includes('ko-KR')&&l.includes('en-US')),language_correction:z.literal(false),font_inventory_sha256:z.string().regex(/^[a-f0-9]{64}$/),font_families:z.array(z.string())}).passthrough();
let infoPromise:Promise<Record<string,any>|undefined>|undefined;
async function probeVisionInfo(signal?:AbortSignal):Promise<Record<string,any>|undefined>{
  signal?.throwIfAborted();const executable=visionExecutable();if(!executable)return undefined;
  try{return {...HelperInfo.parse(JSON.parse(await runTool(executable,['--info'],{timeout:30_000,signal}))),binary_sha256:byteHash(await readFile(executable))};}
  catch(e){signal?.throwIfAborted();if(e instanceof DocverError&&e.code==='CANCELLED')throw e;return undefined;}
}
export function visionInfo(signal?:AbortSignal):Promise<Record<string,any>|undefined>{
  // A cancellable optional viewer owns its probe. Cancelling it must not abort
  // or poison another caller's shared processing-environment inspection.
  if(signal)return probeVisionInfo(signal);
  if(!infoPromise){const pending=probeVisionInfo();infoPromise=pending;
    pending.then(value=>{if(!value&&infoPromise===pending)infoPromise=undefined;},()=>{if(infoPromise===pending)infoPromise=undefined;});}
  return infoPromise;
}
