import { readFile, stat } from 'node:fs/promises';
import { extname } from 'node:path';
import { Asset, byteHash, DocverError, type PageData } from '../schema/index.js';
import { extractPptx } from './pptx.js';
import { extractPdf } from './pdf.js';
import type { z } from 'zod';
export interface Extracted { asset:z.infer<typeof Asset>; pages:PageData[]; bytes:Uint8Array }
export async function ingest(path:string):Promise<Extracted> {
  const ext=extname(path).toLowerCase();
  if(!['.pptx','.pdf'].includes(ext)) throw new DocverError('UNSUPPORTED_FORMAT',ext==='.ppt'?'Legacy PPT unsupported':'Only .pptx and .pdf are supported');
  if((await stat(path)).size>50*1024*1024) throw new DocverError('FILE_LIMIT','Input exceeds 50 MiB checkpoint limit');
  const bytes=await readFile(path),asset=Asset.parse({asset_id:'sha256:'+byteHash(bytes),format:ext.slice(1),bytes:bytes.length});
  const pages=asset.format==='pptx'?extractPptx(bytes,asset.asset_id):await extractPdf(bytes,asset.asset_id);
  return {asset,pages,bytes};
}
