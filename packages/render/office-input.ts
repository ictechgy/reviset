import {existsSync,createReadStream} from 'node:fs';
import {readFile,lstat} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {z} from 'zod';
import {runTool} from '../runtime/tools.js';
import {byteHash,hash,OfficeInputPreparation,MAX_INPUT_BYTES,DocverError,type OfficeInputPreparationData} from '../schema/index.js';
import {officeInputPolicy} from './pptx-default-insets.js';
function helper(){
  const source=new URL('../../apps/helpers/OfficeInput.ts',import.meta.url),bundled=new URL('./office-input.mjs',import.meta.url);
  if(existsSync(source))return {path:fileURLToPath(source),args:['--import',import.meta.resolve('tsx'),fileURLToPath(source)],sources:[source,new URL('./pptx-default-insets.ts',import.meta.url),new URL('../schema/index.ts',import.meta.url)]};
  if(existsSync(bundled))return {path:fileURLToPath(bundled),args:[fileURLToPath(bundled)],sources:[bundled]};
  throw new DocverError('CONVERTER_UNAVAILABLE','Renderer input helper is unavailable');
}
export async function officeInputEnvironment():Promise<{policy:string;helper_fingerprint:string}>{
  const current=helper(),fingerprints=await Promise.all(current.sources.map(async path=>byteHash(await readFile(path))));
  return {policy:officeInputPolicy,helper_fingerprint:hash(fingerprints)};
}
export function parseOfficeInputMetadata(value:unknown,sourceHash:string):OfficeInputPreparationData{
  const metadata=OfficeInputPreparation.parse(value);
  if(metadata.policy!==officeInputPolicy||metadata.source_sha256!==sourceHash||!metadata.changed_properties&&metadata.input_sha256!==sourceHash||metadata.changed_properties&&metadata.skip_reason)throw new DocverError('OFFICE_INPUT_PROTOCOL','Renderer input identity mismatch');
  return metadata;
}
export async function prepareOfficeInput(folder:string,sourceHash:string,timeout:number,signal?:AbortSignal):Promise<{path:string;metadata:OfficeInputPreparationData}>{
  signal?.throwIfAborted();const current=helper();
  const response=z.discriminatedUnion('status',[z.object({status:z.literal('ok'),metadata:OfficeInputPreparation}),z.object({status:z.literal('error'),code:z.enum(['ZIP_LIMIT','ZIP_PATH','OFFICE_INPUT_FAILED'])})]).parse(JSON.parse(await runTool(process.execPath,current.args,{input:JSON.stringify({folder,source_sha256:sourceHash}),timeout,signal,maxBytes:8192,inheritEnv:false,env:{PATH:'/usr/bin:/bin',LANG:'en_US.UTF-8',TMPDIR:folder}})));
  if(response.status==='error')throw new DocverError(response.code,'Renderer input preparation failed');
  const metadata=parseOfficeInputMetadata(response.metadata,sourceHash);
  const path=join(folder,metadata.changed_properties?'render-input.pptx':'input.pptx'),info=await lstat(path);
  if(!info.isFile()||info.size>MAX_INPUT_BYTES)throw new DocverError('OFFICE_INPUT_PROTOCOL','Renderer input file is invalid');
  const digest=createHash('sha256');for await(const chunk of createReadStream(path,{signal})){digest.update(chunk);}
  if(digest.digest('hex')!==metadata.input_sha256)throw new DocverError('OFFICE_INPUT_PROTOCOL','Renderer input hash mismatch');
  return {path,metadata};
}
