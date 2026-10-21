// Bounds serialized retained data, not the JavaScript heap size. Values are
// immutable snapshot derivatives; scope checks must precede every lookup.
export class BoundedCache<T> {
  private entries=new Map<string,{value:T;bytes:number}>();
  private bytes=0;
  constructor(private readonly maxEntries:number,private readonly maxBytes:number){}
  get(key:string):T|undefined {
    const entry=this.entries.get(key);if(!entry)return undefined;
    this.entries.delete(key);this.entries.set(key,entry);return entry.value;
  }
  set(key:string,value:T,serializedBytes?:number){
    const bytes=serializedBytes??Buffer.byteLength(JSON.stringify(value));if(!Number.isSafeInteger(bytes)||bytes<0||bytes>this.maxBytes)return;
    const prior=this.entries.get(key);if(prior){this.bytes-=prior.bytes;this.entries.delete(key);}
    while(this.entries.size>=this.maxEntries||this.bytes+bytes>this.maxBytes){const oldest=this.entries.keys().next().value;if(oldest===undefined)break;this.bytes-=this.entries.get(oldest)!.bytes;this.entries.delete(oldest);}
    this.entries.set(key,{value,bytes});this.bytes+=bytes;
  }
}
