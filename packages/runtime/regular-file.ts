import { constants } from 'node:fs';
import { open } from 'node:fs/promises';
import { DocverError, MAX_INPUT_BYTES } from '../schema/index.js';

export interface RegularFileOptions { signal?:AbortSignal; maxBytes?:number }
const CHUNK_BYTES=1024*1024;
function nonregular(){return new DocverError('INPUT_NOT_REGULAR','Document input must be a regular file, not a link or special file');}
function checkSize(size:number,maxBytes:number){if(size>maxBytes)throw new DocverError('FILE_LIMIT',`Input exceeds ${maxBytes} byte limit`);}

// Keep validation and all reads on one descriptor. NONBLOCK makes opening a
// writerless FIFO safe; NOFOLLOW prevents a selected pathname becoming a link.
export async function* regularFileChunks(path:string,options:RegularFileOptions={}):AsyncGenerator<Buffer> {
  const {signal}=options,maxBytes=options.maxBytes??MAX_INPUT_BYTES;
  if(!Number.isSafeInteger(maxBytes)||maxBytes<0)throw new RangeError('Invalid input byte limit');
  signal?.throwIfAborted();
  const handle=await open(path,constants.O_RDONLY|constants.O_NOFOLLOW|constants.O_NONBLOCK).catch(error=>{if(error.code==='ELOOP')throw nonregular();throw error;});
  try{
    signal?.throwIfAborted();
    const initial=await handle.stat();
    if(!initial.isFile())throw nonregular();
    checkSize(initial.size,maxBytes);
    let total=0;
    while(true){
      signal?.throwIfAborted();
      // One extra byte detects growth past the cap without allocating or
      // consuming the remainder of an unexpectedly large input.
      const buffer=Buffer.allocUnsafe(Math.min(CHUNK_BYTES,maxBytes-total+1));
      const {bytesRead}=await handle.read(buffer,0,buffer.length,null);
      signal?.throwIfAborted();
      if(!bytesRead)break;
      total+=bytesRead;checkSize(total,maxBytes);
      yield buffer.subarray(0,bytesRead);
    }
    checkSize((await handle.stat()).size,maxBytes);
    signal?.throwIfAborted();
  }finally{await handle.close();}
}

export async function readRegularFile(path:string,options:RegularFileOptions={}):Promise<Buffer> {
  const chunks:Buffer[]=[];let size=0;
  for await(const chunk of regularFileChunks(path,options)){chunks.push(chunk);size+=chunk.length;}
  options.signal?.throwIfAborted();
  return Buffer.concat(chunks,size);
}
