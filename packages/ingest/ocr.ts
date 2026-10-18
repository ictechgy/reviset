import { z } from 'zod';
import { mkdtemp,mkdir,readFile,writeFile,rm,rename } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { Bbox,box,byteHash,hash,id,normalize,type PageData,type ElementData,DocverError } from '../schema/index.js';
import { runTool,visionExecutable,visionInfo } from '../runtime/tools.js';

const Candidate=z.object({text:z.string(),confidence:z.number().min(0).max(1)});
const Result=z.object({version:z.string(),revision:z.number(),languages:z.array(z.string()),language_correction:z.literal(false),ocr_performed:z.boolean(),renderer:z.string(),verification:z.string(),viewport_width:z.number().positive(),viewport_height:z.number().positive(),rotation:z.number(),width:z.number().int().positive().max(4096),height:z.number().int().positive().max(4096),render_sha256:z.string().regex(/^[a-f0-9]{64}$/),structure_status:z.string().optional(),structure_engine:z.string().optional(),tables:z.array(z.object({cells:z.array(z.object({row:z.number().int().nonnegative(),column:z.number().int().nonnegative(),row_span:z.number().int().positive(),column_span:z.number().int().positive(),text:z.string(),bbox:Bbox})).max(20000)})).max(200).optional(),
  lines:z.array(Candidate.extend({bbox:Bbox,strike_candidate:z.boolean(),strike_bbox:Bbox,numeric_consensus:z.boolean(),numeric_readings:z.array(z.string()),tokens:z.array(z.object({text:z.string(),bbox:Bbox})),alternatives:z.array(Candidate).max(3)})).max(20000)});
