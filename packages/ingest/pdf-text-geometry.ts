import type {ElementData} from '../schema/index.js';

// This marker describes geometry only. The extracted string remains observed.
// Estimated bounds are for display, never visibility, coverage or grid proof.
export const PDF_GEOMETRY_UNVERIFIED='pdf_text_geometry_estimated_or_unavailable';
export const hasUnverifiedPdfGeometry=(e:ElementData)=>e.visibility_evidence?.some(v=>v.method===PDF_GEOMETRY_UNVERIFIED)??false;
export function pdfFontMetrics(metrics:any){
  const known=Number.isFinite(metrics?.ascent)&&Number.isFinite(metrics?.descent)&&metrics.ascent>0&&metrics.descent<=0&&metrics.ascent-metrics.descent>=0.5;
  return {known,ascent:known?metrics.ascent:0.8,descent:known?metrics.descent:-0.2};
}

export const isEstimatedPdfSource=(e:ElementData)=>e.method==='pdf_text'&&e.provenance==='observed'&&hasUnverifiedPdfGeometry(e);
