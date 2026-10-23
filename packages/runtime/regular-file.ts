import { constants } from 'node:fs';
import { open,lstat,type FileHandle } from 'node:fs/promises';
import { DocverError, MAX_INPUT_BYTES } from '../schema/index.js';

export interface RegularFileOptions { signal?:AbortSignal; maxBytes?:number }
const CHUNK_BYTES=1024*1024;
function nonregular(){return new DocverError('INPUT_NOT_REGULAR','Document input must be a regular file, not a link or special file');}
function checkSize(size:number,maxBytes:number){if(size>maxBytes)throw new DocverError('FILE_LIMIT',`Input exceeds ${maxBytes} byte limit`);}

// Windows does not implement O_NOFOLLOW/O_NONBLOCK. Validate the selected
// directory entry and compare its file identity with the opened descriptor,
// rather than silently treating an undefined flag as link protection. Reads
// remain attached to that descriptor even if the pathname is later replaced.
export async function openRegularFile(path:string):Promise<FileHandle> {
  const windows=process.platform==='win32';
  if(windows&&/^\\\\[.?]\\/u.test(path))throw nonregular();
  const selected=windows?await lstat(path,{bigint:true}):undefined;
  if(selected&&!selected.isFile())throw nonregular();
  const handle=await open(path,constants.O_RDONLY|(constants.O_NOFOLLOW??0)|(constants.O_NONBLOCK??0)).catch(error=>{if(error.code==='ELOOP')throw nonregular();throw error;});
  try {
    const opened=await handle.stat({bigint:true});
    if(!opened.isFile()||selected&&(selected.dev!==opened.dev||selected.ino!==opened.ino))throw nonregular();
    return handle;
  }catch(error){await handle.close();throw error;}
}

// Keep validation and all reads on one descriptor. NONBLOCK makes opening a
// writerless FIFO safe; NOFOLLOW prevents a selected pathname becoming a link.
export async function* regularFileChunks(path:string,options:RegularFileOptions={}):AsyncGenerator<Buffer> {
  const {signal}=options,maxBytes=options.maxBytes??MAX_INPUT_BYTES;
  if(!Number.isSafeInteger(maxBytes)||maxBytes<0)throw new RangeError('Invalid input byte limit');
  signal?.throwIfAborted();
  const handle=await openRegularFile(path);
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
