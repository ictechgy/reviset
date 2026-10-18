import { mkdir,readFile,writeFile } from 'node:fs/promises';
import { join,resolve } from 'node:path';
import { createCanvas,loadImage } from '@napi-rs/canvas';
import { extractPptx } from '../packages/ingest/pptx.js';
import { extractPdf } from '../packages/ingest/pdf.js';
import { renderPdf } from '../packages/render/index.js';
import { preparePptxPreview } from '../packages/render/pptx-preview.js';
import { byteHash } from '../packages/schema/index.js';

const commit='faeca2bc29598744a62f787076d9e340e5095b8b',base=`https://raw.githubusercontent.com/developer0hye/office2pdf/${commit}/tests/golden_mocks/business/`,folder=resolve('output/office-reference');
await mkdir(folder,{recursive:true});
async function fetchFile(path:string,expected?:string):Promise<Buffer>{
  if(!/^[a-zA-Z0-9_./-]+$/.test(path)||path.split('/').includes('..'))throw new Error('Unsafe fixture path');
  const local=join(folder,path);let bytes:Buffer|undefined;try{bytes=await readFile(local);}catch{/* fetch below */}
  if(!bytes||expected&&byteHash(bytes)!==expected){const response=await fetch(base+path);if(!response.ok)throw new Error(`Fixture HTTP ${response.status}: ${path}`);bytes=Buffer.from(await response.arrayBuffer());if(expected&&byteHash(bytes)!==expected)throw new Error('Fixture SHA mismatch: '+path);await mkdir(resolve(local,'..'),{recursive:true});await writeFile(local,bytes);}
  return bytes;
}
const manifestBytes=await fetchFile('manifest.json'),manifest=JSON.parse(manifestBytes.toString()),cases=manifest.cases.filter((c:any)=>c.format==='pptx'),results:any[]=[];
await writeFile(join(folder,'provenance.json'),JSON.stringify({repository:'https://github.com/developer0hye/office2pdf',commit,manifest_sha256:byteHash(manifestBytes),reference_provenance:manifest.provenance,usage:'Private validation cache; third-party fixtures not added to product or source distribution'},null,2));
for(const item of cases){
  const [source,reference]=await Promise.all([fetchFile(item.source,item.source_sha256),fetchFile(item.expected_pdf,item.expected_sha256)]);
  const output=join(folder,item.id);await mkdir(output,{recursive:true});
  const pages=extractPptx(source,'sha256:'+byteHash(source)),converted=await preparePptxPreview(join(folder,item.source),source,pages,join(folder,'cache'));
  if(!converted)throw new Error('Reference validation requires actual renderer');await writeFile(join(output,'converted.pdf'),converted);
  const actual=await extractPdf(converted,'sha256:'+byteHash(converted)),expected=await extractPdf(reference,'sha256:'+byteHash(reference));
  const metrics=[];
  for(let n=1;n<=Math.min(actual.length,expected.length);n++){
    const [a,b]=await Promise.all([renderPdf(converted,n,1440),renderPdf(reference,n,1440)]),ca=createCanvas(1440,810),cb=createCanvas(1440,810),xa=ca.getContext('2d'),xb=cb.getContext('2d');
    xa.drawImage(await loadImage(a),0,0,1440,810);xb.drawImage(await loadImage(b),0,0,1440,810);
    const pa=xa.getImageData(0,0,1440,810).data,pb=xb.getImageData(0,0,1440,810).data;let error=0,changed=0;
    for(let i=0;i<pa.length;i+=4){let difference=0;for(let c=0;c<3;c++){const delta=Math.abs(pa[i+c]-pb[i+c]);error+=delta;difference=Math.max(difference,delta);}if(difference>24)changed++;}
    await writeFile(join(output,`actual-${n}.png`),a);await writeFile(join(output,`powerpoint-${n}.png`),b);
    const needed=pages[n-1].elements.filter(e=>e.text.trim()).map(e=>e.text.replace(/\s/gu,'')),text=actual[n-1].text.replace(/\s/gu,'');
    metrics.push({page:n,mean_absolute_rgb_error:error/(1440*810*3),changed_pixel_fraction:changed/(1440*810),source_text_present:needed.filter(t=>text.includes(t)).length,source_text_count:needed.length});
  }
  const row={id:item.id,locale:item.locale,pages:actual.length,expected_pages:item.expected_pages,required_fonts:item.required_fonts,warnings:[...new Set(pages.flatMap(p=>p.preview?.warnings??[]))],metrics};results.push(row);
  await writeFile(join(folder,'result.json'),JSON.stringify({commit,reference:'Upstream-declared Microsoft PowerPoint16.111.1/macOS26.5.2 independent exports; pinned bytes verified',cases:results,scope:'Descriptive pixel differences, not an all-document or pixel-equivalence certification'},null,2));
  console.log(JSON.stringify({id:item.id,pages:actual.length,max_changed_pixel_fraction:Math.max(...metrics.map(m=>m.changed_pixel_fraction)),warnings:row.warnings.length}));
}
