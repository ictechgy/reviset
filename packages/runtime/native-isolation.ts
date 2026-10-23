import {readFile,realpath,mkdir} from 'node:fs/promises';
import {join,dirname} from 'node:path';import {homedir} from 'node:os';
import {DocverError} from '../schema/index.js';
export const NATIVE_ISOLATION_POLICY='job-home-read-allowlist-no-directory-enumeration-v2';
export function nativeHelperPolicy(folder:string,executable:string,source?:string,interpreter?:string){
  const roots=['/System','/usr/lib','/usr/share','/private/etc','/private/var/db','/Library/Fonts',join(homedir(),'Library/Fonts'),'/dev',folder];
  const jobAncestors:string[]=[];for(let p=dirname(folder);;p=dirname(p)){jobAncestors.push(p);if(p===dirname(p))break;}
  // CoreML/NSBundle enumerate the known helper directory during model setup.
  // Permit that exact directory, not every directory or sibling file contents.
  jobAncestors.push(dirname(executable));
  const files=[executable,...(source?[source]:[]),...(interpreter?[interpreter]:[])];
  return `(version 1)(allow default)(deny network*)(deny process-fork)(deny process-exec)(allow process-exec ${[executable,...(interpreter?[interpreter]:[])].map(p=>`(literal ${JSON.stringify(p)})`).join(' ')})(deny lsopen)(deny user-preference-write)(deny signal (target others))(deny system-debug)(deny file-read-data)(allow file-read-data ${jobAncestors.map(p=>`(literal ${JSON.stringify(p)})`).join(' ')} ${roots.map(p=>`(subpath ${JSON.stringify(p)})`).join(' ')} ${files.map(p=>`(literal ${JSON.stringify(p)})`).join(' ')})(deny file-write*)(allow file-write* (subpath ${JSON.stringify(folder)}) (subpath "/dev"))`;
}
export async function nativeHelperLaunch(executable:string,folder:string,source?:string){
  if(process.platform==='win32')throw new DocverError('OCR_UNAVAILABLE','The Apple native helper has no confined Windows adapter');
  folder=await realpath(folder);executable=await realpath(executable);if(source)source=await realpath(source);
  await mkdir(join(folder,'Library/Caches'),{recursive:true,mode:0o700});
  // CFFIXED_USER_HOME is required: CoreML otherwise reads/writes its normal
  // per-user compiled-model cache even when HOME and TMPDIR point to the job.
  const env={PATH:'/usr/bin:/bin:/usr/sbin:/sbin',LANG:'en_US.UTF-8',LC_ALL:'en_US.UTF-8',HOME:folder,CFFIXED_USER_HOME:folder,TMPDIR:folder+'/',XDG_CACHE_HOME:join(folder,'cache')};
  if(process.platform!=='darwin')return {executable,args:[] as string[],env,policy:'non-native-platform'};
  // Explicit source-development protocol fixtures are executable test code,
  // not the native document parser. Bundled helpers take precedence over the
  // override in visionExecutable(); never describe a fixture as sandboxed.
  const bytes=await readFile(executable),node=await realpath(process.execPath),line=bytes.subarray(0,Math.min(1024,bytes.length)).toString('utf8').split('\n')[0];
  const interpreter=line===`#!${process.execPath}`||line===`#!${node}`?node:undefined;
  if(interpreter&&process.env.DOCVER_VISION&&executable===await realpath(process.env.DOCVER_VISION))return {executable,args:[] as string[],env:{...process.env,...env},policy:'development-node-fixture-unconfined-v1'};
  return {executable:'/usr/bin/sandbox-exec',args:['-p',nativeHelperPolicy(folder,executable,source),executable],env,policy:NATIVE_ISOLATION_POLICY};
}
