import { inspectAppearance } from './pdf-appearance.js';
import {pdfFontMetrics,PDF_GEOMETRY_UNVERIFIED} from './pdf-text-geometry.js';
import { getDocument, Util } from 'pdfjs-dist/legacy/build/pdf.mjs';
import { createRequire } from 'node:module';
import { dirname, join } from 'node:path';
import { box, Page, DocverError, id, normalize, type PageData, type ElementData } from '../schema/index.js';
import { captureNativePages,ocrEnvironment,supplementPdfOcr,type OcrOptions } from './ocr.js';
const require=createRequire(import.meta.url);
const pdfRoot=dirname(require.resolve('pdfjs-dist/package.json'));
export const pdfOptions = {isEvalSupported:false,useSystemFonts:false,standardFontDataUrl:join(pdfRoot,'standard_fonts/'),
  cMapUrl:join(pdfRoot,'cmaps/'),cMapPacked:true,wasmUrl:join(pdfRoot,'wasm/'),verbosity:0};
export async function extractPdf(bytes:Uint8Array,assetId:string,options:OcrOptions&{ocr?:'off'|'auto'|'all'}={}):Promise<PageData[]> {
  // Load outline paths for precise rectangular-clip checks. Source text and
  // metric boxes remain unchanged; unsupported/missing paths stay unverified.
  const task=getDocument({...pdfOptions,disableFontFace:true,data:new Uint8Array(bytes)});
  try {
    const document=await task.promise;
    if(document.numPages>1000) throw new DocverError('PAGE_LIMIT','PDF exceeds 1000 pages');
    const pages:PageData[]=[],ocrPages:number[]=[];
    for(let n=1;n<=document.numPages;n++) {
      options.signal?.throwIfAborted();
      const page=await document.getPage(n), viewport=page.getViewport({scale:1});
      if(![viewport.width,viewport.height].every(v=>Number.isFinite(v)&&v>0)||viewport.transform.length!==6||!viewport.transform.every(Number.isFinite))throw new DocverError('INVALID_PDF','PDF page geometry is unavailable');
      const content=await page.getTextContent({disableNormalization:true});
      const elements:ElementData[]=[];
      for(const item of content.items) {
        if(!('str' in item)||!item.str.trim()) continue;
        const t=Util.transform(viewport.transform,item.transform);
        const vertical=!!content.styles[item.fontName]?.vertical;
        const height=Math.hypot(t[2],t[3]), width=item.width;
        const angle=Math.atan2(t[1],t[0])+(vertical?Math.PI/2:0);
        const metrics=pdfFontMetrics(content.styles[item.fontName]),ascent=metrics.ascent;
        // Bounding rectangle of a transformed glyph run, including rotated text.
        const ux=Math.cos(angle),uy=Math.sin(angle),vx=-uy,vy=ux;
        const corners=[[0,-height*ascent],[width,-height*ascent],[0,height*(1-ascent)],[width,height*(1-ascent)]]
          .map(([x,y])=>[t[4]+ux*x+vx*y,t[5]+uy*x+vy*y]);
        const xs=corners.map(c=>c[0]),ys=corners.map(c=>c[1]);
        const finite=xs.concat(ys).every(Number.isFinite),bbox=finite?box(Math.min(...xs)/viewport.width,Math.min(...ys)/viewport.height,(Math.max(...xs)-Math.min(...xs))/viewport.width,(Math.max(...ys)-Math.min(...ys))/viewport.height):box(0,0,0,0);
        elements.push({observation_id:id('obs',[assetId,n,elements.length]),kind:'text',text:item.str,normalized_text:normalize(item.str),
          bbox,...(!metrics.known||!finite?{visibility_evidence:[{method:PDF_GEOMETRY_UNVERIFIED,bbox,assessment:'inferred' as const,coverage:0}]}:{}),
          reading_order:elements.length,availability:'available',method:'pdf_text',source_ref:`page:${n}/text:${elements.length}`,provenance:'observed'});
      }
      const appearance=await inspectAppearance(page,viewport,elements,content.styles);
      const hasText=elements.length>0;
      pages.push({page_id:id('pg',[assetId,n-1]),asset_id:assetId,page:n,width:viewport.width,height:viewport.height,
        coordinate_system:'pdf_user_space_bottom_left',source_transform:viewport.transform,hidden:null,
        text:elements.map(e=>e.text).join('\n'),visible_text:elements.filter(e=>['visible','struck_through'].includes(e.visibility??'')).map(e=>e.text).join('\n'),unresolved_text:elements.filter(e=>!['visible','occluded','struck_through'].includes(e.visibility??'unverified')).map(e=>e.text).join('\n'),suppressed_text:elements.filter(e=>['occluded','hidden_render_mode'].includes(e.visibility??'')).map(e=>e.text).join('\n'),elements,notes:null,
        capabilities:{text:hasText?'available':'unavailable',notes:'unavailable',hidden_slides:'unavailable',animation:'unavailable',structure:'unavailable',preview:'available'},
        coverage_gaps:[...appearance.gaps,{feature:'table_semantics',reason:'pdf_grid_is_inferred_not_original_table_structure'},{feature:'notes',reason:'not_present_in_pdf'},{feature:'hidden_slides',reason:'export_visibility_unknown'},
          {feature:'animation',reason:'not_present_in_pdf'},{feature:'structure',reason:'pdf_has_no_original_shape_semantics'},
          ...(!hasText?[{feature:'text',reason:'no_text_layer_ocr_not_run'}]:[])]});
      if(options.ocr&&options.ocr!=='off'&&(options.ocr==='all'||!hasText||!!pages.at(-1)!.unresolved_text||appearance.regions.some(r=>r.kind==='image'))){
        ocrPages.push(n);
      }
      page.cleanup();
    }
    if(options.ocr&&options.ocr!=='off'){
      const environment=await ocrEnvironment();
      try{
        const observations=await captureNativePages(bytes,pages.map(p=>p.page),ocrPages,options);
        for(const p of pages){const result=observations.get(p.page);if(!result){p.coverage_gaps.push({feature:'raster_verification',reason:'native_page_observation_failed'});if(ocrPages.includes(p.page))p.ocr={status:'failed',engine:'native-vision-helper',environment,reason:'NATIVE_PAGE_FAILED'};continue;}
          p.raster={sha256:result.render_sha256,width:result.width,height:result.height,renderer:result.renderer,environment};
          if(ocrPages.includes(p.page))await supplementPdfOcr(p,bytes,{...options,nativeResult:result});
        }
      }catch(e){if(options.signal?.aborted||(e instanceof DocverError&&e.code==='CANCELLED'))throw e;for(const p of pages){p.coverage_gaps.push({feature:'raster_verification',reason:e instanceof DocverError?e.code:'NATIVE_PAGE_FAILED'});if(ocrPages.includes(p.page))p.ocr={status:e instanceof DocverError&&e.code==='OCR_UNAVAILABLE'?'unavailable':'failed',engine:'native-vision-helper',environment,reason:e instanceof DocverError?e.code:'NATIVE_PAGE_FAILED'};}}
    }
    return pages.map(p=>{const result=Page.safeParse(p);if(!result.success)throw new DocverError('INVALID_PAGE_OBSERVATION','PDF page '+p.page+' failed canonical validation at '+result.error.issues[0]?.path.join('.'));return result.data;});
  } catch(e) {
    if(e instanceof DocverError) throw e;
    throw new DocverError((e as Error).name==='PasswordException'?'ENCRYPTED_PDF':'INVALID_PDF','PDF extraction failed: '+(e as Error).name);
  } finally { await task.destroy(); }
}
