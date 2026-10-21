import { mkdir,readFile,writeFile,mkdtemp,rm,rename } from 'node:fs/promises';
import { join } from 'node:path';
import { getDocument,Util } from 'pdfjs-dist/legacy/build/pdf.mjs';
import { unzipSync } from 'fflate';
import { convertPptxDetailed,officeFilter,validateRenderPackage,isolatedOfficeVersion,svgResourcePolicy,officeIsolationPolicy } from './index.js';
import { pdfOptions } from '../ingest/pdf.js';
import { officeExecutable,visionInfo } from '../runtime/tools.js';
import { hash,byteHash,normalize,DocverError,type PageData,type ElementData,type OfficeInputPreparationData } from '../schema/index.js';
import { captureNativePages,ocrEnvironment } from '../ingest/ocr.js';
import {officeInputPolicy} from './pptx-default-insets.js';
import {officeInputEnvironment,parseOfficeInputMetadata} from './office-input.js';
import {readXml,decodeXmlReferences} from '../xml/index.js';
import {XMLParser} from 'fast-xml-parser';

export function namedSourceFonts(parts:Uint8Array[]):string[]{
  const fonts=new Set<string>();
  const parser=new XMLParser({ignoreAttributes:false,preserveOrder:true,processEntities:false,parseTagValue:false,trimValues:false});
  const drawing=new Set(['http://schemas.openxmlformats.org/drawingml/2006/main','http://purl.oclc.org/ooxml/drawingml/main']);
  const walk=(parts:any[],parent:Map<string,string>):void=>{for(const part of parts){const attrs=part[':@']??{},bindings=Object.entries(attrs).filter(([key])=>key==='@_xmlns'||key.startsWith('@_xmlns:'));
    const namespaces=bindings.length?new Map(parent):parent;for(const [key,value]of bindings)namespaces.set(key==='@_xmlns'?'':key.slice(8),decodeXmlReferences(String(value)));
    for(const [tag,children]of Object.entries(part))if(Array.isArray(children)&&!tag.startsWith('#')){
      const colon=tag.indexOf(':'),prefix=colon<0?'':tag.slice(0,colon),local=colon<0?tag:tag.slice(colon+1);
      if(['latin','ea','cs'].includes(local)&&drawing.has(namespaces.get(prefix)??'')){const family=decodeXmlReferences(String(attrs['@_typeface']??''));if(family&&!family.startsWith('+'))fonts.add(family);}
      walk(children,namespaces);
    }
  }};
  for(const value of parts)walk(parser.parse(readXml(value)),new Map());
  return [...fonts].sort();
}

