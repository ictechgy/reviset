import {unzipSync,zipSync,strToU8} from 'fflate';
import {XMLValidator} from 'fast-xml-parser';
import {MAX_PPTX_EXPANDED_BYTES,MAX_PPTX_PART_BYTES,DocverError} from '../schema/index.js';

export const officeInputPolicy='source-copy-svg-read-allowlist-v6-standard-nonplaceholder-insets';
const presentation=new Set(['http://schemas.openxmlformats.org/presentationml/2006/main','http://purl.oclc.org/ooxml/presentationml/main']);
const drawing=new Set(['http://schemas.openxmlformats.org/drawingml/2006/main','http://purl.oclc.org/ooxml/drawingml/main']);
const defaults={lIns:91440,rIns:91440,tIns:45720,bIns:45720};
type Edit={offset:number;text:string;count:number};
type Shape={eligible:boolean;placeholder:boolean;body:Edit[]};
type Frame={name:string;namespaces:Map<string,string>;shape?:Shape;owner?:Shape};

// Preserve XML bytes, namespace bindings, explicit values and placeholder
// inheritance. Only missing standard margins on ordinary slide shapes change.
function materializeXml(xml:string):{xml:string;count:number}{
  if(/<!DOCTYPE|<!ENTITY/i.test(xml)||XMLValidator.validate(xml)!==true)return {xml,count:0};
  const stack:Frame[]=[],edits:Edit[]=[];let root=false;
  const finish=(frame:Frame|undefined)=>{const shape=frame?.owner;if(shape?.eligible&&!shape.placeholder&&shape.body.length===1)edits.push(shape.body[0]);};
  for(const match of xml.matchAll(/<!--[\s\S]*?-->|<!\[CDATA\[[\s\S]*?\]\]>|<\?[\s\S]*?\?>|<\/?(?:[^<>"']|"[^"]*"|'[^']*')+>/g)){
    const tag=match[0];if(tag.startsWith('<!')||tag.startsWith('<?'))continue;
    if(tag.startsWith('</')){finish(stack.pop());continue;}
    const qualified=/^<([^\s/>]+)/.exec(tag)?.[1];if(!qualified||stack.length>=100||edits.length>=20000)return {xml,count:0};
    const attributes=new Map([...tag.matchAll(/([^\s=<>/"']+)\s*=\s*(["'])([\s\S]*?)\2/g)].map(m=>[m[1],m[3]]));
    const parent=stack.at(-1),bindings=[...attributes].filter(([key])=>key==='xmlns'||key.startsWith('xmlns:'));
    const namespaces=bindings.length?new Map(parent?.namespaces):parent?.namespaces??new Map<string,string>();
    for(const [name,value]of bindings)namespaces.set(name==='xmlns'?'':name.slice(6),value);
    const colon=qualified.indexOf(':'),prefix=colon<0?'':qualified.slice(0,colon),local=colon<0?qualified:qualified.slice(colon+1),uri=namespaces.get(prefix);
    const name=(uri&&presentation.has(uri)?'p:':uri&&drawing.has(uri)?'a:':'other:')+local;
    if(!stack.length){if(root||name!=='p:sld')return {xml,count:0};root=true;}
    let shape=parent?.shape,owner:Shape|undefined;
    if(name==='p:sp'){owner=shape={eligible:parent?.name==='p:spTree'||parent?.name==='p:grpSp',placeholder:false,body:[]};}
    if(name==='p:ph'&&shape)shape.placeholder=true;
    if(name==='a:bodyPr'&&parent?.name==='p:txBody'&&stack.at(-2)?.name==='p:sp'&&shape){
      const missing=Object.entries(defaults).filter(([key])=>!attributes.has(key));
      if(shape.body.length<2)shape.body.push({offset:match.index+tag.length-(tag.endsWith('/>')?2:1),text:missing.map(([key,value])=>` ${key}="${value}"`).join(''),count:missing.length});
    }
    const frame={name,namespaces,shape,owner};if(tag.endsWith('/>'))finish(frame);else stack.push(frame);
  }
  if(stack.length||!root)return {xml,count:0};
  let result=xml,count=0;for(const edit of edits.sort((a,b)=>b.offset-a.offset)){result=result.slice(0,edit.offset)+edit.text+result.slice(edit.offset);count+=edit.count;}
  return {xml:result,count};
}

export function materializeOfficeInsets(bytes:Uint8Array):{bytes:Uint8Array;changed_properties:number}{
  let total=0,ambiguous=false;const seen=new Set<string>();
  const parts=unzipSync(bytes,{filter:entry=>{
    total+=entry.originalSize;if(total>MAX_PPTX_EXPANDED_BYTES||entry.originalSize>MAX_PPTX_PART_BYTES)throw new DocverError('ZIP_LIMIT','Render package exceeds limit');
    if(entry.name.startsWith('/')||entry.name.split('/').includes('..'))throw new DocverError('ZIP_PATH','Unsafe renderer package part');
    const key=entry.name.toLowerCase();if(seen.has(key))ambiguous=true;seen.add(key);return true;
  }});
  // Never rewrite signed or ambiguously named packages for a preview.
  if(ambiguous||Object.keys(parts).some(p=>/^_xmlsignatures\//i.test(p)))return {bytes,changed_properties:0};
  let count=0;
  for(const path of Object.keys(parts).filter(p=>/^ppt\/slides\/slide[0-9]+\.xml$/.test(p))){
    let xml:string;try{xml=new TextDecoder('utf-8',{fatal:true}).decode(parts[path]);}catch{continue;}
    const derived=materializeXml(xml);if(!derived.count)continue;
    parts[path]=strToU8(derived.xml);count+=derived.count;
  }
  return count?{bytes:zipSync(parts,{level:6,mtime:new Date(1980,0,1)}),changed_properties:count}:{bytes,changed_properties:0};
}
