import {annotationBlocksRegion} from './pdf-annotation-regions.js';
import { z } from 'zod';
import { existsSync } from 'node:fs';
import { mkdtemp,mkdir,readFile,writeFile,rm,rename } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { Bbox,GridStatus,OcrReconsideration,box,byteHash,hash,id,normalize,type PageData,type ElementData,type Box,DocverError } from '../schema/index.js';
import { runTool,visionExecutable,visionInfo } from '../runtime/tools.js';
import {nativeHelperLaunch} from '../runtime/native-isolation.js';
import {admitReconsideration} from './ocr-reconsideration.js';
import {selectHybridComparison,sourceAppearanceBlocks} from './comparison-selection.js';

const Candidate=z.object({text:z.string(),confidence:z.number().min(0).max(1)});
const NativeTable=z.object({cells:z.array(z.object({row:z.number().int().nonnegative(),column:z.number().int().nonnegative(),row_span:z.number().int().positive(),column_span:z.number().int().positive(),text:z.string(),text_confident:z.boolean().optional(),bbox:Bbox})).max(20000)});
const DocumentStructure=z.object({structure_status:z.string().max(160).optional(),structure_engine:z.string().max(160).optional(),tables:z.array(NativeTable).max(200).optional()});
const GridStructure=z.object({grid_tables:z.array(NativeTable).max(50).optional(),grid_status:GridStatus.optional(),grid_reasons:z.array(z.string().max(160)).max(20).optional()});
const StructureMetadataError=z.enum(['document','grid']);
const NativeLine=Candidate.extend({bbox:Bbox,strike_candidate:z.boolean(),strike_status:z.string().optional(),strike_bbox:Bbox,numeric_consensus:z.boolean(),numeric_status:z.string().optional(),numeric_readings:z.array(z.string()),numeric_observations:z.array(z.object({text:z.string(),bbox:Bbox,sources:z.array(z.string())})).optional(),tokens:z.array(z.object({text:z.string(),bbox:Bbox})),alternatives:z.array(Candidate).max(3),reconsideration:z.unknown().optional(),reconsideration_error:z.literal('invalid_metadata').optional()}).transform(line=>{const checked=line.reconsideration===undefined?undefined:OcrReconsideration.safeParse(line.reconsideration);return {...line,reconsideration:checked?.success?checked.data:undefined,reconsideration_error:checked&&!checked.success?'invalid_metadata' as const:line.reconsideration_error};});
const Result=z.object({version:z.string(),revision:z.number(),languages:z.array(z.string()),language_correction:z.literal(false),ocr_performed:z.boolean(),renderer:z.string(),verification:z.string(),viewport_width:z.number().positive(),viewport_height:z.number().positive(),rotation:z.number(),width:z.number().int().positive().max(4096),height:z.number().int().positive().max(4096),render_sha256:z.string().regex(/^[a-f0-9]{64}$/),structure_status:z.unknown().optional(),structure_engine:z.unknown().optional(),tables:z.unknown().optional(),grid_tables:z.unknown().optional(),grid_status:z.unknown().optional(),grid_reasons:z.unknown().optional(),structure_metadata_errors:z.array(StructureMetadataError).max(2).optional().catch([]),bitmap_format:z.number().int().nonnegative().optional(),bitmap_bits_per_sample:z.number().int().positive().optional(),bitmap_bits_per_pixel:z.number().int().positive().optional(),
  cache_write_failed:z.literal(true).optional(),lines:z.array(NativeLine).max(20000)}).transform(result=>{
    // Supplementary structure has independent failure domains. A malformed
    // document table cannot erase primary OCR or a valid raster-grid annex.
    const document=DocumentStructure.safeParse(result),grid=GridStructure.safeParse(result);
    const errors=new Set(result.structure_metadata_errors??[]);
    if(!document.success)errors.add('document');if(!grid.success)errors.add('grid');
    const {structure_status,structure_engine,tables,grid_tables,grid_status,grid_reasons,structure_metadata_errors,...primary}=result;
    return {...primary,...(document.success&&!errors.has('document')?document.data:{structure_status:'invalid_metadata'}),...(grid.success&&!errors.has('grid')?grid.data:{}),
      ...(errors.size?{structure_metadata_errors:[...errors]}:{})};
  });
