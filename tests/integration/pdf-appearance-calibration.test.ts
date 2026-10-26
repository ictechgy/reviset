import {test} from 'node:test';
import assert from 'node:assert/strict';
import {getDocument,OPS} from 'pdfjs-dist/legacy/build/pdf.mjs';
import PDFDocument from 'pdfkit';
import {resolve} from 'node:path';
import {inspectAppearance} from '../../packages/ingest/pdf-appearance.js';
import {PdfAppearanceDocumentBudget} from '../../packages/ingest/pdf-glyphs.js';
import {extractPdf,pdfOptions} from '../../packages/ingest/pdf.js';
import type {ElementData} from '../../packages/schema/index.js';

// 200 ordinary, separated text runs, 15 characters each: 3,000 glyphs/page.
// Four columns and fifty rows fit on a 600 × 800 point page at eight points.
function ordinaryPage(){
  const viewport={width:600,height:800,transform:[1,0,0,-1,0,800],scale:1};
  const font={ascent:.8,descent:-.2},fnArray:number[]=[OPS.setFont],argsArray:any[]=[['font',8]],elements:ElementData[]=[];
  for(let run=0;run<200;run++){
    const text=`Row${String(run).padStart(3,'0')}Value0000`,x=20+140*(run%4),y=780-15*Math.floor(run/4);
    fnArray.push(OPS.setTextMatrix,OPS.showText);argsArray.push([1,0,0,1,x,y],[Array.from(text,unicode=>({unicode,width:500}))]);
    elements.push({observation_id:'ordinary_'+run,kind:'text',text,normalized_text:text,bbox:[x/600,(800-y-6.4)/800,60/600,8/800],reading_order:run,availability:'available',method:'pdf_text',source_ref:'page:1/text:'+run,provenance:'observed'});
  }
  const page={pageNumber:1,commonObjs:{get:()=>font},getOperatorList:async()=>({fnArray,argsArray}),getAnnotations:async()=>[]};
  return {page,viewport,elements};
}

class RecordingBudget extends PdfAppearanceDocumentBudget {
  readonly reserved:Record<string,number>={};
  override page(){const reserve=super.page();return (resource:Parameters<typeof reserve>[0],amount=1)=>{reserve(resource,amount);this.reserved[resource]=(this.reserved[resource]??0)+amount;};}
}

test('ordinary 300 and 1000 page PDF appearance stays inside cumulative budgets',async t=>{
  const budget=new RecordingBudget(),fixture=ordinaryPage();let firstGap=0;
  const started=performance.now();
  for(let page=1;page<=1000;page++){
    const elements=structuredClone(fixture.elements),result=await inspectAppearance(fixture.page,fixture.viewport,elements,{},'sha256:ordinary',budget);
    if(result.gaps.some(g=>g.reason==='appearance_budget_exceeded_visibility_unverified')){firstGap=page;break;}
    assert.ok(elements.every(e=>e.visibility==='visible'&&e.visibility_spans?.length===15),'page '+page);
    if(page===300)t.diagnostic('300 pages / 900,000 glyphs retained with complete appearance admission');
  }
  t.diagnostic(JSON.stringify({pagesChecked:firstGap?firstGap-1:1000,firstBudgetGap:firstGap,elapsedMs:Math.round(performance.now()-started),reserved:budget.reserved}));
  assert.equal(firstGap,0);
});

