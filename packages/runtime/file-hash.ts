import { createHash } from 'node:crypto';
import { regularFileChunks } from './regular-file.js';
export async function fileSha256(path:string,signal?:AbortSignal):Promise<string>{
  const hash=createHash('sha256');
  for await(const chunk of regularFileChunks(path,{signal}))hash.update(chunk);
  return hash.digest('hex');
}