export type NativePageResult=z.infer<typeof Result>;
export class NativePageObservations extends Map<number,NativePageResult>{readonly failures=new Map<number,string>();}
export type OcrOptions={cacheRoot?:string;signal?:AbortSignal;sourceFile?:string;sourceHash?:string;reuseRasterOcr?:boolean;nativeResult?:NativePageResult;onPage?:(current:number,total:number)=>void};
export async function ocrEnvironment():Promise<string>{const info=await visionInfo();return info?hash(info):'unavailable';}
export async function recognizePdf(bytes:Uint8Array,page:number,options:OcrOptions={}):Promise<z.infer<typeof Result>>{
  const observations=await captureNativePages(bytes,[page],[page],options),result=observations.get(page);if(!result)throw new DocverError(observations.failures.get(page)??'OCR_FAILED','Native page observation failed');return result;
}
export async function captureNativePages(bytes:Uint8Array,pages:number[],ocrPages:number[],options:OcrOptions={}):Promise<NativePageObservations>{
  options.signal?.throwIfAborted();
  const executable=visionExecutable();if(!executable)throw new DocverError('OCR_UNAVAILABLE','Native OCR helper is unavailable');
  const environment=await ocrEnvironment();if(environment==='unavailable')throw new DocverError('OCR_UNAVAILABLE','Native OCR environment could not be verified');
  const sourceHash=options.sourceHash??byteHash(bytes),wanted=new Set(ocrPages),results=new NativePageObservations(),missing:number[]=[];
  const cache=options.cacheRoot?join(options.cacheRoot,'ocr'):undefined;
  const keyFor=(page:number)=>hash([sourceHash,page,environment,wanted.has(page),'pdfkit-300dpi-4096-tiled-v4']);
  for(const page of pages){const path=cache?join(cache,keyFor(page)+'.json'):undefined;try{if(path){const saved=JSON.parse(await readFile(path,'utf8'));if(saved.key===keyFor(page)&&saved.sha256===hash(saved.value)){const value=Result.parse(saved.value);if(value.ocr_performed===wanted.has(page)){results.set(page,value);continue;}}}}catch{/* missing or corrupt cache is recomputed */}missing.push(page);}
  if(!missing.length){options.signal?.throwIfAborted();return results;}
  const folder=await mkdtemp(join(tmpdir(),'docver-ocr-'));
  try{
    const source=options.sourceFile??join(folder,'source.pdf');if(!options.sourceFile)await writeFile(source,bytes,{mode:0o600});
    const launch=await nativeHelperLaunch(executable,folder,source);
    const writeCache=async(folder:string,key:string,value:NativePageResult)=>{
      const cached={...value};delete cached.cache_write_failed;
      await mkdir(folder,{recursive:true,mode:0o700});const staging=join(folder,key+'-'+randomUUID()+'.tmp');
      try{await writeFile(staging,JSON.stringify({key,sha256:hash(cached),value:cached}),{flag:'wx',mode:0o600,signal:options.signal});options.signal?.throwIfAborted();await rename(staging,join(folder,key+'.json'));}
      finally{await rm(staging,{force:true});}
    };
    const persist=async(value:NativePageResult,write:()=>Promise<void>)=>{
      try{await write();}catch(error){if(options.signal?.aborted||(error instanceof DocverError&&error.code==='CANCELLED'))throw error;value.cache_write_failed=true;}
    };
    const save=async(page:number,value:NativePageResult)=>{if(cache)await writeCache(cache,keyFor(page),value);};
    const sameRaster=(a:NativePageResult,b:NativePageResult)=>a.render_sha256===b.render_sha256&&a.width===b.width&&a.height===b.height;
    const rasterKey=(value:NativePageResult)=>hash([environment,value.render_sha256,value.width,value.height]);
    const forPage=(known:NativePageResult,raster:NativePageResult)=>{
      const value=structuredClone(known);delete value.cache_write_failed;
      value.viewport_width=raster.viewport_width;value.viewport_height=raster.viewport_height;value.rotation=raster.rotation;
      if(raster.cache_write_failed)value.cache_write_failed=true;
      return value;
    };
    let rendered=new NativePageObservations();
    // OCR is an image observation: identical native pixels reuse recognition across versions.
    if(cache&&options.reuseRasterOcr!==false&&existsSync(join(cache,'raster'))&&missing.some(n=>wanted.has(n))){
      rendered=await captureNativePages(bytes,missing.filter(n=>wanted.has(n)),[],{...options,sourceFile:source,sourceHash,onPage:undefined});
      for(const [page,raster] of rendered){options.signal?.throwIfAborted();const key=rasterKey(raster),path=join(cache,'raster',key+'.json');try{const saved=JSON.parse(await readFile(path,'utf8'));if(saved.key!==key||saved.sha256!==hash(saved.value))continue;const known=Result.parse(saved.value);if(!known.ocr_performed||!sameRaster(known,raster))continue;
        const value=forPage(known,raster);results.set(page,value);await persist(value,()=>save(page,value));
      }catch(error){if(options.signal?.aborted||(error instanceof DocverError&&error.code==='CANCELLED'))throw error;/* no verified recognition for these pixels */}}
    }
    const pending=missing.filter(n=>!results.has(n));
    // Reuse the render pass already required for raster-cache lookup. New images
    // repeated within this call need one observation, not one OCR per page. No
    // extra rendering is introduced for a cold cache or when reuse is disabled.
    const groups=new Map<string,{representative:number;duplicates:number[]}>(),duplicates=new Set<number>();
    for(const page of pending){const raster=rendered.get(page);if(!wanted.has(page)||!raster)continue;
      const key=hash([raster.render_sha256,raster.width,raster.height]),group=groups.get(key);
      if(group){group.duplicates.push(page);duplicates.add(page);}else groups.set(key,{representative:page,duplicates:[]});
    }
    let completed=0;
    const progress=()=>options.onPage?.(completed,pending.length);
    // Cold primary OCR plus bounded ROI can exceed30s (measured24.85s
    // process/structure on the ruled-table control). Keep cancellation and a
    // finite60s/page process budget; ROI has its own smaller native budget.
    const observeBatches=async(queue:number[])=>{for(let start=0;start<queue.length;start+=16){
      options.signal?.throwIfAborted();const chunk=queue.slice(start,start+16);try{const response=z.object({pages:z.array(z.object({page:z.number().int().positive(),result:z.unknown().optional(),error:z.string().optional()}).refine(row=>Boolean(row.result)!==Boolean(row.error))).max(16)}).parse(JSON.parse(await runTool(launch.executable,launch.args,{cwd:folder,input:JSON.stringify({path:source,pages:chunk,ocr_pages:chunk.filter(n=>wanted.has(n))}),signal:options.signal,timeout:60_000*chunk.length,maxBytes:32*1024*1024,inheritEnv:false,env:launch.env})));
      if(response.pages.length!==chunk.length||new Set(response.pages.map(p=>p.page)).size!==chunk.length||response.pages.some(p=>!chunk.includes(p.page)))throw new DocverError('OCR_PROTOCOL','Native observation page set mismatch');
      for(const row of response.pages){if(!row.result){results.failures.set(row.page,'NATIVE_PAGE_HELPER_ERROR');continue;}const parsed=Result.safeParse(row.result);if(!parsed.success){results.failures.set(row.page,'NATIVE_RESULT_SCHEMA_INVALID');continue;}const result=parsed.data;delete result.cache_write_failed;if(result.ocr_performed!==wanted.has(row.page)){results.failures.set(row.page,'NATIVE_OCR_MODE_MISMATCH');continue;}if(rendered.get(row.page)?.cache_write_failed)result.cache_write_failed=true;results.set(row.page,result);
        await persist(result,async()=>{await save(row.page,result);if(cache&&result.ocr_performed)await writeCache(join(cache,'raster'),rasterKey(result),result);});
      }
      }catch(e){if(options.signal?.aborted||(e instanceof DocverError&&e.code==='CANCELLED'))throw e;
        const reason=e instanceof DocverError&&['TOOL_TIMEOUT','TOOL_OUTPUT_LIMIT','TOOL_FAILED','OCR_PROTOCOL'].includes(e.code)?e.code:e instanceof SyntaxError||e instanceof z.ZodError?'OCR_PROTOCOL':'NATIVE_BATCH_FAILED';
        for(const page of chunk)if(!results.has(page)&&!results.failures.has(page))results.failures.set(page,reason);
      }
      completed+=chunk.length;progress();
    }};
    await observeBatches(pending.filter(page=>!duplicates.has(page)));
    const fallback:number[]=[];
    for(const {representative,duplicates:peers} of groups.values()){
      options.signal?.throwIfAborted();const known=results.get(representative),raster=rendered.get(representative)!;
      // An individual helper failure or changed render cannot certify its peers.
      if(!known?.ocr_performed||!sameRaster(known,raster)){fallback.push(...peers);continue;}
      for(const page of peers){options.signal?.throwIfAborted();const value=forPage(known,rendered.get(page)!);results.set(page,value);await persist(value,()=>save(page,value));completed++;}
      if(peers.length)progress();
    }
    await observeBatches(fallback);
    options.signal?.throwIfAborted();return results;
  }finally{if(folder)await rm(folder,{recursive:true,force:true});}
}