export type NativePageResult=z.infer<typeof Result>;
export type OcrOptions={cacheRoot?:string;signal?:AbortSignal;sourceFile?:string;sourceHash?:string;nativeResult?:NativePageResult;onPage?:(current:number,total:number)=>void};
export async function ocrEnvironment():Promise<string>{const info=await visionInfo();return info?hash(info):'unavailable';}
export async function recognizePdf(bytes:Uint8Array,page:number,options:OcrOptions={}):Promise<z.infer<typeof Result>>{
  const result=(await captureNativePages(bytes,[page],[page],options)).get(page);if(!result)throw new DocverError('OCR_FAILED','Native page observation failed');return result;
}
export async function captureNativePages(bytes:Uint8Array,pages:number[],ocrPages:number[],options:OcrOptions={}):Promise<Map<number,NativePageResult>>{
  const executable=visionExecutable();if(!executable)throw new DocverError('OCR_UNAVAILABLE','Native OCR helper is unavailable');
  const sourceHash=options.sourceHash??byteHash(bytes),environment=await ocrEnvironment(),wanted=new Set(ocrPages),results=new Map<number,NativePageResult>(),missing:number[]=[];
  const cache=options.cacheRoot?join(options.cacheRoot,'ocr'):undefined;
  const keyFor=(page:number)=>hash([sourceHash,page,environment,wanted.has(page),'pdfkit-300dpi-4096-tiled-v4']);
  for(const page of pages){const path=cache?join(cache,keyFor(page)+'.json'):undefined;try{if(path){const saved=JSON.parse(await readFile(path,'utf8'));if(saved.key===keyFor(page)&&saved.sha256===hash(saved.value)){const value=Result.parse(saved.value);if(value.ocr_performed===wanted.has(page)){results.set(page,value);continue;}}}}catch{/* missing or corrupt cache is recomputed */}missing.push(page);}
  if(!missing.length)return results;
  const folder=options.sourceFile?undefined:await mkdtemp(join(tmpdir(),'docver-ocr-'));
  try{
    const source=options.sourceFile??join(folder!,'source.pdf');if(folder)await writeFile(source,bytes,{mode:0o600});
    const save=async(page:number,value:NativePageResult)=>{if(!cache)return;await mkdir(cache,{recursive:true});const key=keyFor(page),path=join(cache,key+'.json'),staging=join(cache,key+'-'+randomUUID()+'.tmp');await writeFile(staging,JSON.stringify({key,sha256:hash(value),value}),{flag:'wx'});await rename(staging,path);};
    // OCR is an image observation: identical native pixels reuse recognition across versions.
    if(cache&&missing.some(n=>wanted.has(n))){
      const rendered=await captureNativePages(bytes,missing.filter(n=>wanted.has(n)),[],{...options,sourceFile:source,sourceHash,onPage:undefined});
      for(const [page,raster] of rendered){const key=hash([environment,raster.render_sha256]),path=join(cache,'raster',key+'.json');try{const saved=JSON.parse(await readFile(path,'utf8'));if(saved.key!==key||saved.sha256!==hash(saved.value))continue;const known=Result.parse(saved.value);if(!known.ocr_performed||known.render_sha256!==raster.render_sha256)continue;
        const value={...known,viewport_width:raster.viewport_width,viewport_height:raster.viewport_height,rotation:raster.rotation};results.set(page,value);await save(page,value);
      }catch{/* no verified recognition for these pixels */}}
    }
    const pending=missing.filter(n=>!results.has(n));
    for(let start=0;start<pending.length;start+=16){
      options.signal?.throwIfAborted();const chunk=pending.slice(start,start+16),response=z.object({pages:z.array(z.object({page:z.number().int().positive(),result:Result.optional(),error:z.string().optional()}).refine(row=>Boolean(row.result)!==Boolean(row.error))).max(16)}).parse(JSON.parse(await runTool(executable,[],{input:JSON.stringify({path:source,pages:chunk,ocr_pages:chunk.filter(n=>wanted.has(n))}),signal:options.signal,timeout:120_000,maxBytes:32*1024*1024})));
      if(response.pages.length!==chunk.length||new Set(response.pages.map(p=>p.page)).size!==chunk.length||response.pages.some(p=>!chunk.includes(p.page)))throw new DocverError('OCR_PROTOCOL','Native observation page set mismatch');
      for(const row of response.pages){if(!row.result)continue;if(row.result.ocr_performed!==wanted.has(row.page))throw new DocverError('OCR_PROTOCOL','Native observation mode mismatch');results.set(row.page,row.result);await save(row.page,row.result);
        if(cache&&row.result.ocr_performed){const key=hash([environment,row.result.render_sha256]),folder=join(cache,'raster');await mkdir(folder,{recursive:true});const staging=join(folder,key+'-'+randomUUID()+'.tmp');await writeFile(staging,JSON.stringify({key,sha256:hash(row.result),value:row.result}),{flag:'wx'});await rename(staging,join(folder,key+'.json'));}
      }
      options.onPage?.(Math.min(start+16,pending.length),pending.length);
    }
    return results;
  }finally{if(folder)await rm(folder,{recursive:true,force:true});}
}
const compact=(s:string)=>normalize(s).replace(/\s/gu,'').toLowerCase();
export async function supplementPdfOcr(page:PageData,bytes:Uint8Array,options:OcrOptions={}):Promise<void>{
  const environment=await ocrEnvironment();
  try{
    const result=options.nativeResult??await recognizePdf(bytes,page.page,options),original=page.elements.slice();
    const lines=result.lines.filter(l=>l.text.trim());
    const scanned=!original.some(e=>e.text.trim()&&e.visibility!=='hidden_render_mode'),rasterComparison=scanned||!!page.unresolved_text;
    const additions:ElementData[]=[],geometryOK=Math.abs((page.width/page.height)/(result.width/result.height)-1)<0.003;
    for(const [i,line] of lines.entries()){
      // An OCR match never clears a raw visibility/strike warning. Add only separately imaged content.
      const intersects=(e:ElementData)=>Math.max(0,Math.min(e.bbox[0]+e.bbox[2],line.bbox[0]+line.bbox[2])-Math.max(e.bbox[0],line.bbox[0]))*Math.max(0,Math.min(e.bbox[1]+e.bbox[3],line.bbox[1]+line.bbox[3])-Math.max(e.bbox[1],line.bbox[1]));
      if(!rasterComparison&&original.some(e=>intersects(e)>0||compact(e.text).includes(compact(line.text))))continue;
      const ambiguous=line.alternatives.some(c=>compact(c.text)!==compact(line.text)&&c.confidence>=line.confidence-0.15);
      const appearanceBlocked=original.some(e=>intersects(e)>0&&['struck_through','struck_inferred','partially_struck_through','occluded','partially_occluded'].includes(e.visibility??''));
      const confident=geometryOK&&!appearanceBlocked&&line.confidence>=0.5&&!ambiguous&&(!/[0-9]/.test(line.text)||line.numeric_consensus);
      additions.push({observation_id:id('obs',[page.asset_id,page.page,'ocr',environment,i]),kind:'text',text:line.text,normalized_text:normalize(line.text),bbox:box(...line.bbox),reading_order:original.length+additions.length,availability:'available',method:'vision_ocr',source_ref:`page:${page.page}/raster/ocr:${i}`,provenance:'inferred',visibility:line.strike_candidate?'struck_inferred':confident?'visible':'uncertain',
        ...(line.strike_candidate?{visibility_evidence:[{method:'raster_horizontal_strike_candidate',bbox:line.strike_bbox,assessment:'inferred' as const,coverage:Math.min(1,line.strike_bbox[2]/Math.max(0.000001,line.bbox[2]))}]}:{}),
        ocr:{confidence:line.confidence,confidence_scope:'line',numeric_consensus:line.numeric_consensus,ambiguous,alternatives:line.alternatives.map(c=>({text:c.text,confidence:c.confidence,truncated:false}))}});
    }
    page.elements.push(...additions);
    page.ocr={status:lines.length?'available':'no_text',mode:scanned?'scan':rasterComparison?'verification':additions.length?'supplement':'verification',engine:result.version,environment,render_sha256:result.render_sha256,width:result.width,height:result.height,structure_status:result.structure_status,table_count:result.tables?.length??0};
    if(additions.length){
      page.capabilities.text='available';
      const good=additions.filter(e=>e.visibility==='visible').map(e=>e.text).join('\n'),uncertain=additions.filter(e=>e.visibility!=='visible').map(e=>e.text).join('\n');
      page.ocr_text=good;page.ocr_unresolved_text=uncertain;
      if(rasterComparison)page.comparison_basis='raster_ocr';
      else{page.visible_text=[page.visible_text,good].filter(Boolean).join('\n');page.unresolved_text=[page.unresolved_text,uncertain].filter(Boolean).join('\n');}
      page.coverage_gaps.push({feature:'ocr',reason:'ocr_inferred_text_requires_source_review'});
      if(uncertain)page.coverage_gaps.push({feature:'ocr',reason:'low_confidence_or_ambiguous_ocr_text_comparison_withheld'});
    }
    if(original.length&&lines.length)page.coverage_gaps.push({feature:'ocr_verification',reason:'raster_ocr_does_not_override_raw_visibility_or_prove_absence'});
    if(scanned&&original.some(e=>e.visibility==='hidden_render_mode'))page.coverage_gaps.push({feature:'ocr',reason:'prior_invisible_ocr_layer_preserved_separately'});
    if(!geometryOK)page.coverage_gaps.push({feature:'ocr',reason:'native_raster_viewport_geometry_disagrees'});
    if(geometryOK){for(const [ti,table] of (result.tables??[]).entries()){
      const seen=new Set<string>();for(const cell of table.cells){const key=cell.row+':'+cell.column;if(seen.has(key))continue;seen.add(key);
        page.elements.push({observation_id:id('obs',[page.asset_id,page.page,'vision-cell',environment,ti,key]),kind:'table_cell',text:cell.text,normalized_text:normalize(cell.text),bbox:cell.bbox,reading_order:page.elements.length,availability:'available',method:'vision_document_cell',source_ref:`page:${page.page}/raster/table:${ti}/cell:${key}`,provenance:'inferred',visibility:'unverified',table:{table_id:id('table',[page.asset_id,page.page,environment,ti]),row:cell.row,column:cell.column,row_span:cell.row_span,column_span:cell.column_span,origin:'vision_table_inferred',assessment:'inferred'}});
      }
    }}
    if(result.tables?.length)page.coverage_gaps.push({feature:'table_semantics',reason:'vision_table_cells_inferred_not_original_pptx_cells'});
    if(result.structure_status&&result.structure_status!=='available')page.coverage_gaps.push({feature:'table_ocr',reason:'document_structure_'+result.structure_status});
    page.coverage_gaps=page.coverage_gaps.filter(g=>g.reason!=='no_text_layer_ocr_not_run');
    if(!lines.length)page.coverage_gaps.push({feature:'ocr',reason:'ocr_no_text_detected_not_proof_of_blank_page'});
  }catch(e){
    if(options.signal?.aborted||(e instanceof DocverError&&e.code==='CANCELLED'))throw e;
    page.ocr={status:e instanceof DocverError&&e.code==='OCR_UNAVAILABLE'?'unavailable':'failed',engine:'native-vision-helper',environment,reason:e instanceof DocverError?e.code:'OCR_FAILED'};
    page.coverage_gaps.push({feature:'ocr',reason:page.ocr.reason!});
  }
}
