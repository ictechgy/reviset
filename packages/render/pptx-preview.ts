import { mkdir,readFile,writeFile,mkdtemp,rm,rename } from 'node:fs/promises';
import { join } from 'node:path';
import { getDocument } from 'pdfjs-dist/legacy/build/pdf.mjs';
import { unzipSync } from 'fflate';
import { convertPptx,officeFilter,validateRenderPackage } from './index.js';
import { pdfOptions } from '../ingest/pdf.js';
import { officeExecutable,visionInfo,runTool } from '../runtime/tools.js';
import { hash,byteHash,DocverError,type PageData } from '../schema/index.js';
import { captureNativePages,ocrEnvironment } from '../ingest/ocr.js';

let environmentPromise:Promise<string|undefined>|undefined;
export function officeEnvironment():Promise<string|undefined>{return environmentPromise??=(async()=>{
  const executable=officeExecutable();if(!executable)return undefined;
  const version=(await runTool(executable,['--version'],{timeout:30_000})).trim(),vision=await visionInfo();
  return JSON.stringify({version,binary_sha256:byteHash(await readFile(executable)),font_inventory_sha256:vision?.font_inventory_sha256??'unavailable',font_policy:'mac-system-and-user-fontconfig-v2',metadata_policy:'fixed-date-id-xmp-without-docchecksum-v3',input_policy:'validated-source-copy-and-xml-relationships-v4',os:vision?.os??process.platform,filter:officeFilter});
})();}
export async function preparePptxPreview(source:string,bytes:Uint8Array,pages:PageData[],cacheRoot:string,signal?:AbortSignal):Promise<Buffer|undefined>{
  validateRenderPackage(bytes);
  const environment=await officeEnvironment();if(!environment){for(const p of pages)p.coverage_gaps.push({feature:'preview',reason:'CONVERTER_UNAVAILABLE'});return;}
  const key=hash([byteHash(bytes),environment,'fixed-metadata-v1']),folder=join(cacheRoot,'pptx');await mkdir(folder,{recursive:true});
  const path=join(folder,key+'.pdf'),metadata=join(folder,key+'.json');let pdf:Buffer|undefined;
  try{const saved=JSON.parse(await readFile(metadata,'utf8')),candidate=await readFile(path);if(saved.key===key&&saved.sha256===byteHash(candidate))pdf=candidate;}catch{/* cache miss or corruption */}
  if(!pdf){pdf=await convertPptx(source,undefined,120_000,signal,bytes);const temp=await mkdtemp(join(folder,'stage-'));try{await writeFile(join(temp,'preview.pdf'),pdf);await writeFile(join(temp,'metadata.json'),JSON.stringify({key,sha256:byteHash(pdf)}));await rename(join(temp,'preview.pdf'),path);await rename(join(temp,'metadata.json'),metadata);}finally{await rm(temp,{recursive:true,force:true});}}
  const task=getDocument({...pdfOptions,data:new Uint8Array(pdf)});
  try{
    const doc=await task.promise;if(doc.numPages!==pages.length)throw new DocverError('PREVIEW_PAGE_MAPPING','Converted page count does not equal source slide count');
    const info=await visionInfo(),known=new Set((info?.font_families??[]).map((f:string)=>f.toLowerCase())),fonts=new Set<string>();
    const zip=unzipSync(bytes,{filter:e=>/^ppt\/(slides|slideLayouts|slideMasters|theme)\/[^/]+\.xml$/.test(e.name)});
    for(const value of Object.values(zip))for(const m of new TextDecoder().decode(value).matchAll(/<a:(?:latin|ea|cs)\b[^>]*typeface="([^"+][^"]*)"/g))fonts.add(m[1]);
    const missing=[...fonts].filter(f=>!known.has(f.toLowerCase())).sort();
    for(const p of pages){
      const rendered=await doc.getPage(p.page),v=rendered.getViewport({scale:1}),warnings=missing.map(f=>'font_substitution_possible:'+f);
      if(Math.abs((p.width/p.height)/(v.width/v.height)-1)>0.001)throw new DocverError('PREVIEW_GEOMETRY','Converted page aspect ratio differs from source slide');
      const content=await rendered.getTextContent(),text=content.items.flatMap(i=>'str'in i?[i.str]:[]).join('').replace(/\s/gu,'');
      const required=p.elements.filter(e=>e.text.trim()).map(e=>e.text.replace(/\s/gu,''));
      if(required.some(t=>!text.includes(t)))warnings.push('rendered_text_differs_from_ooxml_requires_source_review');
      if(p.elements.some(e=>e.kind==='unsupported'))warnings.push('chart_smartart_or_other_object_render_requires_review');
      p.preview={asset_id:'sha256:'+byteHash(pdf),page:p.page,width:v.width,height:v.height,source_transform:v.transform,renderer:'LibreOffice Impress PDF',environment,assessment:'inferred',warnings};
      p.capabilities.preview='available';p.coverage_gaps=p.coverage_gaps.filter(g=>g.reason!=='pptx_conversion_not_run');
      p.coverage_gaps.push({feature:'render_fidelity',reason:'libreoffice_conversion_not_powerpoint_pixel_equivalence'},...warnings.map(reason=>({feature:'render_fidelity',reason})));
      rendered.cleanup();
    }
    try{const environment=await ocrEnvironment(),rasters=await captureNativePages(pdf,pages.map(p=>p.page),[],{sourceFile:path,sourceHash:byteHash(pdf),cacheRoot,signal});for(const p of pages){const r=rasters.get(p.page);if(r)p.raster={sha256:r.render_sha256,width:r.width,height:r.height,renderer:r.renderer,environment};else p.coverage_gaps.push({feature:'raster_verification',reason:'native_preview_observation_failed'});}}
    catch(e){if(signal?.aborted||(e instanceof DocverError&&e.code==='CANCELLED'))throw e;for(const p of pages)p.coverage_gaps.push({feature:'raster_verification',reason:'native_preview_observation_failed'});}
    return pdf;
  }finally{await task.destroy();}
}
