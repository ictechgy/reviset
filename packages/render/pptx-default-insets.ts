import {unzipSync,zipSync,type Zippable} from 'fflate';
import {XMLParser,XMLValidator} from 'fast-xml-parser';
import {readXml,encodeXml} from '../xml/index.js';
import {MAX_INPUT_BYTES,MAX_PPTX_EXPANDED_BYTES,MAX_PPTX_PART_BYTES,DocverError} from '../schema/index.js';

export const officeInputPolicy='source-copy-svg-read-allowlist-v8-unicode-bounded-insets';
const presentation=new Set(['http://schemas.openxmlformats.org/presentationml/2006/main','http://purl.oclc.org/ooxml/presentationml/main']);
const drawing=new Set(['http://schemas.openxmlformats.org/drawingml/2006/main','http://purl.oclc.org/ooxml/drawingml/main']);
const defaults={lIns:91440,rIns:91440,tIns:45720,bIns:45720};
type Edit={offset:number;text:string;count:number};
type Shape={eligible:boolean;placeholder:boolean;body:Edit[]};
type Frame={name:string;namespaces:Map<string,string>;shapeTree:boolean;shape?:Shape;owner?:Shape};

// Preserve XML bytes, namespace bindings, explicit values and placeholder
// inheritance. Only missing standard margins on ordinary slide shapes change.
function materializeXml(xml:string):{xml:string;count:number;unsupported?:true}{
  const unsupported=()=>({xml,count:0,unsupported:true as const});
  if(XMLValidator.validate(xml)!==true)return unsupported();
  const stack:Frame[]=[],edits:Edit[]=[];let root=false;
  const finish=(frame:Frame|undefined)=>{const shape=frame?.owner;if(shape?.eligible&&!shape.placeholder&&shape.body.length===1)edits.push(shape.body[0]);};
  for(const match of xml.matchAll(/<!--[\s\S]*?-->|<!\[CDATA\[[\s\S]*?\]\]>|<\?[\s\S]*?\?>|<\/?(?:[^<>"']|"[^"]*"|'[^']*')+>/g)){
    const tag=match[0];if(tag.startsWith('<!')||tag.startsWith('<?'))continue;
    if(tag.startsWith('</')){finish(stack.pop());continue;}
    const qualified=/^<([^\s/>]+)/.exec(tag)?.[1];if(!qualified||stack.length>=100||edits.length>=20000)return unsupported();
    const attributes=new Map([...tag.matchAll(/([^\s=<>/"']+)\s*=\s*(["'])([\s\S]*?)\2/g)].map(m=>[m[1],m[3]]));
    const parent=stack.at(-1),bindings=[...attributes].filter(([key])=>key==='xmlns'||key.startsWith('xmlns:'));
    const namespaces=bindings.length?new Map(parent?.namespaces):parent?.namespaces??new Map<string,string>();
    for(const [name,value]of bindings)namespaces.set(name==='xmlns'?'':name.slice(6),value);
    const colon=qualified.indexOf(':'),prefix=colon<0?'':qualified.slice(0,colon),local=colon<0?qualified:qualified.slice(colon+1),uri=namespaces.get(prefix);
    const name=(uri&&presentation.has(uri)?'p:':uri&&drawing.has(uri)?'a:':'other:')+local;
    if(!stack.length){if(root||name!=='p:sld')return unsupported();root=true;}
    const shapeTree=name==='p:spTree'&&parent?.name==='p:cSld'&&stack.length===2&&stack[0].name==='p:sld'||name==='p:grpSp'&&parent?.shapeTree===true;
    let shape=parent?.shape,owner:Shape|undefined;
    if(name==='p:sp'){owner=shape={eligible:parent?.shapeTree===true,placeholder:false,body:[]};}
    if(name==='p:ph'&&shape)shape.placeholder=true;
    if(name==='a:bodyPr'&&parent?.name==='p:txBody'&&stack.at(-2)?.name==='p:sp'&&shape){
      const missing=Object.entries(defaults).filter(([key])=>!attributes.has(key));
      if(shape.body.length<2)shape.body.push({offset:match.index+tag.length-(tag.endsWith('/>')?2:1),text:missing.map(([key,value])=>` ${key}="${value}"`).join(''),count:missing.length});
    }
    const frame={name,namespaces,shapeTree,shape,owner};if(tag.endsWith('/>'))finish(frame);else stack.push(frame);
  }
  if(stack.length||!root)return unsupported();
  const pieces:string[]=[];let offset=0,count=0;
  for(const edit of edits.sort((a,b)=>a.offset-b.offset)){pieces.push(xml.slice(offset,edit.offset),edit.text);offset=edit.offset;count+=edit.count;}
  pieces.push(xml.slice(offset));return {xml:pieces.join(''),count};
}

export type OfficeInputSkipReason='signed_package'|'ambiguous_part_names'|'unsupported_package_metadata'|'derivation_budget_exceeded';
type Limits={partBytes?:number;totalBytes?:number;zipBytes?:number};
const metadataPart=(path:string)=>/\.rels$/i.test(path)||path.toLowerCase()==='[content_types].xml';
const slidePart=(path:string)=>/^ppt\/slides\/slide[0-9]+\.xml$/.test(path);
function signatureMetadata(parts:Record<string,Uint8Array>):'signature'|'unsupported'|undefined{
  const parser=new XMLParser({ignoreAttributes:false,removeNSPrefix:true,processEntities:false}),array=(value:any):any[]=>value==null?[]:Array.isArray(value)?value:[value];
  const decoded=(value:unknown)=>String(value??'').replace(/&(#x[0-9a-f]+|#[0-9]+|amp|lt|gt|quot|apos);/gi,(_,entity:string)=>{
    if(entity[0]!=='#')return ({amp:'&',lt:'<',gt:'>',quot:'"',apos:"'"} as Record<string,string>)[entity.toLowerCase()];
    const code=entity[1].toLowerCase()==='x'?parseInt(entity.slice(2),16):Number(entity.slice(1));
    if(!code||code>0x10ffff||code>=0xd800&&code<=0xdfff)throw new Error('Invalid XML scalar');return String.fromCodePoint(code);
  });
  for(const [path,bytes]of Object.entries(parts).filter(([path])=>metadataPart(path))){
    let xml:string;try{xml=readXml(bytes);}catch(error){if(error instanceof DocverError&&error.code==='XML_ENCODING_UNAVAILABLE')throw error;return 'unsupported';}
    let depth=0,tags=0;for(const token of xml.matchAll(/<!--[\s\S]*?-->|<!\[CDATA\[[\s\S]*?\]\]>|<\?[\s\S]*?\?>|<\/?(?:[^<>"']|"[^"]*"|'[^']*')+>/g)){
      const tag=token[0];if(tag.startsWith('<!')||tag.startsWith('<?'))continue;
      if(tag.startsWith('</'))depth--;else{tags++;if(!tag.endsWith('/>'))depth++;}
      if(depth>100||tags>100000)return 'unsupported';
    }
    try{
      const data=parser.parse(xml);if(!data||typeof data!=='object')return 'unsupported';
      if(/\.rels$/i.test(path)){
        if(!Object.hasOwn(data,'Relationships'))return 'unsupported';
        if(array(data.Relationships?.Relationship).some(r=>r&&/\/digital-signature\/(origin|signature|certificate)$/i.test(decoded(r['@_Type']).trim())))return 'signature';
      }else{
        if(!Object.hasOwn(data,'Types'))return 'unsupported';
        if([...array(data.Types?.Default),...array(data.Types?.Override)].some(r=>r&&decoded(r['@_ContentType']).toLowerCase().includes('openxmlformats-package.digital-signature')))return 'signature';
      }
    }catch{return 'unsupported';}
  }
}
export function materializeOfficeInsets(bytes:Uint8Array,limits:Limits={}):{bytes:Uint8Array;changed_properties:number;unsupported_parts:number;skip_reason?:OfficeInputSkipReason}{
  const limit=(requested:number|undefined,cap:number)=>{if(requested===undefined)return cap;if(!Number.isSafeInteger(requested)||requested<1||requested>cap)throw new DocverError('ZIP_LIMIT','Invalid renderer budget');return requested;};
  const partLimit=limit(limits.partBytes,MAX_PPTX_PART_BYTES),totalLimit=limit(limits.totalBytes,MAX_PPTX_EXPANDED_BYTES),zipLimit=limit(limits.zipBytes,MAX_INPUT_BYTES);
  if(bytes.length>zipLimit)throw new DocverError('ZIP_LIMIT','Render package exceeds limit');
  let total=0,ambiguous=false,signedPath=false;const seen=new Set<string>(),sizes=new Map<string,number>();
  // Scan/inflate only slide and OPC metadata first. Explicit-margin and other
  // unchanged inputs never inflate/repack their media for this preparation.
  const selected=unzipSync(bytes,{filter:entry=>{
    total+=entry.originalSize;if(total>totalLimit||entry.originalSize>partLimit||seen.size>=100000)throw new DocverError('ZIP_LIMIT','Render package exceeds limit');
    if(entry.name.startsWith('/')||entry.name.split('/').includes('..'))throw new DocverError('ZIP_PATH','Unsafe renderer package part');
    const key=entry.name.toLowerCase();if(seen.has(key))ambiguous=true;seen.add(key);sizes.set(entry.name,entry.originalSize);
    if(/^_xmlsignatures\//i.test(entry.name))signedPath=true;
    return slidePart(entry.name)||metadataPart(entry.name);
  }});
  let unsupported=0;
  const unchanged=(skip_reason?:OfficeInputSkipReason)=>({bytes,changed_properties:0,unsupported_parts:unsupported,...(skip_reason?{skip_reason}:{})});
  if(ambiguous)return unchanged('ambiguous_part_names');if(signedPath)return unchanged('signed_package');
  const signature=signatureMetadata(selected);if(signature)return unchanged(signature==='signature'?'signed_package':'unsupported_package_metadata');
  let count=0,derivedTotal=total;const replacements:Record<string,Uint8Array>={};
  for(const path of Object.keys(selected).filter(slidePart)){
    let xml:string;try{xml=readXml(selected[path]);}catch(error){if(error instanceof DocverError&&error.code==='XML_ENCODING_UNAVAILABLE')throw error;unsupported++;continue;}
    const derived=materializeXml(xml);if(derived.unsupported)unsupported++;if(!derived.count)continue;
    const data=encodeXml(derived.xml,selected[path]);derivedTotal+=data.length-sizes.get(path)!;
    if(data.length>partLimit||derivedTotal>totalLimit)return unchanged('derivation_budget_exceeded');
    replacements[path]=data;count+=derived.count;
  }
  if(!count)return unchanged();
  const parts=unzipSync(bytes),output:Zippable={};
  for(const [name,data]of Object.entries(parts))output[name]=[replacements[name]??data,{level:/(?:^|\/)media\//i.test(name)&&!/\.svg$/i.test(name)?0:6}];
  const prepared=zipSync(output,{mtime:new Date(1980,0,1)});
  return prepared.length>zipLimit?unchanged('derivation_budget_exceeded'):{bytes:prepared,changed_properties:count,unsupported_parts:unsupported};
}
