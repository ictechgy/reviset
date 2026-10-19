import { mkdir,readFile,writeFile } from 'node:fs/promises';
import { join,resolve } from 'node:path';
import { createCanvas,loadImage } from '@napi-rs/canvas';
import { extractPptx } from '../packages/ingest/pptx.js';
import { extractPdf } from '../packages/ingest/pdf.js';
import { renderPdf } from '../packages/render/index.js';
import { preparePptxPreview } from '../packages/render/pptx-preview.js';
import { byteHash,ENGINE_VERSION } from '../packages/schema/index.js';
import {execFileSync} from 'node:child_process';
import {visionInfo} from '../packages/runtime/tools.js';
import {officeEnvironment} from '../packages/render/pptx-preview.js';
import {pdfWorkerEnvironment} from '../packages/runtime/pdfjs-environment.js';

const commit='faeca2bc29598744a62f787076d9e340e5095b8b',base=`https://raw.githubusercontent.com/developer0hye/office2pdf/${commit}/tests/golden_mocks/business/`,folder=resolve('output/office-reference');
await mkdir(folder,{recursive:true});
const sourceHead=execFileSync('git',['rev-parse','HEAD'],{encoding:'utf8'}).trim();
const clean=()=>!execFileSync('git',['diff','--binary','HEAD']).length&&!execFileSync('git',['ls-files','--others','--exclude-standard','-z']).length;
if(!clean())throw new Error('Office reference qualification requires frozen clean source');
const run=join(folder,'runs',sourceHead.slice(0,8));await mkdir(run,{recursive:true});
const manifestSha='4209c193deb0e6f24a2806aa152395364e558e131b0bd3419e0151cae636bd19';
const environment={head:sourceHead,source_clean:true,engine:ENGINE_VERSION,office:await officeEnvironment(),native:await visionInfo(),pdfjs_worker_sha256:await pdfWorkerEnvironment()};
async function fetchFile(path:string,expected?:string):Promise<Buffer>{
  if(!/^[a-zA-Z0-9_./-]+$/.test(path)||path.split('/').includes('..'))throw new Error('Unsafe fixture path');
  const local=join(folder,path);let bytes:Buffer|undefined;try{bytes=await readFile(local);}catch{/* fetch below */}
  if(!bytes||expected&&byteHash(bytes)!==expected){const response=await fetch(base+path,{redirect:'error',signal:AbortSignal.timeout(30000)});if(!response.ok)throw new Error(`Fixture HTTP ${response.status}: ${path}`);bytes=Buffer.from(await response.arrayBuffer());if(expected&&byteHash(bytes)!==expected)throw new Error('Fixture SHA mismatch: '+path);await mkdir(resolve(local,'..'),{recursive:true});await writeFile(local,bytes);}
  return bytes;
}
const manifestBytes=await fetchFile('manifest.json',manifestSha),manifest=JSON.parse(manifestBytes.toString()),cases=manifest.cases.filter((c:any)=>c.format==='pptx'),results:any[]=[];
await writeFile(join(run,'provenance.json'),JSON.stringify({repository:'https://github.com/developer0hye/office2pdf',commit,manifest_sha256:byteHash(manifestBytes),reference_provenance:manifest.provenance,usage:'Private validation cache; third-party fixtures not added to product or source distribution'},null,2));
for(const item of cases){
  const [source,reference]=await Promise.all([fetchFile(item.source,item.source_sha256),fetchFile(item.expected_pdf,item.expected_sha256)]);
  const output=join(run,item.id);await mkdir(output,{recursive:true});
  const pages=extractPptx(source,'sha256:'+byteHash(source)),converted=await preparePptxPreview(join(folder,item.source),source,pages,join(run,'cache'));
  if(!converted)throw new Error('Reference validation requires actual renderer');await writeFile(join(output,'converted.pdf'),converted);
  const actual=await extractPdf(converted,'sha256:'+byteHash(converted)),expected=await extractPdf(reference,'sha256:'+byteHash(reference));
  if(actual.length!==item.expected_pages||expected.length!==item.expected_pages)throw new Error('Reference page-count mismatch: '+item.id);
  const metrics=[];
  for(let n=1;n<=actual.length;n++){
    const [a,b]=await Promise.all([renderPdf(converted,n,1440),renderPdf(reference,n,1440)]),ia=await loadImage(a),ib=await loadImage(b),width=Math.max(ia.width,ib.width),height=Math.max(ia.height,ib.height),ca=createCanvas(width,height),cb=createCanvas(width,height),xa=ca.getContext('2d'),xb=cb.getContext('2d');
    for(const ctx of [xa,xb]){ctx.fillStyle='white';ctx.fillRect(0,0,width,height);}xa.drawImage(ia,0,0);xb.drawImage(ib,0,0);
    const pa=xa.getImageData(0,0,width,height).data,pb=xb.getImageData(0,0,width,height).data;let error=0,changed=0,anyChanged=0;
    for(let i=0;i<pa.length;i+=4){let difference=0;for(let c=0;c<3;c++){const delta=Math.abs(pa[i+c]-pb[i+c]);error+=delta;difference=Math.max(difference,delta);}if(difference>24)changed++;if(difference>0)anyChanged++;}
    await writeFile(join(output,`actual-${n}.png`),a);await writeFile(join(output,`powerpoint-${n}.png`),b);
    const needed=pages[n-1].elements.filter(e=>e.text.trim()).map(e=>e.text.replace(/\s/gu,'')),text=actual[n-1].text.replace(/\s/gu,'');
    metrics.push({page:n,actual_pixels:[ia.width,ia.height],reference_pixels:[ib.width,ib.height],geometry_matches:ia.width===ib.width&&ia.height===ib.height,mean_absolute_rgb_error:error/(width*height*3),changed_pixel_fraction:changed/(width*height),any_rgb_changed_pixel_fraction:anyChanged/(width*height),pixel_identical:ia.width===ib.width&&ia.height===ib.height&&anyChanged===0,source_text_present:needed.filter(t=>text.includes(t)).length,source_text_count:needed.length});
  }
  const row={id:item.id,locale:item.locale,pages:actual.length,expected_pages:item.expected_pages,required_fonts:item.required_fonts,warnings:[...new Set(pages.flatMap(p=>p.preview?.warnings??[]))],input_preparation:pages.map(p=>p.preview?.input_preparation),source_sha256:byteHash(source),reference_sha256:byteHash(reference),metrics};results.push(row);
  if(!clean()||execFileSync('git',['rev-parse','HEAD'],{encoding:'utf8'}).trim()!==sourceHead)throw new Error('Source changed during Office reference qualification');
  await writeFile(join(run,'result.json'),JSON.stringify({...environment,commit,reference:'Upstream-declared Microsoft PowerPoint16.111.1/macOS26.5.2 independent exports; pinned bytes verified',cases:results,completed:results.length===cases.length,scope:'Every geometry and RGB channel measured; both >24 and any-RGB difference reported. Pinned upstream corpus, not heldout or universal fidelity certification'},null,2));
  console.log(JSON.stringify({id:item.id,pages:actual.length,max_changed_pixel_fraction:Math.max(...metrics.map(m=>m.changed_pixel_fraction)),warnings:row.warnings.length}));
}
