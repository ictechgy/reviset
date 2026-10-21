import {openSync,writeFileSync,fsyncSync,closeSync,linkSync,readFileSync,lstatSync,renameSync,unlinkSync} from 'node:fs';
import {open,link,readFile,lstat,rename,unlink} from 'node:fs/promises';
import {dirname,join} from 'node:path';
import {randomUUID} from 'node:crypto';
import {byteHash,DocverError} from '../schema/index.js';

// Publish only a fully written, synced blob under its canonical name. A
// pre-existing corrupt regular file is retained by a quarantine hardlink
// before the verified replacement is atomically renamed into place.
function temporary(target:string){return join(dirname(target),'.docver-content-'+randomUUID()+'.tmp');}
function corrupt(){return new DocverError('ASSET_CORRUPT','저장 원본이 일반 파일이 아닙니다. 기존 파일을 보존했으며 자동으로 덮어쓰지 않았습니다.');}
export function publishContentSync(target:string,bytes:Uint8Array,sha256:string){
  if(byteHash(bytes)!==sha256)throw new DocverError('ASSET_HASH','Content does not match its expected hash');
  const temp=temporary(target);let fd:number|undefined;
  try{
    fd=openSync(temp,'wx',0o600);writeFileSync(fd,bytes);fsyncSync(fd);closeSync(fd);fd=undefined;
    try{linkSync(temp,target);}catch(error){
      if((error as NodeJS.ErrnoException).code!=='EEXIST')throw error;
      if(!lstatSync(target).isFile())throw corrupt();
      if(byteHash(readFileSync(target))===sha256)return;
      const quarantine=target+'.corrupt-'+randomUUID();linkSync(target,quarantine);
      // Quarantine is a hardlink, never a rename of the canonical name. A
      // competing repair may already have published the same verified bytes.
      const prior=lstatSync(quarantine),current=lstatSync(target);
      if(prior.dev!==current.dev||prior.ino!==current.ino){if(current.isFile()&&byteHash(readFileSync(target))===sha256)return;throw new DocverError('ASSET_BUSY','저장 원본이 변경됐습니다. 보존된 파일을 확인한 뒤 다시 시도하세요.');}
      renameSync(temp,target);
    }
  }finally{if(fd!==undefined)closeSync(fd);try{unlinkSync(temp);}catch(error){if((error as NodeJS.ErrnoException).code!=='ENOENT')throw error;}}
}
export async function publishContent(target:string,bytes:Uint8Array,sha256:string){
  if(byteHash(bytes)!==sha256)throw new DocverError('ASSET_HASH','Content does not match its expected hash');
  const temp=temporary(target);let handle:Awaited<ReturnType<typeof open>>|undefined;
  try{
    handle=await open(temp,'wx',0o600);await handle.writeFile(bytes);await handle.sync();await handle.close();handle=undefined;
    try{await link(temp,target);}catch(error){
      if((error as NodeJS.ErrnoException).code!=='EEXIST')throw error;
      if(!(await lstat(target)).isFile())throw corrupt();
      if(byteHash(await readFile(target))===sha256)return;
      const quarantine=target+'.corrupt-'+randomUUID();await link(target,quarantine);
      const prior=await lstat(quarantine),current=await lstat(target);
      if(prior.dev!==current.dev||prior.ino!==current.ino){if(current.isFile()&&byteHash(await readFile(target))===sha256)return;throw new DocverError('ASSET_BUSY','저장 원본이 변경됐습니다. 보존된 파일을 확인한 뒤 다시 시도하세요.');}
      await rename(temp,target);
    }
  }finally{await handle?.close();try{await unlink(temp);}catch(error){if((error as NodeJS.ErrnoException).code!=='ENOENT')throw error;}}
}