// Prefer the native document observer when it covers the same table. The grid
// observer is supplementary geometry, not another copy of those cells.
function tableOverlap(a:z.infer<typeof NativeTable>,b:z.infer<typeof NativeTable>):boolean{
  const bounds=(t:z.infer<typeof NativeTable>)=>{if(!t.cells.length)return undefined;const x=Math.min(...t.cells.map(c=>c.bbox[0])),y=Math.min(...t.cells.map(c=>c.bbox[1]));return [x,y,Math.max(...t.cells.map(c=>c.bbox[0]+c.bbox[2]))-x,Math.max(...t.cells.map(c=>c.bbox[1]+c.bbox[3]))-y];};
  const x=bounds(a),y=bounds(b);if(!x||!y)return false;const area=Math.max(0,Math.min(x[0]+x[2],y[0]+y[2])-Math.max(x[0],y[0]))*Math.max(0,Math.min(x[1]+x[3],y[1]+y[3])-Math.max(x[1],y[1]));return area>0.5*Math.min(x[2]*x[3],y[2]*y[3]);
}
const compact=(s:string)=>normalize(s).replace(/\s/gu,'').toLowerCase();
export async function supplementPdfOcr(page:PageData,bytes:Uint8Array,options:OcrOptions={}):Promise<void>{
  const environment=await ocrEnvironment();
  try{
    const result=options.nativeResult?Result.parse(options.nativeResult):await recognizePdf(bytes,page.page,options),original=page.elements.slice();
    const lines=result.lines.filter(l=>l.text.trim());
    const scanned=!original.some(e=>e.text.trim()&&e.visibility!=='hidden_render_mode'),rasterComparison=scanned||!!page.unresolved_text;
    const additions:ElementData[]=[],geometryOK=Math.abs((page.width/page.height)/(result.width/result.height)-1)<0.003;
    for(const [i,line] of lines.entries()){
      // Preserve every raster observation. The selector alone decides whether
      // matching, fully covered source makes it redundant; text equality or a
      // partial overlap cannot discard an independently imaged line.
      const ambiguous=line.alternatives.some(c=>compact(c.text)!==compact(line.text)&&c.confidence>=line.confidence-0.15);
      const appearanceBlocked=original.some(e=>sourceAppearanceBlocks(e,line.bbox))||annotationBlocksRegion(original,line.bbox);
      const strikeEvaluated=!line.strike_status||['detected','not_detected'].includes(line.strike_status);
      const confident=geometryOK&&strikeEvaluated&&!appearanceBlocked&&line.confidence>=0.5&&!ambiguous&&line.numeric_consensus;
      additions.push({observation_id:id('obs',[page.asset_id,page.page,'ocr',environment,i]),kind:'text',text:line.text,normalized_text:normalize(line.text),bbox:box(...line.bbox),reading_order:original.length+additions.length,availability:'available',method:'vision_ocr',source_ref:`page:${page.page}/raster/ocr:${i}`,provenance:'inferred',visibility:line.strike_candidate?'struck_inferred':confident?'visible':'uncertain',
        ...(line.strike_candidate?{visibility_evidence:[{method:'raster_horizontal_strike_candidate',bbox:line.strike_bbox,assessment:'inferred' as const,coverage:Math.min(1,line.strike_bbox[2]/Math.max(0.000001,line.bbox[2]))}]}:{}),
        ocr:{...(line.reconsideration?{reconsideration_observation:line.reconsideration}:{}),confidence:line.confidence,confidence_scope:'line',strike_status:line.strike_status,numeric_consensus:line.numeric_consensus,ambiguous,alternatives:line.alternatives.map(c=>({text:c.text,confidence:c.confidence,truncated:false}))}});
    }
    const primaryAdditions=additions.slice();
    const appearanceInputs=[...original,...primaryAdditions];
    for(const [i,primary]of primaryAdditions.entries()){
      const observation=primary.ocr?.reconsideration_observation;if(!observation||!geometryOK||lines[i].strike_status!=='not_detected'||lines[i].strike_candidate)continue;
      const accepted=admitReconsideration(primary,observation,b=>appearanceInputs.some(e=>sourceAppearanceBlocks(e,b))||annotationBlocksRegion(appearanceInputs,b));
      if(!accepted)continue;
      additions.push({observation_id:id('obs',[page.asset_id,page.page,'roi',environment,i]),kind:'text',text:accepted.text,normalized_text:normalize(accepted.text),bbox:accepted.bbox,reading_order:original.length+additions.length,availability:'available',method:'vision_ocr',source_ref:`page:${page.page}/raster/roi:${i}`,provenance:'inferred',visibility:'visible',
        ocr:{confidence:accepted.confidence,confidence_scope:'line',numeric_consensus:true,ambiguous:false,alternatives:accepted.alternatives,reconsideration:{method:'vision_multicontext_roi',primary_source_ref:primary.source_ref,primary_text:primary.text,primary_confidence:primary.ocr!.confidence,primary_bbox:primary.bbox,observation}}});
    }
    page.elements.push(...additions);
    const appearanceBlockedAt=(b:Box)=>original.some(e=>sourceAppearanceBlocks(e,b))||annotationBlocksRegion(original,b);
    const nativeTables=result.tables??[],gridTables=(result.grid_tables??[]).filter(grid=>!nativeTables.some(native=>tableOverlap(grid,native)));
    const tables=[...nativeTables.map(table=>({table,grid:false})),...gridTables.map(table=>({table,grid:true}))];
    page.ocr={status:lines.length?'available':'no_text',mode:scanned?'scan':rasterComparison?'verification':additions.length?'supplement':'verification',engine:result.version,environment,render_sha256:result.render_sha256,width:result.width,height:result.height,structure_status:result.structure_status,grid_status:result.grid_status,grid_reasons:result.grid_reasons,bitmap_format:result.bitmap_format,bitmap_bits_per_sample:result.bitmap_bits_per_sample,bitmap_bits_per_pixel:result.bitmap_bits_per_pixel,table_count:tables.length};
    if(additions.length){
      page.capabilities.text='available';
      const good=primaryAdditions.filter(e=>e.visibility==='visible').map(e=>e.text).join('\n'),uncertain=primaryAdditions.filter(e=>e.visibility!=='visible').map(e=>e.text).join('\n');
      page.ocr_text=good;page.ocr_unresolved_text=uncertain;
      if(rasterComparison)page.comparison_basis='raster_ocr';
      page.coverage_gaps.push({feature:'ocr',reason:'ocr_inferred_text_requires_source_review'});
      if(uncertain)page.coverage_gaps.push({feature:'ocr',reason:'low_confidence_or_ambiguous_ocr_observation_retained'});
    }
    if(original.length&&lines.length)page.coverage_gaps.push({feature:'ocr_verification',reason:'raster_ocr_does_not_override_raw_visibility_or_prove_absence'});
    if(scanned&&original.some(e=>e.visibility==='hidden_render_mode'))page.coverage_gaps.push({feature:'ocr',reason:'prior_invisible_ocr_layer_preserved_separately'});
    if(!geometryOK)page.coverage_gaps.push({feature:'ocr',reason:'native_raster_viewport_geometry_disagrees'});
    if(geometryOK){for(const [ti,{table,grid}] of tables.entries()){
      const seen=new Set<string>();for(const cell of table.cells){const key=cell.row+':'+cell.column;if(seen.has(key))continue;seen.add(key);
        page.elements.push({observation_id:id('obs',[page.asset_id,page.page,grid?'grid-cell':'vision-cell',environment,ti,key]),kind:'table_cell',text:cell.text,normalized_text:normalize(cell.text),bbox:cell.bbox,reading_order:page.elements.length,availability:grid&&!cell.text.trim()?'unavailable':'available',method:grid?'raster_ruled_grid_cell':'vision_document_cell',source_ref:`page:${page.page}/raster/table:${ti}/cell:${key}`,provenance:'inferred',visibility:grid&&(cell.text_confident!==true||appearanceBlockedAt(cell.bbox))?'uncertain':'unverified',table:{table_id:id('table',[page.asset_id,page.page,environment,ti]),row:cell.row,column:cell.column,row_span:cell.row_span,column_span:cell.column_span,origin:grid?'pdf_grid_inferred':'vision_table_inferred',assessment:'inferred'}});
      }
    }}
    if(result.grid_status&&!['available','not_detected'].includes(result.grid_status))page.coverage_gaps.push({feature:'table_ocr',reason:'raster_grid_'+result.grid_status});
    for(const reason of result.grid_reasons??[])page.coverage_gaps.push({feature:'table_ocr',reason:'raster_grid_'+reason});
    if(gridTables.some(t=>t.cells.some(c=>c.text_confident!==true||appearanceBlockedAt(c.bbox))))page.coverage_gaps.push({feature:'table_ocr',reason:'ruled_grid_cell_text_uncertain_or_not_observed'});
    if(gridTables.length)page.coverage_gaps.push({feature:'table_semantics',reason:'raster_ruled_grid_cells_inferred_complete_rectangles_only'});
    if(result.tables?.length)page.coverage_gaps.push({feature:'table_semantics',reason:'vision_table_cells_inferred_not_original_pptx_cells'});
    if(result.structure_status&&result.structure_status!=='available')page.coverage_gaps.push({feature:'table_ocr',reason:'document_structure_'+result.structure_status});
    page.coverage_gaps=page.coverage_gaps.filter(g=>g.reason!=='no_text_layer_ocr_not_run');
    for(const status of new Set(lines.map(l=>l.strike_status).filter(s=>s&&!['detected','not_detected'].includes(s))))page.coverage_gaps.push({feature:'strike_ocr',reason:'raster_strike_'+status});
    if(lines.some(l=>l.numeric_status==='unsupported_notation'))page.coverage_gaps.push({feature:'ocr_numeric',reason:'unsupported_numeric_notation_requires_source_review'});
    if(lines.some(l=>l.reconsideration_error))page.coverage_gaps.push({feature:'ocr_reconsideration',reason:'invalid_optional_roi_metadata_ignored_primary_retained'});
    for(const annex of result.structure_metadata_errors??[])page.coverage_gaps.push({feature:'table_ocr',reason:'invalid_optional_'+annex+'_metadata_ignored_primary_retained'});
    if(result.cache_write_failed)page.coverage_gaps.push({feature:'native_cache',reason:'optional_cache_write_failed_observations_retained'});
    if(!lines.length)page.coverage_gaps.push({feature:'ocr',reason:'ocr_no_text_detected_not_proof_of_blank_page'});
    if(additions.length){
      selectHybridComparison(page);
      if(!rasterComparison&&additions.every(e=>e.comparison_role==='shadowed'))page.ocr.mode='verification';
    }
  }catch(e){
    if(options.signal?.aborted||(e instanceof DocverError&&e.code==='CANCELLED'))throw e;
    page.ocr={status:e instanceof DocverError&&e.code==='OCR_UNAVAILABLE'?'unavailable':'failed',engine:'native-vision-helper',environment,reason:e instanceof DocverError?e.code:'OCR_FAILED'};
    page.coverage_gaps.push({feature:'ocr',reason:page.ocr.reason!});
  }
}