test('spatial admission includes both embedded-ink overhangs across distinct metric grid cells',async()=>{
  const viewport={width:600,height:800,transform:[1,0,0,-1,0,800],scale:1};
  const font={ascent:.8,descent:-.2,docverEmbeddedFontProgram:true,getPathGenerator:()=>({computeTightBounds:()=>[-1,-.2,1,.8]})};
  const fnArray=[OPS.setFont,OPS.setTextMatrix,OPS.showText,OPS.setTextMatrix,OPS.showText],argsArray=[['font',10],[1,0,0,1,40,100],[[{unicode:'A',fontChar:'A',isInFont:true,width:500}]],[1,0,0,1,59,100],[[{unicode:'B',fontChar:'B',isInFont:true,width:500}]]];
  const page={pageNumber:1,commonObjs:{get:()=>font},getOperatorList:async()=>({fnArray,argsArray}),getAnnotations:async()=>[]};
  const elements:ElementData[]=[40,59].map((x,i)=>({observation_id:'ink_'+i,kind:'text',text:i?'B':'A',normalized_text:i?'B':'A',bbox:[x/600,692/800,5/600,10/800],reading_order:i,availability:'available',method:'pdf_text',source_ref:'page:1/text:'+i,provenance:'observed'}));
  // Metrics occupy cells 4 and 6; actual ink overlaps between x=49 and 50.
  await inspectAppearance(page,viewport,elements,{},'sha256:ink-bucket-boundary');
  assert.equal(elements[0].visibility,'uncertain');assert.ok(elements[0].visibility_evidence?.some(e=>e.method==='later_embedded_text_ink_clearance_unverified'));
  assert.equal(elements[1].visibility,'visible');
});

test('real embedded-font 300 page PDF retains ordinary source text and appearance without OCR',async t=>{
  const document=new PDFDocument({size:[600,800],margin:0,autoFirstPage:false}),chunks:Buffer[]=[];
  document.on('data',b=>chunks.push(b));const done=new Promise<Buffer>(r=>document.on('end',()=>r(Buffer.concat(chunks))));
  document.font(resolve('node_modules/pdfjs-dist/standard_fonts/LiberationSans-Regular.ttf')).fontSize(8);
  for(let page=0;page<300;page++){
    document.addPage();
    for(let run=0;run<200;run++)document.text(`Row${String(run).padStart(3,'0')}Value0000`,20+140*(run%4),20+15*Math.floor(run/4),{lineBreak:false});
  }
  document.end();const bytes=await done,started=performance.now(),pages=await extractPdf(bytes,'sha256:ordinary-real',{ocr:'off'});
  assert.equal(pages.length,300);
  for(const page of pages){
    assert.ok(!page.coverage_gaps.some(g=>g.reason==='appearance_budget_exceeded_visibility_unverified'),'page '+page.page);
    const text=page.elements.filter(e=>e.method==='pdf_text');assert.equal(text.length,200);assert.ok(text.every(e=>e.visibility==='visible'&&e.visibility_spans?.length===15),'page '+page.page);
    assert.equal(page.ocr,undefined);
  }
  t.diagnostic(JSON.stringify({realPdfPages:pages.length,runsPerPage:200,glyphs:900000,pdfBytes:bytes.length,elapsedMs:Math.round(performance.now()-started)}));
  // Independently calibrate 1,000 repeated decoded REAL pages, retaining the
  // actual PDF.js operators, qualified embedded outlines and text geometry.
  // The extraction above exercises distinct source pages and canonical output;
  // this loop measures cumulative admission without a second 3M-span tree.
  const task=getDocument({...pdfOptions,disableFontFace:true,data:new Uint8Array(bytes)}),budget=new RecordingBudget();
  try{
    const source=await(await task.promise).getPage(1),content=await source.getTextContent({disableNormalization:true}),viewport=source.getViewport({scale:1});
    for(let n=1;n<=1000;n++){
      const elements=structuredClone(pages[0].elements),result=await inspectAppearance(source,viewport,elements,content.styles,'sha256:ordinary-real-repeated',budget);
      assert.ok(!result.gaps.some(g=>g.reason==='appearance_budget_exceeded_visibility_unverified'),'actual operators, repeated page '+n);
      assert.ok(elements.every(e=>e.visibility==='visible'&&e.visibility_spans?.length===15),'actual operators, repeated page '+n);
    }
    t.diagnostic(JSON.stringify({repeatedRealOperatorPages:1000,reserved:budget.reserved}));
  }finally{await task.destroy();}
});
