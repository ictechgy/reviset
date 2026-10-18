import { mkdir, writeFile } from 'node:fs/promises';
import { resolve,join } from 'node:path';
import { makePptx,makePdf } from './generate-fixtures.js';
import type { SlideSpec } from '../tests/ground-truth/scenarios.js';
const root=resolve('artifacts/scale-fixture');await mkdir(root,{recursive:true});
const count=Number(process.argv[2]??300);if(!Number.isInteger(count)||count<2||count>1000)throw new Error('Page count must be 2..1000');
const code=(n:number)=>String.fromCharCode(65+Math.floor(n/676)%26,65+Math.floor(n/26)%26,65+n%26);
const slides=(value:string):SlideSpec[]=>Array.from({length:count},(_,i)=>({key:'section-'+code(i),title:`사업 계획 · ${code(i)} 검토 항목`,body:i===149?`예상 매출 ${value}억`:`검토 자료 ${code(i)} · 공급 일정과 계약 가정을 확인합니다.`}));
const revisions=[];
for(const [i,format] of (['pptx','pdf','pptx'] as const).entries()){
  const file=`v${i+1}.${format}`,spec=slides(['100','120','110'][i]);
  await writeFile(join(root,file),format==='pdf'?await makePdf(spec):await makePptx(spec));revisions.push({label:`${count}쪽 v${i+1}`,files:[file]});
}
await writeFile(join(root,'manifest.json'),JSON.stringify({project_id:'prj_scale_'+count,title:`${count}페이지 혼합 형식 검증`,revisions,mapping_decisions:[]},null,2));
console.log(JSON.stringify({root,pages_per_version:count,versions:3,total_pages:count*3}));
