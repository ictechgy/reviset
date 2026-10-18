import { createReadStream } from 'node:fs';
import { createHash } from 'node:crypto';
export async function fileSha256(path:string,signal?:AbortSignal):Promise<string>{
  const hash=createHash('sha256');
  for await(const chunk of createReadStream(path,{highWaterMark:1024*1024,signal}))hash.update(chunk);
  return hash.digest('hex');
}