export function missingRenderedText(elements:ElementData[],fragments:{text:string;bbox:number[]}[]):boolean{
  const compact=(s:string)=>normalize(s).replace(/\s/gu,''),numbers=(s:string):string[]=>compact(s).match(/[+−-]?[0-9]+(?:[.,][0-9]+)*/g)??[];
  return elements.filter(e=>e.text.trim()).some(e=>{
    const b=e.bbox,local=fragments.filter(f=>{const x=f.bbox[0]+f.bbox[2]/2,y=f.bbox[1]+f.bbox[3]/2;return x>=b[0]-.015&&x<=b[0]+b[2]+.015&&y>=b[1]-.015&&y<=b[1]+b[3]+.015;}).map(f=>f.text).join(' ');
    const available=numbers(local);for(const token of numbers(e.text)){const index=available.indexOf(token);if(index<0)return true;available.splice(index,1);}
    return e.text.split(/\r?\n/).some(line=>!compact(local).includes(compact(line)));
  });
}
let environmentPromise:Promise<string|undefined>|undefined;
export function officeEnvironment():Promise<string|undefined>{
  if(!environmentPromise){const pending=(async()=>{const executable=officeExecutable();if(!executable)return undefined;
    try{const version=await isolatedOfficeVersion(executable),vision=await visionInfo();if(!vision)return undefined;
      return JSON.stringify({version,binary_sha256:byteHash(await readFile(executable)),font_inventory_sha256:vision?.font_inventory_sha256??'unavailable',font_policy:'mac-system-and-user-fontconfig-v2',source_font_policy:'ooxml-shared-xml-v1',svg_resource_policy:svgResourcePolicy,isolation_policy:officeIsolationPolicy,metadata_policy:'xref-scoped-direct-info-and-trailer-v4',input_policy:officeInputPolicy,input_preparation:await officeInputEnvironment(),os:vision?.os??process.platform,filter:officeFilter});
    }catch(e){if(e instanceof DocverError&&e.code==='CANCELLED')throw e;return undefined;}})();environmentPromise=pending;
    pending.then(value=>{if(!value&&environmentPromise===pending)environmentPromise=undefined;},()=>{if(environmentPromise===pending)environmentPromise=undefined;});}
  return environmentPromise;
}
export async function preparePptxPreview(source:string,bytes:Uint8Array,pages:PageData[],cacheRoot:string,signal?:AbortSignal):Promise<Buffer|undefined>{
  validateRenderPackage(bytes);
  const environment=await officeEnvironment();if(!environment){for(const p of pages)p.coverage_gaps.push({feature:'preview',reason:'CONVERTER_UNAVAILABLE'});return;}
  const sourceHash=byteHash(bytes),key=hash([sourceHash,environment,'fixed-metadata-v1']),folder=join(cacheRoot,'pptx');
  const path=join(folder,key+'.pdf'),metadata=join(folder,key+'.json');let pdf:Buffer|undefined,inputInfo:OfficeInputPreparationData|undefined,cacheWriteFailed=false,cacheCleanupFailed=false;
  try{const saved=JSON.parse(await readFile(metadata,'utf8')),candidate=await readFile(path),input=parseOfficeInputMetadata(saved.input,sourceHash);if(saved.key===key&&saved.sha256===byteHash(candidate)&&saved.input_hash===hash(input)){pdf=candidate;inputInfo=input;}}catch{/* cache miss or corruption */}
  if(!pdf){
    const converted=await convertPptxDetailed(source,undefined,120_000,signal,bytes);pdf=converted.pdf;inputInfo=converted.input;
    let staging:string|undefined;
    try{await mkdir(folder,{recursive:true,mode:0o700});staging=await mkdtemp(join(folder,'stage-'));await writeFile(join(staging,'preview.pdf'),pdf,{mode:0o600,signal});await writeFile(join(staging,'metadata.json'),JSON.stringify({key,sha256:byteHash(pdf),input:inputInfo,input_hash:hash(inputInfo)}),{mode:0o600,signal});signal?.throwIfAborted();await rename(join(staging,'preview.pdf'),path);await rename(join(staging,'metadata.json'),metadata);}
    catch(error){if(signal?.aborted||(error instanceof DocverError&&error.code==='CANCELLED'))throw error;cacheWriteFailed=true;}
    finally{if(staging)await rm(staging,{recursive:true,force:true}).catch(()=>{cacheCleanupFailed=true;});}
  }
  const task=getDocument({...pdfOptions,data:new Uint8Array(pdf)});
  try{
    const doc=await task.promise;if(doc.numPages!==pages.length)throw new DocverError('PREVIEW_PAGE_MAPPING','Converted page count does not equal source slide count');
    const info=await visionInfo(),known=new Set((info?.font_families??[]).map((f:string)=>f.toLowerCase()));
    const zip=unzipSync(bytes,{filter:e=>/^ppt\/(slides|slideLayouts|slideMasters|theme)\/[^/]+\.xml$/.test(e.name)});
    const missing=namedSourceFonts(Object.values(zip)).filter(f=>!known.has(f.toLowerCase()));
    for(const p of pages){
      const rendered=await doc.getPage(p.page),v=rendered.getViewport({scale:1}),warnings=missing.map(f=>'font_substitution_possible:'+f);
      if(Math.abs((p.width/p.height)/(v.width/v.height)-1)>0.001)throw new DocverError('PREVIEW_GEOMETRY','Converted page aspect ratio differs from source slide');
      const content=await rendered.getTextContent({disableNormalization:true}),fragments=content.items.flatMap(item=>{
        if(!('str'in item))return [];const t=Util.transform(v.transform,item.transform),height=Math.hypot(t[2],t[3]),angle=Math.atan2(t[1],t[0])+(content.styles[item.fontName]?.vertical?Math.PI/2:0),ascent=content.styles[item.fontName]?.ascent??.8;
        const corners=[[0,-height*ascent],[item.width,-height*ascent],[0,height*(1-ascent)],[item.width,height*(1-ascent)]].map(([x,y])=>[t[4]+Math.cos(angle)*x-Math.sin(angle)*y,t[5]+Math.sin(angle)*x+Math.cos(angle)*y]);
        const xs=corners.map(p=>p[0]),ys=corners.map(p=>p[1]);return [{text:item.str,bbox:[Math.min(...xs)/v.width,Math.min(...ys)/v.height,(Math.max(...xs)-Math.min(...xs))/v.width,(Math.max(...ys)-Math.min(...ys))/v.height]}];
      });
      if(missingRenderedText(p.elements,fragments))warnings.push('rendered_text_differs_from_ooxml_requires_source_review');
      if(p.elements.some(e=>e.kind==='unsupported'))warnings.push('chart_smartart_or_other_object_render_requires_review');
      if(inputInfo?.changed_properties)warnings.push('standard_text_insets_materialized');
      p.preview={asset_id:'sha256:'+byteHash(pdf),page:p.page,width:v.width,height:v.height,source_transform:v.transform,renderer:'LibreOffice Impress PDF',environment,assessment:'inferred',warnings,input_preparation:inputInfo};
      p.capabilities.preview='available';p.coverage_gaps=p.coverage_gaps.filter(g=>g.reason!=='pptx_conversion_not_run');
      p.coverage_gaps.push({feature:'render_fidelity',reason:'libreoffice_conversion_not_powerpoint_pixel_equivalence'},...warnings.map(reason=>({feature:'render_fidelity',reason})));
      if(inputInfo?.skip_reason)p.coverage_gaps.push({feature:'render_fidelity',reason:'standard_text_insets_skipped_'+inputInfo.skip_reason});
      if(inputInfo?.unsupported_parts)p.coverage_gaps.push({feature:'render_fidelity',reason:'standard_text_insets_unsupported_slide_parts_unchanged'});
      if(cacheWriteFailed)p.coverage_gaps.push({feature:'preview_cache',reason:'optional_cache_write_failed_render_retained'});
      if(cacheCleanupFailed)p.coverage_gaps.push({feature:'preview_cache',reason:'optional_cache_cleanup_failed_render_retained'});
      rendered.cleanup();
    }
    // The shared cache can be atomically replaced by another process. Native
    // observation must read a private copy of these exact verified PDF bytes.
    try{const environment=await ocrEnvironment(),rasters=await captureNativePages(pdf,pages.map(p=>p.page),[],{sourceHash:byteHash(pdf),cacheRoot,signal});for(const p of pages){const r=rasters.get(p.page);if(r){p.raster={sha256:r.render_sha256,width:r.width,height:r.height,renderer:r.renderer,environment};if(r.cache_write_failed)p.coverage_gaps.push({feature:'native_cache',reason:'optional_cache_write_failed_observations_retained'});}else p.coverage_gaps.push({feature:'raster_verification',reason:rasters.failures.get(p.page)??'native_preview_observation_failed'});}}
    catch(e){if(signal?.aborted||(e instanceof DocverError&&e.code==='CANCELLED'))throw e;for(const p of pages)p.coverage_gaps.push({feature:'raster_verification',reason:e instanceof DocverError?e.code:'native_preview_observation_failed'});}
    return pdf;
  }finally{await task.destroy();}
}
