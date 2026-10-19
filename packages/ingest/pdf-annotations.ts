import {AnnotationType} from 'pdfjs-dist/legacy/build/pdf.mjs';
import {box,id,type Box,type ElementData} from '../schema/index.js';
import {transformedBounds} from './pdf-geometry.js';

import {PDF_ANNOTATION_CARRIER,PDF_ANNOTATION_REGION} from './pdf-annotation-regions.js';
export const PDF_ANNOTATION_LIMIT=2048;
export const PDF_ANNOTATION_POINT_LIMIT=32768;
export const PDF_ANNOTATION_QUAD_LIMIT=8192;

// A page-scoped metadata carrier has no text and never participates in pairing.
// Its region is only a withholding signal, not proof of rendered strike/delete.
export function annotationCarriers(annotations:any[],viewport:any,assetId:string,page:number,startOrder:number){
  const elements:ElementData[]=[],gaps:{feature:string;reason:string}[]=[];
  const add=(index:number|string,subtype:string,bbox:Box,reason:string)=>{
    elements.push({observation_id:id('obs',[assetId,page,'annotation',index,subtype]),kind:'shape',text:'',normalized_text:'',bbox,reading_order:startOrder+elements.length,availability:'available',method:PDF_ANNOTATION_CARRIER,source_ref:`page:${page}/annotation:${index}/${encodeURIComponent(subtype)}`,provenance:'observed',comparison_role:'excluded',comparison_reason:'page_annotation_intent_not_comparison_text',visibility:'unverified',visibility_evidence:[{method:PDF_ANNOTATION_REGION,bbox,assessment:'inferred',coverage:0}]});gaps.push({feature:'pdf_annotations',reason});
  };
  const pointBudget=annotations.some(a=>(a.quadPoints?.length??0)>PDF_ANNOTATION_QUAD_LIMIT)||annotations.reduce((n,a)=>n+(a.quadPoints?.length??0),0)>PDF_ANNOTATION_POINT_LIMIT;
  if(annotations.length>PDF_ANNOTATION_LIMIT||pointBudget){add('budget','BudgetExceeded',box(0,0,1,1),pointBudget?'source_annotation_point_budget_exceeded':'source_annotation_budget_exceeded');return {elements,gaps,budgetExceeded:true};}
  for(const [index,a]of annotations.entries()){
    if(a.annotationFlags&34)continue;
    if((a.annotationType===AnnotationType.LINK||a.annotationType===AnnotationType.POPUP)&&!a.hasAppearance)continue;
    const subtype=typeof a.subtype==='string'?a.subtype:'Unknown',rect=Array.from(a.rect??[]) as number[],quad=Array.from(a.quadPoints??[]) as number[];
    let bbox:Box=box(0,0,1,1),known=false;
    if(rect.length===4&&rect.every(Number.isFinite)&&quad.length<=PDF_ANNOTATION_QUAD_LIMIT&&quad.every(Number.isFinite)){
      let [left,bottom,right,top]=[Math.min(rect[0],rect[2]),Math.min(rect[1],rect[3]),Math.max(rect[0],rect[2]),Math.max(rect[1],rect[3])];
      for(let i=0;i+1<quad.length;i+=2){left=Math.min(left,quad[i]);right=Math.max(right,quad[i]);bottom=Math.min(bottom,quad[i+1]);top=Math.max(top,quad[i+1]);}
      const bounds=transformedBounds([left,bottom,right,top],[1,0,0,1,0,0],viewport);if(bounds.bbox.every(Number.isFinite)){bbox=bounds.bbox;known=true;}
    }
    add(index,subtype,bbox,known?'source_annotation_visibility_requires_review:'+subtype:'source_annotation_geometry_unavailable');
  }
  return {elements,gaps,budgetExceeded:false};
}
