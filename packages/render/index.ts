import { createCanvas } from '@napi-rs/canvas';
import { getDocument } from 'pdfjs-dist/legacy/build/pdf.mjs';
import { mkdtemp, readFile, rm, mkdir } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, basename, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { pdfOptions } from '../ingest/pdf.js';
import { DocverError } from '../schema/index.js';
const execute=promisify(execFile);
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
export async function convertPptx(path:string,executable='soffice',timeout=30_000,signal?:AbortSignal):Promise<Buffer> {
  const folder=await mkdtemp(join(tmpdir(),'docver-render-'));
  try {
    const output=join(folder,'output'); await mkdir(output);
    await execute(executable,[`-env:UserInstallation=${pathToFileURL(join(folder,'profile')).href}`,'--headless','--convert-to','pdf','--outdir',output,resolve(path)],
      {timeout,signal,maxBuffer:1024*1024});
    return await readFile(join(output,basename(path).replace(/\.pptx$/i,'.pdf')));
  } catch(e) {
    const err=e as NodeJS.ErrnoException&{killed?:boolean};
    throw new DocverError(err.code==='ENOENT'?'CONVERTER_UNAVAILABLE':err.killed?'CONVERTER_TIMEOUT':err.name==='AbortError'?'CANCELLED':'CONVERSION_FAILED',
      'PPTX preview conversion failed; structural observations remain usable');
  } finally {await rm(folder,{recursive:true,force:true});}
}
