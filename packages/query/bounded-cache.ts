// Count validated plain JSON without constructing its serialized string. The
// limit includes punctuation, keys and escaped UTF-8 bytes. Stop as soon as it
// cannot fit, including before flattening a single oversized string.
function boundedJsonBytes(value:unknown,limit:number):number|null {
  let bytes=0;
  const add=(count:number)=>(bytes+=count)<=limit;
  const string=(text:string):boolean=>{
    if(text.length+2>limit-bytes||!add(2))return false;
    for(let i=0;i<text.length;i++){
      const code=text.charCodeAt(i);let count:number;
      if(code===34||code===92||code===8||code===9||code===10||code===12||code===13)count=2;
      else if(code<32)count=6;
      else if(code<128)count=1;
      else if(code<2048)count=2;
      else if(code>=0xd800&&code<=0xdbff){const next=text.charCodeAt(i+1);if(next>=0xdc00&&next<=0xdfff){count=4;i++;}else count=6;}
      else count=code>=0xdc00&&code<=0xdfff?6:3;
      if(!add(count))return false;
    }
    return true;
  };
  function* keys(object:object){for(const key in object)if(Object.hasOwn(object,key))yield key;}
  const omitted=(item:unknown)=>item===undefined||typeof item==='function'||typeof item==='symbol';
  type Frame={kind:'value';value:unknown}|{kind:'array';value:unknown[];index:number}|{kind:'object';value:object;keys:Generator<string>;count:number};
  const frames:Frame[]=[{kind:'value',value}],active=new Set<object>();
  while(frames.length){
    const frame=frames.pop()!;
    if(frame.kind==='array'){
      if(frame.index===frame.value.length){active.delete(frame.value);continue;}
      if(frame.index&&!add(1))return null;
      const descriptor=Object.getOwnPropertyDescriptor(frame.value,String(frame.index++));
      if(descriptor&&!('value' in descriptor))throw new TypeError('Cache data contains an accessor');
      const item=descriptor?.value;frames.push(frame,{kind:'value',value:omitted(item)?null:item});continue;
    }
    if(frame.kind==='object'){
      const next=frame.keys.next();if(next.done){active.delete(frame.value);continue;}
      const descriptor=Object.getOwnPropertyDescriptor(frame.value,next.value)!;
      if(!('value' in descriptor))throw new TypeError('Cache data contains an accessor');
      frames.push(frame);if(omitted(descriptor.value))continue;
      if((frame.count++&&!add(1))||!string(next.value)||!add(1))return null;
      frames.push({kind:'value',value:descriptor.value});continue;
    }
    const item=frame.value;
    if(item===null){if(!add(4))return null;continue;}
    if(typeof item==='string'){if(!string(item))return null;continue;}
    if(typeof item==='number'){if(!add(JSON.stringify(item).length))return null;continue;}
    if(typeof item==='boolean'){if(!add(item?4:5))return null;continue;}
    if(omitted(item))return null;
    if(typeof item!=='object')throw new TypeError('Cache data contains a non-JSON value');
    if(active.has(item))throw new TypeError('Cache data contains a cycle');
    const array=Array.isArray(item),prototype=Object.getPrototypeOf(item),serializer=Object.getOwnPropertyDescriptor(item,'toJSON');
    if(serializer&&(!('value' in serializer)||typeof serializer.value==='function'))throw new TypeError('Cache data contains a custom serializer');
    if(!array&&prototype!==Object.prototype&&prototype!==null)throw new TypeError('Cache data contains a non-plain object');
    // Every array element needs at least one byte and every pair a comma.
    if(array&&item.length>0&&item.length*2+1>limit-bytes)return null;
    if(!add(2))return null;active.add(item);
    frames.push(array?{kind:'array',value:item,index:0}:{kind:'object',value:item,keys:keys(item),count:0});
  }
  return bytes;
}

// Bounds serialized retained data, not the JavaScript heap size. Values are
// immutable plain snapshot derivatives; scope checks precede every lookup.
export class BoundedCache<T> {
  private entries=new Map<string,{value:T;bytes:number}>();
  private bytes=0;
  constructor(private readonly maxEntries:number,private readonly maxBytes:number){}
  get(key:string):T|undefined {
    const entry=this.entries.get(key);if(!entry)return undefined;
    this.entries.delete(key);this.entries.set(key,entry);return entry.value;
  }
  set(key:string,value:T,serializedBytes?:number){
    // Admission is optional: unsupported derivatives must not break their query.
    // Inspect descriptors only; never invoke getters or toJSON while measuring.
    let bytes:number|null;
    try{bytes=serializedBytes??boundedJsonBytes(value,this.maxBytes);}catch(error){if(error instanceof TypeError)return;throw error;}
    if(bytes===null||!Number.isSafeInteger(bytes)||bytes<0||bytes>this.maxBytes)return;
    const prior=this.entries.get(key);if(prior){this.bytes-=prior.bytes;this.entries.delete(key);}
    while(this.entries.size>=this.maxEntries||this.bytes+bytes>this.maxBytes){const oldest=this.entries.keys().next().value;if(oldest===undefined)break;this.bytes-=this.entries.get(oldest)!.bytes;this.entries.delete(oldest);}
    this.entries.set(key,{value,bytes});this.bytes+=bytes;
  }
}
