import {readFile,writeFile,rename,rm} from 'node:fs/promises';
import {createHash,randomUUID} from 'node:crypto';
import {createRequire} from 'node:module';
import {dirname,join} from 'node:path';

const require=createRequire(import.meta.url);
export const PDFJS_VERSION='6.4.299';
export const PDFJS_WORKER_UPSTREAM_SHA256='bb422f60804477de4a0b09091d8347a916a387755ed1cbad24ccaec1d09c78bf';
export const PDFJS_WORKER_LEGACY_SHA256='8f63f23a466f9fa448f0ced94dc8cf06f024014a3fe1c9bbcc3155f65f105107';
export const PDFJS_WORKER_PATCHED_SHA256='4c5cce3000bfe13fb39083127c6b9083aa199bf076febf11c5b5eae913f9ae45';
const notice='// DOCVER_FONT_ORIGIN_METRICS_V2: Modified by Docver to expose embedded font-program origin and bounded font metrics; see scripts/prepare-pdfjs.ts.\n';
const originalExtra='      extra: this.fontExtraProperties ? this.#getExportData(EXPORT_DATA_EXTRA_PROPERTIES) : undefined';
const legacyExtra='      extra: {\n        ...(this.fontExtraProperties ? this.#getExportData(EXPORT_DATA_EXTRA_PROPERTIES) : {}),\n        docverEmbeddedFontProgram: this.docverEmbeddedFontProgram === true\n      }';
const originAssignment='    this.docverEmbeddedFontProgram = !!file && !properties.isInternalFont;';
const hash=(bytes:Uint8Array|string)=>createHash('sha256').update(bytes).digest('hex');

// Build-time only. Never mutate dependencies from a signed app at runtime.
// A new PDF.js version or any unexpected bytes require an explicit source review.
export async function preparePdfjs(packageRoot=dirname(require.resolve('pdfjs-dist/package.json'))){
  const metadata=JSON.parse(await readFile(join(packageRoot,'package.json'),'utf8'));
  if(metadata.version!==PDFJS_VERSION)throw new Error('Unsupported PDF.js patch version: '+metadata.version);
  const path=join(packageRoot,'legacy/build/pdf.worker.mjs'),bytes=await readFile(path),sha=hash(bytes);
  if(sha===PDFJS_WORKER_PATCHED_SHA256)return {version:PDFJS_VERSION,upstream_sha256:PDFJS_WORKER_UPSTREAM_SHA256,worker_sha256:sha,patch:'DOCVER_FONT_ORIGIN_METRICS_V2'};
  if(![PDFJS_WORKER_UPSTREAM_SHA256,PDFJS_WORKER_LEGACY_SHA256].includes(sha))throw new Error('Unexpected PDF.js worker bytes; refusing patch: '+sha);
  let source=bytes.toString('utf8');
  if(sha===PDFJS_WORKER_LEGACY_SHA256){
    source=source.replace(/^\/\/ DOCVER_EMBEDDED_FONT_ORIGIN_V1[^\n]*\n/,'').replace(originAssignment+'\n','').replace(legacyExtra,originalExtra);
    if(hash(source)!==PDFJS_WORKER_UPSTREAM_SHA256)throw new Error('PDF.js legacy migration did not reproduce pinned upstream');
  }
  for(const [before,after] of [
    ['    this.fontExtraProperties = evaluatorOptions.fontExtraProperties;',
      '    this.fontExtraProperties = evaluatorOptions.fontExtraProperties;\n    this.docverEmbeddedFontProgram = !!file && !properties.isInternalFont;'],
    [originalExtra,
      '      extra: {\n        ...(this.fontExtraProperties ? this.#getExportData(EXPORT_DATA_EXTRA_PROPERTIES) : {}),\n        docverEmbeddedFontProgram: this.docverEmbeddedFontProgram === true,\n        docverFontMetrics: Number.isFinite(this.ascent) && Number.isFinite(this.descent) && this.ascent > 0 && this.descent <= 0 && this.ascent - this.descent >= 0.5 ? { ascent: this.ascent, descent: this.descent } : undefined\n      }']
  ]){
    if(source.split(before).length!==2)throw new Error('PDF.js patch anchor is not unique');
    source=source.replace(before,after);
  }
  source=notice+source;
  if(hash(source)!==PDFJS_WORKER_PATCHED_SHA256)throw new Error('PDF.js patched worker fingerprint mismatch: '+hash(source));
  const temp=path+'.'+randomUUID()+'.tmp';
  try{await writeFile(temp,source,{flag:'wx'});await rename(temp,path);}finally{await rm(temp,{force:true});}
  return {version:PDFJS_VERSION,upstream_sha256:PDFJS_WORKER_UPSTREAM_SHA256,worker_sha256:hash(source),patch:'DOCVER_FONT_ORIGIN_METRICS_V2'};
}
