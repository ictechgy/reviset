import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,mkdir,readFile,writeFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {preparePdfjs,PDFJS_VERSION,PDFJS_WORKER_UPSTREAM_SHA256,PDFJS_WORKER_PATCHED_SHA256} from '../../scripts/prepare-pdfjs.js';
import {createHash} from 'node:crypto';
import {pdfWorkerEnvironment} from '../../packages/runtime/pdfjs-environment.js';

test('PDF.js origin patch is pinned, idempotent, tamper rejecting and part of snapshot identity',async()=>{
  const folder=await mkdtemp(join(tmpdir(),'docver-pdfjs-origin-'));
  try{
    await mkdir(join(folder,'legacy/build'),{recursive:true});
    await writeFile(join(folder,'package.json'),JSON.stringify({version:PDFJS_VERSION}));
    const worker=await readFile(resolve('node_modules/pdfjs-dist/legacy/build/pdf.worker.mjs'));
    const upstream=worker.toString('utf8').replace(/^\/\/ DOCVER_EMBEDDED_FONT_ORIGIN_V1[^\n]*\n/,'')
      .replace('    this.docverEmbeddedFontProgram = !!file && !properties.isInternalFont;\n','')
      .replace('      extra: {\n        ...(this.fontExtraProperties ? this.#getExportData(EXPORT_DATA_EXTRA_PROPERTIES) : {}),\n        docverEmbeddedFontProgram: this.docverEmbeddedFontProgram === true\n      }','      extra: this.fontExtraProperties ? this.#getExportData(EXPORT_DATA_EXTRA_PROPERTIES) : undefined');
    assert.equal(createHash('sha256').update(upstream).digest('hex'),PDFJS_WORKER_UPSTREAM_SHA256);
    await writeFile(join(folder,'legacy/build/pdf.worker.mjs'),upstream);
    assert.equal((await preparePdfjs(folder)).worker_sha256,PDFJS_WORKER_PATCHED_SHA256);
    assert.equal((await preparePdfjs(folder)).worker_sha256,PDFJS_WORKER_PATCHED_SHA256);
    assert.deepEqual(await readFile(join(folder,'legacy/build/pdf.worker.mjs')),worker);
    assert.equal(await pdfWorkerEnvironment(),PDFJS_WORKER_PATCHED_SHA256);
    await writeFile(join(folder,'legacy/build/pdf.worker.mjs'),Buffer.concat([worker,Buffer.from('\n// unexpected edit')]));
    await assert.rejects(preparePdfjs(folder),/Unexpected PDF.js worker bytes/);
    await writeFile(join(folder,'package.json'),JSON.stringify({version:'6.4.300'}));
    await assert.rejects(preparePdfjs(folder),/Unsupported PDF.js patch version/);
  }finally{await rm(folder,{recursive:true,force:true});}
});
