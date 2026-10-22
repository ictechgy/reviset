import {createHash} from 'node:crypto';
import {openSync,writeSync,closeSync} from 'node:fs';

// Report trees contain JSON values, plain objects and optional undefined
// properties after schema validation. Serialize that domain without retaining
// the complete replacer-created object graph or a full string just to hash it.
// Rich objects/accessors are deliberately outside this internal boundary.
function visit(value:unknown,emit:(part:string)=>void,active:Set<object>):void {
  if(value===null){emit('null');return;}
  if(typeof value==='string'||typeof value==='number'||typeof value==='boolean'){emit(JSON.stringify(value));return;}
  if(!value||typeof value!=='object')throw new TypeError('Canonical report contains a non-JSON value');
  if(active.has(value))throw new TypeError('Canonical report contains a cycle');
  const array=Array.isArray(value),prototype=Object.getPrototypeOf(value);
  if(!array&&prototype!==Object.prototype&&prototype!==null)throw new TypeError('Canonical report contains a non-plain object');
  active.add(value);
  try{
    if(array){
      emit('[');
      for(let i=0;i<value.length;i++){if(i)emit(',');const descriptor=Object.getOwnPropertyDescriptor(value,String(i));if(descriptor&&!('value' in descriptor))throw new TypeError('Canonical report contains an accessor');const item=descriptor?.value;if(item===undefined)emit('null');else visit(item,emit,active);}
      emit(']');return;
    }
    // JSON enumerates array-index property names numerically even after the
    // canonical replacer's locale-sorted insertion into a new plain object.
    const index=(key:string)=>{const number=Number(key);return Number.isInteger(number)&&number>=0&&number<4294967295&&String(number)===key?number:undefined;};
    const keys=Object.keys(value).sort((a,b)=>{const x=index(a),y=index(b);return x!==undefined?y!==undefined?x-y:-1:y!==undefined?1:a.localeCompare(b,'en');});
    emit('{');let first=true;
    for(const key of keys){const descriptor=Object.getOwnPropertyDescriptor(value,key)!;if(!('value' in descriptor))throw new TypeError('Canonical report contains an accessor');if(descriptor.value===undefined)continue;if(!first)emit(',');first=false;emit(JSON.stringify(key));emit(':');visit(descriptor.value,emit,active);}
    emit('}');
  }finally{active.delete(value);}
}
function serialize(value:unknown,consume:(chunk:string)=>void):void {
  // Join each batch so stored chunks do not retain millions of tiny cons-string
  // nodes. Append complete JSON tokens: a flush never splits a surrogate pair.
  const parts:string[]=[];let length=0;
  const flush=()=>{consume(parts.join(''));parts.length=0;length=0;};
  visit(value,part=>{parts.push(part);length+=part.length;if(length>=64*1024)flush();},new Set());
  if(parts.length)flush();
}
export function canonicalJson(value:unknown):string {const chunks:string[]=[];serialize(value,chunk=>chunks.push(chunk));return chunks.join('');}
export function canonicalJsonDigest(value:unknown):string {const digest=createHash('sha256');serialize(value,chunk=>digest.update(chunk));return digest.digest('hex');}
// Staging requires an exclusive private file and a digest of exactly its bytes.
// Synchronous bounded batches avoid queuing an entire report in a write stream.
export function writeCanonicalJson(path:string,value:unknown,signal?:AbortSignal):string {
  signal?.throwIfAborted();const fd=openSync(path,'wx',0o600),digest=createHash('sha256');
  try{
    serialize(value,chunk=>{
      signal?.throwIfAborted();const bytes=Buffer.from(chunk);let offset=0;
      while(offset<bytes.length){const written=writeSync(fd,bytes,offset,bytes.length-offset);if(!written)throw new Error('Report staging write made no progress');offset+=written;}
      digest.update(bytes);
    });
    return digest.digest('hex');
  }finally{closeSync(fd);}
}
