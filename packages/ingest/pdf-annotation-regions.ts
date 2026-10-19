import type {Box,ElementData} from '../schema/index.js';
export const PDF_ANNOTATION_CARRIER='pdf_page_annotation';
export const PDF_ANNOTATION_REGION='pdf_annotation_region_requires_review';
// Pure metadata check: query/diff consumers do not load the PDF parser.
export const annotationBlocksRegion=(elements:ElementData[],region:Box)=>elements.some(e=>e.method===PDF_ANNOTATION_CARRIER&&e.visibility_evidence?.some(v=>v.method===PDF_ANNOTATION_REGION&&Math.min(v.bbox[0]+v.bbox[2],region[0]+region[2])>Math.max(v.bbox[0],region[0])&&Math.min(v.bbox[1]+v.bbox[3],region[1]+region[3])>Math.max(v.bbox[1],region[1])));
