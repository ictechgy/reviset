import { readFile, stat } from 'node:fs/promises';
import { extname } from 'node:path';
import { Asset, byteHash, DocverError, MAX_INPUT_BYTES, type PageData } from '../schema/index.js';
import { extractPptx } from './pptx.js';
import { extractPdf } from './pdf.js';
import type { z } from 'zod';
import type { OcrOptions } from './ocr.js';
export interface Extracted { asset:z.infer<typeof Asset>; pages:PageData[]; bytes:Uint8Array }
export async function ingest(path:string,options:OcrOptions&{ocr?:'off'|'auto'|'all'}={}):Promise<Extracted> {
  const ext=extname(path).toLowerCase();
  if(!['.pptx','.pdf'].includes(ext)) throw new DocverError('UNSUPPORTED_FORMAT',ext==='.ppt'?'Legacy PPT unsupported':'Only .pptx and .pdf are supported');
  if((await stat(path)).size>MAX_INPUT_BYTES) throw new DocverError('FILE_LIMIT','Input exceeds 512 MiB limit');
  const bytes=await readFile(path);if(bytes.length>MAX_INPUT_BYTES)throw new DocverError('FILE_LIMIT','Input exceeds 512 MiB limit');
  const asset=Asset.parse({asset_id:'sha256:'+byteHash(bytes),format:ext.slice(1),bytes:bytes.length});
  const pages=asset.format==='pptx'?extractPptx(bytes,asset.asset_id):await extractPdf(bytes,asset.asset_id,options);
  return {asset,pages,bytes};
}
