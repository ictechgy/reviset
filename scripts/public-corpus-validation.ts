import {Page,type PageData} from '../packages/schema/index.js';

// Validate before JSON.stringify: JSON would silently turn NaN into null.
export function validateCorpusPages(pages:unknown[],context:string):PageData[]{
  return pages.map((page,i)=>{const result=Page.safeParse(page);if(!result.success)throw new Error(context+' page '+(i+1)+' failed canonical Page validation',{cause:result.error});return result.data;});
}
