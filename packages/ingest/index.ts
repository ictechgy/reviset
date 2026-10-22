import { extname } from 'node:path';
import { Asset, Page, byteHash, DocverError, type PageData } from '../schema/index.js';
import { readRegularFile } from '../runtime/regular-file.js';
import { extractPptx } from './pptx.js';
import { extractPdf } from './pdf.js';
import type { z } from 'zod';
import type { OcrOptions } from './ocr.js';
export interface Extracted { asset:z.infer<typeof Asset>; pages:PageData[]; bytes:Uint8Array }
export interface IngestOptions extends OcrOptions {ocr?:'off'|'auto'|'all';expectedSha256?:string}
export async function ingest(path:string,options:IngestOptions={}):Promise<Extracted> {
  const ext=extname(path).toLowerCase();
  if(!['.pptx','.pdf'].includes(ext)) throw new DocverError('UNSUPPORTED_FORMAT',ext==='.ppt'?'Legacy PPT unsupported':'Only .pptx and .pdf are supported');
  let bytes:Buffer;
  try{bytes=await readRegularFile(path,{signal:options.signal});}
  catch(error){if(options.signal?.aborted)throw error;if(options.expectedSha256)throw new DocverError('SOURCE_CHANGED','Expected document input is no longer readable as a bounded regular file');throw error;}
  const digest=byteHash(bytes);
  if(options.expectedSha256&&digest!==options.expectedSha256)throw new DocverError('SOURCE_CHANGED','Document input no longer matches its expected original hash');
  const asset=Asset.parse({asset_id:'sha256:'+digest,format:ext.slice(1),bytes:bytes.length});
  const pages=asset.format==='pptx'?extractPptx(bytes,asset.asset_id):await extractPdf(bytes,asset.asset_id,options);
  const validated=pages.map(page=>{const result=Page.safeParse(page);if(!result.success)throw new DocverError('INVALID_PAGE_OBSERVATION','Extracted page '+page.page+' failed canonical validation');return result.data;});
  return {asset,pages:validated,bytes};
}
