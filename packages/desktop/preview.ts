import {createHash} from 'node:crypto';
import {join} from 'node:path';
import {readRegularFile} from '../runtime/regular-file.js';
import {DocverError,textChunk} from '../schema/index.js';
import {renderPdf} from '../render/index.js';
import {type DesktopService} from './service.js';

// A read-only projection for native clients without a system PDF control.
// Every resource is selected through a fixed report/page, never a caller path.
export async function pagePreview(service:DesktopService,library:string,input:{project_id:string;report_id:string;page_id:string;max_width:number}) {
  const {page,asset,reference}=service.pageData(input.project_id,input.report_id,input.page_id);
  const text=textChunk(page.text,0,65_536);
  const base={project_id:input.project_id,report_id:input.report_id,page_id:page.page_id,
    text,text_total_length:page.text.length,text_truncated:text.length!==page.text.length,
    text_length_unit:'utf16_code_units',coverage_gaps:page.coverage_gaps,
    width:page.width,height:page.height};
  const preview=reference?{asset_id:reference.asset_id,page:reference.page,source:'reference_pdf'}:
    page.preview?{asset_id:page.preview.asset_id,page:page.preview.page,source:'pptx_converted'}:
    asset.format==='pdf'?{asset_id:asset.asset_id,page:page.page,source:'original_pdf'}:undefined;
  if(!preview)return {...base,source:'pptx_structure',unavailable_reason:'Original PPTX rendering is unavailable; extracted structure is not an original page rendering.'};
  if(!/^sha256:[a-f0-9]{64}$/u.test(preview.asset_id))throw new DocverError('ASSET_ID','Invalid preview asset identity');
  const bytes=await readRegularFile(join(library,'assets',preview.asset_id.slice(7)));
  if(createHash('sha256').update(bytes).digest('hex')!==preview.asset_id.slice(7))throw new DocverError('ASSET_CORRUPT','Preview source SHA-256 does not match its fixed report');
  try {
    const png=await renderPdf(bytes,preview.page,input.max_width);
    if(png.length>8*1024*1024)throw new DocverError('RENDER_LIMIT','Native preview exceeds 8 MiB');
    return {...base,source:preview.source,png_base64:png.toString('base64'),width:png.readUInt32BE(16),height:png.readUInt32BE(20)};
  }catch(error){
    return {...base,source:preview.source,unavailable_reason:error instanceof DocverError?error.code:'PDF_PREVIEW_FAILED'};
  }
}
