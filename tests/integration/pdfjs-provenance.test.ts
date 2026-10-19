import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,mkdir,readFile,writeFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {preparePdfjs,PDFJS_VERSION,PDFJS_WORKER_UPSTREAM_SHA256,PDFJS_WORKER_PATCHED_SHA256,PDFJS_WORKER_LEGACY_SHA256} from '../../scripts/prepare-pdfjs.js';
import {createHash} from 'node:crypto';
import {pdfWorkerEnvironment} from '../../packages/runtime/pdfjs-environment.js';
import {analyze} from '../../packages/engine/index.js';
import {Store} from '../../packages/storage/index.js';
import {id} from '../../packages/schema/index.js';
import PDFDocument from 'pdfkit';
import {getDocument,OPS} from 'pdfjs-dist/legacy/build/pdf.mjs';
import {pdfOptions} from '../../packages/ingest/pdf.js';

await preparePdfjs();

test('PDF.js origin patch is pinned, idempotent, tamper rejecting and part of snapshot identity',async()=>{
  const folder=await mkdtemp(join(tmpdir(),'docver-pdfjs-origin-'));
  try{
    await mkdir(join(folder,'legacy/build'),{recursive:true});
    await writeFile(join(folder,'package.json'),JSON.stringify({version:PDFJS_VERSION}));
    const worker=await readFile(resolve('node_modules/pdfjs-dist/legacy/build/pdf.worker.mjs'));
    const upstream=worker.toString('utf8').replace(/^\/\/ DOCVER_FONT_ORIGIN_METRICS_V2[^\n]*\n/,'')
      .replace('    this.docverEmbeddedFontProgram = !!file && !properties.isInternalFont;\n','')
      .replace('      extra: {\n        ...(this.fontExtraProperties ? this.#getExportData(EXPORT_DATA_EXTRA_PROPERTIES) : {}),\n        docverEmbeddedFontProgram: this.docverEmbeddedFontProgram === true,\n        docverFontMetrics: Number.isFinite(this.ascent) && Number.isFinite(this.descent) && this.ascent > 0 && this.descent <= 0 && this.ascent - this.descent >= 0.5 ? { ascent: this.ascent, descent: this.descent } : undefined\n      }','      extra: this.fontExtraProperties ? this.#getExportData(EXPORT_DATA_EXTRA_PROPERTIES) : undefined');
    assert.equal(createHash('sha256').update(upstream).digest('hex'),PDFJS_WORKER_UPSTREAM_SHA256);
    await writeFile(join(folder,'legacy/build/pdf.worker.mjs'),upstream);
    assert.equal((await preparePdfjs(folder)).worker_sha256,PDFJS_WORKER_PATCHED_SHA256);
    assert.equal((await preparePdfjs(folder)).worker_sha256,PDFJS_WORKER_PATCHED_SHA256);
    assert.deepEqual(await readFile(join(folder,'legacy/build/pdf.worker.mjs')),worker);
    const legacy='// DOCVER_EMBEDDED_FONT_ORIGIN_V1: Modified by Docver to expose embedded font-program origin; see scripts/prepare-pdfjs.ts.\n'+upstream
      .replace('    this.fontExtraProperties = evaluatorOptions.fontExtraProperties;','    this.fontExtraProperties = evaluatorOptions.fontExtraProperties;\n    this.docverEmbeddedFontProgram = !!file && !properties.isInternalFont;')
      .replace('      extra: this.fontExtraProperties ? this.#getExportData(EXPORT_DATA_EXTRA_PROPERTIES) : undefined','      extra: {\n        ...(this.fontExtraProperties ? this.#getExportData(EXPORT_DATA_EXTRA_PROPERTIES) : {}),\n        docverEmbeddedFontProgram: this.docverEmbeddedFontProgram === true\n      }');
    assert.equal(createHash('sha256').update(legacy).digest('hex'),PDFJS_WORKER_LEGACY_SHA256);
    await writeFile(join(folder,'legacy/build/pdf.worker.mjs'),legacy);
    assert.equal((await preparePdfjs(folder)).worker_sha256,PDFJS_WORKER_PATCHED_SHA256);
    assert.deepEqual(await readFile(join(folder,'legacy/build/pdf.worker.mjs')),worker);
    assert.equal(await pdfWorkerEnvironment(),PDFJS_WORKER_PATCHED_SHA256);
    await writeFile(join(folder,'legacy/build/pdf.worker.mjs'),Buffer.concat([worker,Buffer.from('\n// unexpected edit')]));
    await assert.rejects(preparePdfjs(folder),/Unexpected PDF.js worker bytes/);
    await writeFile(join(folder,'package.json'),JSON.stringify({version:'6.4.300'}));
    await assert.rejects(preparePdfjs(folder),/Unsupported PDF.js patch version/);
  }finally{await rm(folder,{recursive:true,force:true});}
});

