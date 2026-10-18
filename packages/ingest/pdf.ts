import { getDocument, Util } from 'pdfjs-dist/legacy/build/pdf.mjs';
import { createRequire } from 'node:module';
import { dirname, join } from 'node:path';
import { box, DocverError, id, normalize, type PageData, type ElementData } from '../schema/index.js';
const require=createRequire(import.meta.url);
const pdfRoot=dirname(require.resolve('pdfjs-dist/package.json'));
export const pdfOptions = {isEvalSupported:false,useSystemFonts:false,standardFontDataUrl:join(pdfRoot,'standard_fonts/'),
  cMapUrl:join(pdfRoot,'cmaps/'),cMapPacked:true,wasmUrl:join(pdfRoot,'wasm/'),verbosity:0};
export async function extractPdf(bytes:Uint8Array,assetId:string):Promise<PageData[]> {
  const task=getDocument({...pdfOptions,data:new Uint8Array(bytes)});
  try {
    const document=await task.promise;
    if(document.numPages>1000) throw new DocverError('PAGE_LIMIT','PDF exceeds 1000 pages');
    const pages:PageData[]=[];
    for(let n=1;n<=document.numPages;n++) {
      const page=await document.getPage(n), viewport=page.getViewport({scale:1});
      const content=await page.getTextContent({disableNormalization:true});
      const elements:ElementData[]=[];
      for(const item of content.items) {
        if(!('str' in item)||!item.str.trim()) continue;
        const t=Util.transform(viewport.transform,item.transform);
        const vertical=!!content.styles[item.fontName]?.vertical;
        const height=Math.hypot(t[2],t[3]), width=item.width;
        const angle=Math.atan2(t[1],t[0])+(vertical?Math.PI/2:0);
        const ascent=content.styles[item.fontName]?.ascent??0.8;
        // Bounding rectangle of a transformed glyph run, including rotated text.
        const ux=Math.cos(angle),uy=Math.sin(angle),vx=-uy,vy=ux;
        const corners=[[0,-height*ascent],[width,-height*ascent],[0,height*(1-ascent)],[width,height*(1-ascent)]]
          .map(([x,y])=>[t[4]+ux*x+vx*y,t[5]+uy*x+vy*y]);
        const xs=corners.map(c=>c[0]),ys=corners.map(c=>c[1]);
        elements.push({observation_id:id('obs',[assetId,n,elements.length]),kind:'text',text:item.str,normalized_text:normalize(item.str),
          bbox:box(Math.min(...xs)/viewport.width,Math.min(...ys)/viewport.height,(Math.max(...xs)-Math.min(...xs))/viewport.width,(Math.max(...ys)-Math.min(...ys))/viewport.height),
          reading_order:elements.length,availability:'available',method:'pdf_text',source_ref:`page:${n}/text:${elements.length}`,provenance:'observed'});
      }
      const hasText=elements.length>0;
      pages.push({page_id:id('pg',[assetId,n-1]),asset_id:assetId,page:n,width:viewport.width,height:viewport.height,
        coordinate_system:'pdf_user_space_bottom_left',source_transform:viewport.transform,hidden:null,
        text:elements.map(e=>e.text).join('\n'),elements,notes:null,
        capabilities:{text:hasText?'available':'unavailable',notes:'unavailable',hidden_slides:'unavailable',animation:'unavailable',structure:'unavailable',preview:'available'},
        coverage_gaps:[{feature:'notes',reason:'not_present_in_pdf'},{feature:'hidden_slides',reason:'export_visibility_unknown'},
          {feature:'animation',reason:'not_present_in_pdf'},{feature:'structure',reason:'pdf_has_no_original_shape_semantics'},
          ...(!hasText?[{feature:'text',reason:'no_text_layer_ocr_not_run'}]:[])]});
      page.cleanup();
    }
    return pages;
  } catch(e) {
    if(e instanceof DocverError) throw e;
    throw new DocverError((e as Error).name==='PasswordException'?'ENCRYPTED_PDF':'INVALID_PDF','PDF extraction failed: '+(e as Error).name);
  } finally { await task.destroy(); }
}
