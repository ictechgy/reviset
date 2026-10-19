import {XMLValidator} from 'fast-xml-parser';
import {DocverError} from '../schema/index.js';
export const MAX_XML_DEPTH=100;
// Shared by the Node engine and its isolated renderer-preparation process.
export function xmlDecoder(encoding:string,fatal=true):TextDecoder {
  try{return new TextDecoder(encoding,{fatal});}
  catch{throw new DocverError('XML_ENCODING_UNAVAILABLE','OOXML character decoder is unavailable');}
}

// OPC XML parts use UTF-8 or BOM-marked UTF-16 (XML1.0 §4.3.3).
// A malformed byte sequence must never silently change the observed source.
export function decodeXml(bytes:Uint8Array):string {
  const encoding=bytes[0]===0xff&&bytes[1]===0xfe?'utf-16le':bytes[0]===0xfe&&bytes[1]===0xff?'utf-16be':'utf-8';
  const decoder=xmlDecoder(encoding);
  let source:string;
  try{source=decoder.decode(bytes);}
  catch{throw new DocverError('INVALID_XML','Invalid OOXML character encoding');}
  if(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\ufffe\uffff]/u.test(source))throw new DocverError('INVALID_XML','Forbidden XML character');
  if(source.startsWith('<?xml')&&/[ \t\r\n]/.test(source[5]??'')){
    const end=source.indexOf('?>');
    if(end<0)throw new DocverError('INVALID_XML','Unterminated XML declaration');
    const declared=source.slice(0,end).match(/\bencoding[ \t\r\n]*=[ \t\r\n]*(['"])([^'"]*)\1/)?.[2]?.toUpperCase();
    if(declared&&declared!=='UTF-8'&&declared!=='UTF-16')throw new DocverError('XML_ENCODING_UNSUPPORTED','OOXML encoding must be UTF-8 or UTF-16');
    if(declared&&((declared==='UTF-8')!==(encoding==='utf-8')))throw new DocverError('INVALID_XML','OOXML encoding declaration does not match its bytes');
  }
  return source;
}
export function xmlCharacter(cp:number):boolean {
  return cp===0x9||cp===0xa||cp===0xd||cp>=0x20&&cp<=0xd7ff||cp>=0xe000&&cp<=0xfffd||cp>=0x10000&&cp<=0x10ffff;
}
export function decodeXmlReferences(text:string):string {
  return text.replace(/&(amp|lt|gt|quot|apos|#x[0-9a-fA-F]+|#[0-9]+);/g,(_match,key:string)=>{
    if(key[0]!=='#')return ({amp:'&',lt:'<',gt:'>',quot:'"',apos:"'"} as Record<string,string>)[key];
    const cp=key[1]==='x'?parseInt(key.slice(2),16):Number(key.slice(1));
    if(!xmlCharacter(cp))throw new DocverError('INVALID_XML','Forbidden XML character reference');return String.fromCodePoint(cp);
  });
}
function checkXmlReferences(source:string){
  let cursor=0;
  while(cursor<source.length){
    const start=source.indexOf('&',cursor);if(start<0)break;
    if(source[start+1]!=='#'){
      const entity=['amp;','lt;','gt;','quot;','apos;'].find(name=>source.startsWith(name,start+1));
      if(!entity)throw new DocverError('INVALID_XML','Malformed XML entity reference');
      cursor=start+1+entity.length;continue;
    }
    let end=start+2;const hex=source[end]==='x';if(hex)end++;
    const digits=end;
    for(;end<source.length;end++){
      const code=source.charCodeAt(end);
      if(!(code>=48&&code<=57||hex&&(code>=65&&code<=70||code>=97&&code<=102)))break;
    }
    if(end===digits||source[end]!==';')throw new DocverError('INVALID_XML','Malformed XML character reference');
    const cp=hex?parseInt(source.slice(digits,end),16):Number(source.slice(digits,end));
    if(!xmlCharacter(cp))throw new DocverError('INVALID_XML','Forbidden XML character reference');
    cursor=end+1;
  }
}
function checkXmlMarkup(source:string){
  let cursor=0,depth=0;
  while(cursor<source.length){
    const open=source.indexOf('<',cursor);checkXmlReferences(source.slice(cursor,open<0?source.length:open));if(open<0)break;
    let delimiter:string|undefined,contentStart=open;
    if(source.startsWith('<!--',open)){delimiter='-->';contentStart=open+4;}
    else if(source.startsWith('<![CDATA[',open)){delimiter=']]>';contentStart=open+9;}
    else if(source.startsWith('<?',open)){delimiter='?>';contentStart=open+2;}
    if(delimiter){const end=source.indexOf(delimiter,contentStart);if(end<0)throw new DocverError('INVALID_XML','Unterminated XML data');cursor=end+delimiter.length;continue;}
    if(source.startsWith('<!',open)){
      const declaration=source.slice(open,open+9).toUpperCase();
      if(declaration.startsWith('<!DOCTYPE')||declaration.startsWith('<!ENTITY'))throw new DocverError('XML_DTD','DTD/entity declarations are unsupported');
      throw new DocverError('INVALID_XML','Unsupported XML declaration');
    }
    let end=open+1,quote='';
    for(;end<source.length;end++){
      const char=source[end];
      // XMLValidator accepts raw '<' in quoted attributes; XML1.0 does not.
      // Never rescan that value as a comment, PI, CDATA or another tag.
      if(char==='<')throw new DocverError('INVALID_XML','Invalid XML attribute or tag');
      if(quote){if(char===quote)quote='';}
      else if(char==='"'||char==="'")quote=char;
      else if(char==='>')break;
    }
    if(end===source.length||quote)throw new DocverError('INVALID_XML','Unterminated XML tag');
    checkXmlReferences(source.slice(open,end+1));
    if(source[open+1]==='/')depth--;else if(source[end-1]!=='/')depth++;
    if(depth<0)throw new DocverError('INVALID_XML','Unbalanced XML tags');
    if(depth>MAX_XML_DEPTH)throw new DocverError('XML_DEPTH','XML nesting exceeds limit');
    cursor=end+1;
  }
  if(depth!==0)throw new DocverError('INVALID_XML','Unbalanced XML tags');
}

export function readXml(bytes:Uint8Array):string {
  const source=decodeXml(bytes);checkXmlMarkup(source);
  if(XMLValidator.validate(source)!==true)throw new DocverError('INVALID_XML','Malformed OOXML');
  return source;
}
// Only an explicitly derived renderer copy uses this encoder. Preserve its
// original byte order/BOM and declaration; untouched parts remain byte-exact.
export function encodeXml(source:string,original:Uint8Array):Uint8Array {
  const little=original[0]===0xff&&original[1]===0xfe,big=original[0]===0xfe&&original[1]===0xff;
  if(little||big){const content=Buffer.from(source,'utf16le');if(big)content.swap16();return Buffer.concat([Buffer.from(little?[0xff,0xfe]:[0xfe,0xff]),content]);}
  const content=Buffer.from(source,'utf8');return original[0]===0xef&&original[1]===0xbb&&original[2]===0xbf?Buffer.concat([Buffer.from([0xef,0xbb,0xbf]),content]):content;
}