test('worker exports only bounded origin and actual finite metrics for embedded and substitute fonts',async()=>{
  for(const embedded of [false,true]){
    const doc=new PDFDocument(),chunks:Buffer[]=[];doc.on('data',b=>chunks.push(b));const done=new Promise<Buffer>(r=>doc.on('end',()=>r(Buffer.concat(chunks))));if(embedded)doc.font(resolve('node_modules/pdfjs-dist/standard_fonts/LiberationSans-Regular.ttf'));doc.text('Embedded origin');doc.end();
    const task=getDocument({...pdfOptions,disableFontFace:true,data:new Uint8Array(await done)});
    try{const pdf=await task.promise,page=await pdf.getPage(1),ops=await page.getOperatorList(),i=ops.fnArray.indexOf(OPS.setFont),font=(page.commonObjs as any).get(ops.argsArray[i][0]),content=await page.getTextContent(),style=content.styles[ops.argsArray[i][0]];assert.equal(font.docverEmbeddedFontProgram,embedded);assert.deepEqual(Object.keys(font.docverFontMetrics).sort(),['ascent','descent']);assert.equal(font.docverFontMetrics.ascent,style.ascent);assert.equal(font.docverFontMetrics.descent,style.descent);for(const key of ['cMap','vmetrics','systemFontInfo','data','tables'])assert.ok(!Object.hasOwn(font,key),'Full font metadata must not be exported: '+key);}
    finally{await task.destroy();}
  }
});

test('actual worker hash is present in an analyzed immutable report identity',async()=>{
  const folder=await mkdtemp(join(tmpdir(),'docver-worker-report-')),store=new Store(join(folder,'store'));
  try{
    const doc=new PDFDocument(),chunks:Buffer[]=[];doc.on('data',b=>chunks.push(b));const done=new Promise<Buffer>(r=>doc.on('end',()=>r(Buffer.concat(chunks))));doc.text('Worker identity');doc.end();await writeFile(join(folder,'input.pdf'),await done);
    const {report}=await analyze({project_id:'prj_worker_identity',title:'Worker identity',revisions:[{label:'v1',files:['input.pdf']}],mapping_decisions:[]},folder,store,undefined,undefined,{ocr:'off'});
    assert.equal(report.observation_environment.pdfjs_worker_sha256,PDFJS_WORKER_PATCHED_SHA256);assert.equal(report.changes.length,0);
    const {report_id,...base}=report;assert.equal(report_id,id('rpt',base));
    assert.notEqual(report_id,id('rpt',{...base,observation_environment:{...base.observation_environment,pdfjs_worker_sha256:PDFJS_WORKER_UPSTREAM_SHA256}}),'Worker bytes change identity even without any text/visibility delta');
    assert.equal(store.report(report.project_id,report.report_id).observation_environment.pdfjs_worker_sha256,PDFJS_WORKER_PATCHED_SHA256);
  }finally{store.close();await rm(folder,{recursive:true,force:true});}
});
