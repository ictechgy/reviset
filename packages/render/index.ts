import {createHash} from 'node:crypto';
import { normalizeConvertedPdf } from './pdf-metadata.js';
import { createCanvas } from '@napi-rs/canvas';
import { getDocument } from 'pdfjs-dist/legacy/build/pdf.mjs';
import { mkdtemp, readFile, rm, mkdir,realpath,writeFile,rename } from 'node:fs/promises';
import { existsSync,realpathSync } from 'node:fs';
import { tmpdir,homedir } from 'node:os';
import { join, resolve,dirname,posix } from 'node:path';
import { pathToFileURL } from 'node:url';
import { pdfOptions } from '../ingest/pdf.js';
import { DocverError,MAX_PPTX_EXPANDED_BYTES,byteHash,type OfficeInputPreparationData } from '../schema/index.js';
import { runTool,officeExecutable } from '../runtime/tools.js';
import {officeZipDirectory,readOfficeZipPart} from '../runtime/office-zip.js';
import { XMLParser,XMLValidator } from 'fast-xml-parser';
import {prepareOfficeInput} from './office-input.js';
import {readXml,xmlDecoder,decodeXmlReferences} from '../xml/index.js';
export const officeFilter='pdf:impress_pdf_Export:'+JSON.stringify({ExportHiddenSlides:{type:'boolean',value:'true'},ExportNotesPages:{type:'boolean',value:'false'}});
export const svgResourcePolicy='fragment-only-no-xml-base-v1';
export const officeIsolationPolicy='isolated-env-profile-ipc-mach-no-directory-enumeration-v2';
export function validateRenderPackage(bytes:Uint8Array,depth=0,budget={total:0}):void{
  if(depth>2)throw new DocverError('ZIP_LIMIT','Nested render package exceeds limit');
  const entries=officeZipDirectory(bytes),parts=new Set(entries.map(entry=>entry.name));
  for(const entry of entries){budget.total+=entry.size;if(budget.total>MAX_PPTX_EXPANDED_BYTES)throw new DocverError('ZIP_LIMIT','Render package exceeds limit');}
  for(const entry of entries){
    // Every member is size/CRC checked, even when its semantic inspection is
    // unnecessary. Unselected XML/media cannot hide a different ZIP payload.
    const name=entry.name,value=readOfficeZipPart(bytes,entry);
    if(!(name.endsWith('.rels')||/\.svg$/i.test(name)||/(?:^|\/)media\//i.test(name)||/vbaProject|embeddings\//i.test(name)))continue;
    if(name.endsWith('/'))continue;
    if(/vbaProject|embeddings\/.*\.bin$/i.test(name))throw new DocverError('ACTIVE_CONTENT','Embedded executable/OLE content is not sent to the renderer');
    if(/embeddings\/.*\.xlsx$/i.test(name)){validateRenderPackage(value,depth+1,budget);continue;}
    if(/embeddings\//i.test(name))throw new DocverError('ACTIVE_CONTENT','Unsupported embedded object is not sent to the renderer');
    const svgName=/\.svg$/i.test(name),media=/(?:^|\/)media\//i.test(name);
    // Sniff media using its BOM, then validate any SVG as XML before it reaches
    // Office. Binary media remain binary; UTF16 SVG cannot hide behind .bin.
    const xmlLead=(code:number|undefined)=>code!==undefined&&[9,10,13,32,60].includes(code);
    const encoding=value[0]===0xff&&value[1]===0xfe||xmlLead(value[0])&&value[1]===0?'utf-16le':value[0]===0xfe&&value[1]===0xff||value[0]===0&&xmlLead(value[1])?'utf-16be':'utf-8';
    const mediaText=svgName||media?xmlDecoder(encoding,false).decode(value):'';
    if(svgName||media&&/<(?:[\w.-]+:)?svg\b/i.test(mediaText)){
      let source:string;try{source=readXml(value);}catch(error){if(error instanceof DocverError&&error.code==='XML_ENCODING_UNAVAILABLE')throw error;throw new DocverError('ACTIVE_CONTENT','Unsafe SVG is not sent to the renderer');}
      if(/<!DOCTYPE|<!ENTITY|<\s*(?:[\w.-]+:)?(?:script|foreignObject)\b|\bon[\w.-]+\s*=|@import|<\?xml-stylesheet/i.test(source)||XMLValidator.validate(source)!==true)throw new DocverError('ACTIVE_CONTENT','Unsafe SVG is not sent to the renderer');
      // CSS receives XML-decoded text. Inspect that text as well as the raw
      // resource guard, and refuse CSS escapes rather than interpreting them.
      const svg=new XMLParser({ignoreAttributes:false,preserveOrder:true,cdataPropName:'#cdata',processEntities:false,parseTagValue:false,trimValues:false}).parse(source);
      const literal=(value:any):string=>typeof value==='string'?value:Array.isArray(value)?value.map(literal).join(''):value&&typeof value==='object'?Object.values(value).map(literal).join(''):'';
      const text=(parts:any[]):string=>parts.map(part=>Object.entries(part).map(([key,value])=>key===':@'?'':key==='#text'?decodeXmlReferences(String(value)):key==='#cdata'?literal(value):Array.isArray(value)?text(value):'').join('')).join('');
      const checkCss=(css:string)=>{if(/\\|@import/i.test(css))throw new DocverError('ACTIVE_CONTENT','Unsupported SVG CSS is not sent to the renderer');
        const urls=/url/gi;
        while(urls.exec(css)){let open=urls.lastIndex;while(open<css.length&&/\s/u.test(css[open]))open++;
          if(css[open]!=='('){urls.lastIndex=open;continue;}
          let end=open+1,quote='';for(;end<css.length;end++){const char=css[end];if(quote){if(char===quote)quote='';}else if(char==='"'||char==="'")quote=char;else if(char===')')break;else if(char==='(')throw new DocverError('ACTIVE_CONTENT','Unsupported nested SVG resource');}
          if(end===css.length||quote)throw new DocverError('ACTIVE_CONTENT','Unterminated SVG resource');
          const target=css.slice(open+1,end).trim().replace(/^["']|["']$/g,'');if(!/^#[a-z0-9_.:-]+$/i.test(target))throw new DocverError('EXTERNAL_RELATIONSHIP','SVG external resources are not sent to the renderer');urls.lastIndex=end+1;
        }};
      const styles=(parts:any[]):void=>{for(const part of parts){for(const [key,value]of Object.entries(part[':@']??{})){
        const decoded=decodeXmlReferences(String(value));checkCss(decoded);
        if(key==='@_xml:base'&&decoded!=='')throw new DocverError('EXTERNAL_RELATIONSHIP','SVG base addresses are unsupported by the local resource policy');
        if(key.startsWith('@_')&&key.slice(2).split(':').at(-1)!.toLowerCase()==='href'&&!/^#[a-z0-9_.:-]+$/i.test(decoded.trim()))throw new DocverError('EXTERNAL_RELATIONSHIP','SVG external resources are not sent to the renderer');
      }
        for(const [key,value]of Object.entries(part))if(Array.isArray(value)){if(key.split(':').at(-1)!.toLowerCase()==='style')checkCss(text(value));styles(value);}
      }};styles(svg);
      continue;
    }
    if(!name.endsWith('.rels'))continue;
    let source:string;try{source=readXml(value);}catch(error){if(error instanceof DocverError&&error.code==='XML_ENCODING_UNAVAILABLE')throw error;throw new DocverError('INVALID_XML','Unsafe renderer relationship XML');}
    const decoded=(value:unknown)=>String(value??'').replace(/&(amp|lt|gt|quot|apos|#x[0-9a-f]+|#[0-9]+);/gi,(_,entity:string)=>{if(entity[0]==='#'){const code=entity[1].toLowerCase()==='x'?parseInt(entity.slice(2),16):Number(entity.slice(1));if(!code||code>0x10ffff||code>=0xd800&&code<=0xdfff)throw new DocverError('INVALID_XML','Invalid relationship character');return String.fromCodePoint(code);}return {amp:'&',lt:'<',gt:'>',quot:'"',apos:"'"}[entity.toLowerCase()]!;});
    const data=new XMLParser({ignoreAttributes:false,removeNSPrefix:true,processEntities:false}).parse(source),raw=data.Relationships?.Relationship,relationships=raw==null?[]:Array.isArray(raw)?raw:[raw];
    for(const rel of relationships){
      let target=decoded(rel['@_Target']).trim();try{target=decodeURIComponent(target);}catch{throw new DocverError('EXTERNAL_RELATIONSHIP','Malformed renderer relationship URI');}
      if(/[\u0000-\u001f\u007f]/u.test(target))throw new DocverError('EXTERNAL_RELATIONSHIP','Control character in renderer relationship URI');
      if(target.includes('\\')||target.startsWith('/')&&!parts.has(posix.normalize(target.slice(1)).split('#')[0]))throw new DocverError('EXTERNAL_RELATIONSHIP','Unsafe absolute renderer target');
      const external=decoded(rel['@_TargetMode']).trim().toLowerCase()==='external'||/^[a-z][a-z0-9+.-]*:|^\/\/|^\\/i.test(target);
      const hyperlink=decoded(rel['@_Type']).endsWith('/hyperlink')&&/^https?:|^mailto:/i.test(target);
      if(external&&!hyperlink)throw new DocverError('EXTERNAL_RELATIONSHIP','External resources are not sent to the renderer');
      const part=name.replace(/(^|\/)\_rels\//,'$1').replace(/\.rels$/,'');
      if(!external&&posix.normalize(posix.join(posix.dirname(part),target)).startsWith('../'))throw new DocverError('EXTERNAL_RELATIONSHIP','Renderer relationship leaves the package');
    }
  }
}
export { normalizeConvertedPdf } from './pdf-metadata.js';
export async function renderPdf(bytes:Uint8Array,pageNumber=1,maxWidth=960):Promise<Buffer> {
  const task=getDocument({...pdfOptions,data:new Uint8Array(bytes)});
  try {
    const doc=await task.promise,page=await doc.getPage(pageNumber),v=page.getViewport({scale:1});
    const viewport=page.getViewport({scale:Math.min(maxWidth/v.width,2)});
    if(viewport.width*viewport.height>16_000_000) throw new DocverError('RENDER_LIMIT','Page exceeds preview pixel limit');
    const canvas=createCanvas(Math.ceil(viewport.width),Math.ceil(viewport.height));
    await page.render({canvas:canvas as any,canvasContext:canvas.getContext('2d') as any,viewport}).promise;
    return canvas.toBuffer('image/png');
  } finally {await task.destroy();}
}
// LibreOffice26.8.1.1 dp_misc::generateOfficePipeId: UTF16 native-endian
// MD5 bytes formatted individually without leading zeroes. Only this unique
// private profile's IPC socket is allowed, never arbitrary Unix sockets.
export function officePipePath(folder:string){
  const digest=createHash('md5').update(Buffer.from(pathToFileURL(join(folder,'profile')).href,'utf16le')).digest();
  return '/private/tmp/OSL_PIPE_'+process.getuid!()+'_SingleOfficeIPC_'+[...digest].map(n=>n.toString(16)).join('');
}
export function rendererSandbox(folder:string,executable:string):string{
  const canonicalExecutable=realpathSync(executable),vendor=canonicalExecutable.endsWith('/Contents/MacOS/soffice')?resolve(dirname(canonicalExecutable),'../..'):dirname(canonicalExecutable);
  const readable=['/System','/usr/lib','/usr/share','/bin','/sbin','/private/etc','/private/var/db','/Library/Fonts',join(homedir(),'Library/Fonts'),vendor,folder,'/dev'];
  const pipe=officePipePath(folder);
  const jobAncestors:string[]=[];for(let p=dirname(folder);;p=dirname(p)){jobAncestors.push(p);if(p===dirname(p))break;}
  const services=['com.apple.CoreServices.coreservicesd','com.apple.logd','com.apple.windowserver.active','com.apple.coreservices.launchservicesd','com.apple.DiskArbitration.diskarbitrationd','com.apple.SystemConfiguration.configd','com.apple.system.notification_center','com.apple.system.opendirectoryd.libinfo','com.apple.distributed_notifications@Uv3'];
  return `(version 1)(allow default)(deny lsopen)(deny mach-lookup)(allow mach-lookup ${services.map(p=>`(global-name ${JSON.stringify(p)})`).join(' ')})(deny mach-register)(deny user-preference-write)(deny signal (target others))(deny system-debug)(deny process-exec)(allow process-exec (subpath ${JSON.stringify(vendor)}))(deny network*)(allow network* (local unix-socket (literal ${JSON.stringify(pipe)})) (remote unix-socket (literal ${JSON.stringify(pipe)})))(deny file-read-data)(allow file-read-data ${jobAncestors.map(p=>`(literal ${JSON.stringify(p)})`).join(' ')} (literal ${JSON.stringify(pipe)}))(allow file-read-data ${readable.map(p=>`(subpath ${JSON.stringify(p)})`).join(' ')})(deny file-write*)(allow file-write* (subpath "/dev") (literal "/private/tmp") (literal ${JSON.stringify(pipe)}) (subpath ${JSON.stringify(folder)}))(deny file-write* (subpath ${JSON.stringify(vendor)}))`;
}
export async function isolatedOfficeVersion(executable:string):Promise<string>{
  const folder=await realpath(await mkdtemp(join(tmpdir(),'docver-office-probe-')));
  try{return (await runTool(process.platform==='darwin'?'/usr/bin/sandbox-exec':executable,process.platform==='darwin'?['-p',rendererSandbox(folder,executable),executable,'--version']:['--version'],{timeout:30_000,cwd:folder,inheritEnv:false,env:{PATH:'/usr/bin:/bin:/usr/sbin:/sbin',LANG:'en_US.UTF-8',LC_ALL:'en_US.UTF-8',CFFIXED_USER_HOME:folder,HOME:folder,TMPDIR:folder+'/',XDG_CACHE_HOME:join(folder,'cache'),PYTHONDONTWRITEBYTECODE:'1'}})).trim();}
  finally{await rm(folder,{recursive:true,force:true});}
}
export async function convertPptx(path:string,executable=officeExecutable()??'soffice',timeout=120_000,signal?:AbortSignal,sourceBytes?:Uint8Array):Promise<Buffer> {
  return (await convertPptxDetailed(path,executable,timeout,signal,sourceBytes)).pdf;
}
export async function convertPptxDetailed(path:string,executable=officeExecutable()??'soffice',timeout=120_000,signal?:AbortSignal,sourceBytes?:Uint8Array):Promise<{pdf:Buffer;input:OfficeInputPreparationData}> {
  if(executable.includes('/')&&!existsSync(executable))throw new DocverError('CONVERTER_UNAVAILABLE','PPTX renderer executable not found');
  const folder=await realpath(await mkdtemp(join(tmpdir(),'docver-render-')));
  try {
    const output=join(folder,'output'); await mkdir(output);
    const input=sourceBytes??await readFile(path);validateRenderPackage(input);const copiedSource=join(folder,'input.pptx');await writeFile(copiedSource,input,{mode:0o600});
    const deadline=performance.now()+timeout,prepared=await prepareOfficeInput(folder,byteHash(input),Math.max(1,Math.min(30_000,deadline-performance.now())),signal);
    // Replace only the private job copy, retaining a stable converter filename.
    if(prepared.path!==copiedSource)await rename(prepared.path,copiedSource);
    const profile=join(folder,'profile');await mkdir(join(profile,'user'),{recursive:true});
    const xml=(s:string)=>s.replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('"','&quot;');
    const fontConfig=join(folder,'fonts.conf');
    await writeFile(fontConfig,'<?xml version="1.0"?><!DOCTYPE fontconfig SYSTEM "fonts.dtd"><fontconfig>'+['/System/Library/Fonts','/Library/Fonts',join(homedir(),'Library/Fonts'),resolve(dirname(executable),'../Resources/fonts')].map(p=>'<dir>'+xml(p)+'</dir>').join('')+'<cachedir>'+xml(join(folder,'font-cache'))+'</cachedir></fontconfig>');
    await import('node:fs/promises').then(fs=>fs.writeFile(join(profile,'user/registrymodifications.xcu'),'<?xml version="1.0"?><oor:items xmlns:oor="http://openoffice.org/2001/registry"><item oor:path="/org.openoffice.Office.Common/Security/Scripting"><prop oor:name="MacroSecurityLevel" oor:op="fuse"><value>3</value></prop></item><item oor:path="/org.openoffice.Office.Common/Misc"><prop oor:name="FirstRun" oor:op="fuse"><value>false</value></prop></item></oor:items>'));
    const args=[`-env:UserInstallation=${pathToFileURL(profile).href}`,'--headless','--norestore','--nodefault','--nofirststartwizard','--convert-to',officeFilter,'--outdir',output,copiedSource];
    // Deny document-controlled reads outside the source/job, vendor code and
    // explicit OS/font dependencies, including nested SVG/resource resolution.
    const sandbox=rendererSandbox(folder,executable);
    const remaining=deadline-performance.now();if(remaining<=0)throw new DocverError('TOOL_TIMEOUT','Renderer preparation exceeded conversion budget');
    await runTool(process.platform==='darwin'?'/usr/bin/sandbox-exec':executable,process.platform==='darwin'?['-p',sandbox,executable,...args]:args,{timeout:remaining,cwd:folder,signal,maxBytes:1024*1024,inheritEnv:false,env:{PATH:'/usr/bin:/bin:/usr/sbin:/sbin',LANG:'en_US.UTF-8',LC_ALL:'en_US.UTF-8',CFFIXED_USER_HOME:folder,HOME:folder,TMPDIR:folder+'/',XDG_CACHE_HOME:join(folder,'cache'),FONTCONFIG_FILE:fontConfig,FONTCONFIG_PATH:folder,PYTHONDONTWRITEBYTECODE:'1'}});
    return {pdf:normalizeConvertedPdf(await readFile(join(output,'input.pdf'))),input:prepared.metadata};
  } catch(e) {
    const err=e as NodeJS.ErrnoException&{killed?:boolean};
    if(e instanceof DocverError&&['EXTERNAL_RELATIONSHIP','ACTIVE_CONTENT','ZIP_LIMIT','ZIP_PATH','CANCELLED','XML_ENCODING_UNAVAILABLE'].includes(e.code))throw e;
    const failure=new DocverError(err.code==='ENOENT'?'CONVERTER_UNAVAILABLE':err.code==='TOOL_TIMEOUT'||err.killed?'CONVERTER_TIMEOUT':err.name==='AbortError'?'CANCELLED':'CONVERSION_FAILED',
      'PPTX preview conversion failed; structural observations remain usable');
    failure.cause=e;throw failure;
  } finally {await rm(folder,{recursive:true,force:true});}
}
