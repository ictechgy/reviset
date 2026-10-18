import { createCanvas } from '@napi-rs/canvas';
import { getDocument } from 'pdfjs-dist/legacy/build/pdf.mjs';
import { mkdtemp, readFile, rm, mkdir,realpath,writeFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { tmpdir,homedir } from 'node:os';
import { join, resolve,dirname,posix } from 'node:path';
import { pathToFileURL } from 'node:url';
import { pdfOptions } from '../ingest/pdf.js';
import { DocverError,MAX_PPTX_EXPANDED_BYTES,MAX_PPTX_PART_BYTES } from '../schema/index.js';
import { runTool,officeExecutable } from '../runtime/tools.js';
import { unzipSync } from 'fflate';
import { XMLParser,XMLValidator } from 'fast-xml-parser';
export const officeFilter='pdf:impress_pdf_Export:'+JSON.stringify({ExportHiddenSlides:{type:'boolean',value:'true'},ExportNotesPages:{type:'boolean',value:'false'}});
export function validateRenderPackage(bytes:Uint8Array,depth=0,budget={total:0}):void{
  if(depth>2)throw new DocverError('ZIP_LIMIT','Nested render package exceeds limit');
  const parts=new Set<string>();
  const zip=unzipSync(bytes,{filter:e=>{parts.add(e.name);budget.total+=e.originalSize;if(budget.total>MAX_PPTX_EXPANDED_BYTES||e.originalSize>MAX_PPTX_PART_BYTES)throw new DocverError('ZIP_LIMIT','Render package exceeds limit');return e.name.endsWith('.rels')||/vbaProject|embeddings\//i.test(e.name);}});
  for(const [name,value] of Object.entries(zip)){
    if(name.endsWith('/'))continue;
    if(/vbaProject|embeddings\/.*\.bin$/i.test(name))throw new DocverError('ACTIVE_CONTENT','Embedded executable/OLE content is not sent to the renderer');
    if(/embeddings\/.*\.xlsx$/i.test(name)){validateRenderPackage(value,depth+1,budget);continue;}
    if(/embeddings\//i.test(name))throw new DocverError('ACTIVE_CONTENT','Unsupported embedded object is not sent to the renderer');
    if(!name.endsWith('.rels'))continue;
    const source=new TextDecoder().decode(value);if(/<!DOCTYPE|<!ENTITY/i.test(source)||XMLValidator.validate(source)!==true)throw new DocverError('INVALID_XML','Unsafe renderer relationship XML');
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
// Replace only fixed-width volatile metadata; byte offsets/xref and all drawing streams stay intact.
export function normalizeConvertedPdf(bytes:Buffer):Buffer{
  return Buffer.from(bytes.toString('latin1').replace(/\/(?:CreationDate|ModDate)\s*\(D:\d{14}[^)]*\)/g,s=>s.replace(/D:\d{14}/,'D:19700101000000')).replace(/\/ID\s*\[\s*<[a-f0-9]+>\s*<[a-f0-9]+>\s*\]/gi,s=>s.replace(/<[a-f0-9]+>/gi,t=>'<'+ '0'.repeat(t.length-2)+'>')).replace(/\/Type\s*\/Metadata[\s\S]*?\nendstream/g,s=>s.replace(/\b\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/g,'1970-01-01T00:00:00')).replace(/\/DocChecksum\s*\/[a-f0-9]+/gi,s=>' '.repeat(s.length)),'latin1');
}
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
export async function convertPptx(path:string,executable=officeExecutable()??'soffice',timeout=120_000,signal?:AbortSignal,sourceBytes?:Uint8Array):Promise<Buffer> {
  if(executable.includes('/')&&!existsSync(executable))throw new DocverError('CONVERTER_UNAVAILABLE','PPTX renderer executable not found');
  const folder=await realpath(await mkdtemp(join(tmpdir(),'docver-render-')));
  try {
    const output=join(folder,'output'); await mkdir(output);
    const input=sourceBytes??await readFile(path);validateRenderPackage(input);const copiedSource=join(folder,'input.pptx');await writeFile(copiedSource,input,{mode:0o600});
    const profile=join(folder,'profile');await mkdir(join(profile,'user'),{recursive:true});
    const xml=(s:string)=>s.replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('"','&quot;');
    const fontConfig=join(folder,'fonts.conf');
    await writeFile(fontConfig,'<?xml version="1.0"?><!DOCTYPE fontconfig SYSTEM "fonts.dtd"><fontconfig>'+['/System/Library/Fonts','/Library/Fonts',join(homedir(),'Library/Fonts'),resolve(dirname(executable),'../Resources/fonts')].map(p=>'<dir>'+xml(p)+'</dir>').join('')+'<cachedir>'+xml(join(folder,'font-cache'))+'</cachedir></fontconfig>');
    await import('node:fs/promises').then(fs=>fs.writeFile(join(profile,'user/registrymodifications.xcu'),'<?xml version="1.0"?><oor:items xmlns:oor="http://openoffice.org/2001/registry"><item oor:path="/org.openoffice.Office.Common/Security/Scripting"><prop oor:name="MacroSecurityLevel" oor:op="fuse"><value>3</value></prop></item><item oor:path="/org.openoffice.Office.Common/Misc"><prop oor:name="FirstRun" oor:op="fuse"><value>false</value></prop></item></oor:items>'));
    const args=[`-env:UserInstallation=${pathToFileURL(profile).href}`,'--headless','--norestore','--nodefault','--nofirststartwizard','--convert-to',officeFilter,'--outdir',output,copiedSource];
    // The native Mac renderer cannot make network requests or write outside its isolated job.
    const vendor=executable.endsWith('/Contents/MacOS/soffice')?resolve(dirname(executable),'../..'):undefined;
    const sandbox=`(version 1)(allow default)(deny network*)(allow network* (local unix-socket) (remote unix-socket))(deny file-write*)(allow file-write* (subpath "/dev") (subpath "/private/tmp") (subpath ${JSON.stringify(dirname(folder))}))${vendor?`(deny file-write* (subpath ${JSON.stringify(vendor)}))`:''}`;
    await runTool(process.platform==='darwin'?'/usr/bin/sandbox-exec':executable,process.platform==='darwin'?['-p',sandbox,executable,...args]:args,{timeout,signal,maxBytes:1024*1024,env:{HOME:folder,TMPDIR:folder,XDG_CACHE_HOME:join(folder,'cache'),FONTCONFIG_FILE:fontConfig,FONTCONFIG_PATH:folder,PYTHONDONTWRITEBYTECODE:'1'}});
    return normalizeConvertedPdf(await readFile(join(output,'input.pdf')));
  } catch(e) {
    const err=e as NodeJS.ErrnoException&{killed?:boolean};
    if(e instanceof DocverError&&['EXTERNAL_RELATIONSHIP','ACTIVE_CONTENT','ZIP_LIMIT','CANCELLED'].includes(e.code))throw e;
    throw new DocverError(err.code==='ENOENT'?'CONVERTER_UNAVAILABLE':err.code==='TOOL_TIMEOUT'||err.killed?'CONVERTER_TIMEOUT':err.name==='AbortError'?'CANCELLED':'CONVERSION_FAILED',
      'PPTX preview conversion failed; structural observations remain usable');
  } finally {await rm(folder,{recursive:true,force:true});}
}
