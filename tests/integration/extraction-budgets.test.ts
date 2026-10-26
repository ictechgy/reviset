import {test} from 'node:test';
import assert from 'node:assert/strict';
import {strToU8,zipSync} from 'fflate';
import {OPS} from 'pdfjs-dist/legacy/build/pdf.mjs';
import {inspectAppearance} from '../../packages/ingest/pdf-appearance.js';
import {PDF_APPEARANCE_LIMITS,PdfAppearanceDocumentBudget,PdfAppearanceBudgetExceeded,paintedGlyphs} from '../../packages/ingest/pdf-glyphs.js';
import {PPTX_EXTRACTION_LIMITS,PptxExtractionBudget,extractPptx} from '../../packages/ingest/pptx.js';
import type {ElementData} from '../../packages/schema/index.js';

const slide='<p:sld xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"><p:cSld><p:spTree/></p:cSld></p:sld>';
function deck(count:number,change?:(entries:{id:string;rid:string;target:string}[],parts:Record<string,Uint8Array>)=>void){
  const entries=Array.from({length:count},(_,i)=>({id:String(256+i),rid:'r'+i,target:`slides/slide${i}.xml`}));
  const parts:Record<string,Uint8Array>={};for(const entry of entries)parts['ppt/'+entry.target]=strToU8(slide);
  change?.(entries,parts);
  parts['ppt/presentation.xml']=strToU8('<p:presentation xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><p:sldIdLst>'+entries.map(e=>`<p:sldId id="${e.id}" r:id="${e.rid}"/>`).join('')+'</p:sldIdLst><p:sldSz cx="960" cy="540"/></p:presentation>');
  // A distinct relationship per entry lets target aliases be tested separately.
  const relationships=new Map(entries.map(e=>[e.rid,e.target]));
  parts['ppt/_rels/presentation.xml.rels']=strToU8('<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'+[...relationships].map(([id,target])=>`<Relationship Id="${id}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="${target}"/>`).join('')+'</Relationships>');
  return zipSync(parts);
}

test('PPTX accepts 1000 unique slides and enforces slide/reference admission before payload parsing',()=>{
  const pages=extractPptx(deck(PPTX_EXTRACTION_LIMITS.slides),'sha256:large-normal-deck');
  assert.equal(pages.length,1000);assert.equal(pages.at(-1)!.page,1000);
  assert.throws(()=>extractPptx(deck(1001,(_,parts)=>{parts['ppt/slides/slide0.xml']=strToU8('not XML');}),'fixture'),{code:'PAGE_LIMIT'});
  for(const field of ['id','rid','target'] as const){
    assert.throws(()=>extractPptx(deck(2,(entries,parts)=>{entries[1][field]=entries[0][field];parts['ppt/slides/slide0.xml']=strToU8('not XML');}),'fixture'),{code:'INVALID_PPTX_SLIDE_REFERENCE'},field);
  }
  assert.throws(()=>extractPptx(deck(1,(entries,parts)=>{entries[0].rid='';parts['ppt/slides/slide0.xml']=strToU8('not XML');}),'fixture'),{code:'INVALID_PPTX_RELATIONSHIP'});
  assert.throws(()=>extractPptx(deck(1,entries=>{entries[0].id='invalid';}),'fixture'),{code:'INVALID_PPTX_SLIDE_REFERENCE'});
});

test('PPTX cumulative XML, text, notes and element counters admit their exact boundary and reject further work',()=>{
  for(const [resource,code] of [['xmlBytes','PPTX_PARSE_LIMIT'],['xmlNodes','PPTX_PARSE_LIMIT'],['parsedText','PPTX_TEXT_LIMIT'],['text','PPTX_TEXT_LIMIT'],['notes','PPTX_NOTES_LIMIT'],['elements','PPTX_ELEMENT_LIMIT']] as const){
    const budget=new PptxExtractionBudget(),limit=PPTX_EXTRACTION_LIMITS[resource];
    budget.reserve(resource,limit-1);budget.reserve(resource,1);
    assert.throws(()=>budget.reserve(resource,1),{code});
    assert.throws(()=>new PptxExtractionBudget().reserve(resource,-1),{code});
  }
});

test('PDF appearance counters enforce both page and cumulative document limits before reserving work',()=>{
  for(const resource of ['work','glyphs','characters','regions','evidence'] as const){
    const document=new PdfAppearanceDocumentBudget(),page=document.page(),limit=PDF_APPEARANCE_LIMITS.page[resource];
    page(resource,limit);assert.throws(()=>page(resource,1),PdfAppearanceBudgetExceeded);
    let remaining=PDF_APPEARANCE_LIMITS.document[resource]-limit;
    while(remaining){const amount=Math.min(remaining,limit);document.page()(resource,amount);remaining-=amount;}
    assert.throws(()=>document.page()(resource,1),PdfAppearanceBudgetExceeded);
  }
  const spend=new PdfAppearanceDocumentBudget().page();spend('glyphs',PDF_APPEARANCE_LIMITS.page.glyphs);
  const {page,viewport,operators}=appearanceFixture(1,0);
  assert.throws(()=>paintedGlyphs(page,viewport,operators,{},spend),PdfAppearanceBudgetExceeded);
});

function appearanceFixture(glyphCount:number,fillCount:number){
  const viewport={width:600,height:400,transform:[1,0,0,-1,0,400],scale:1},font={ascent:.8,descent:-.2};
  const glyph={unicode:'A',width:100},fnArray=[OPS.setFont,OPS.setTextMatrix,OPS.showText],argsArray:any[]=[['font',1],[1,0,0,1,20,100],[Array.from({length:glyphCount},()=>glyph)]];
  const rectangle=[[0,0,0,1,600,0,1,600,400,1,0,400,4]];
  for(let i=0;i<fillCount;i++){fnArray.push(OPS.constructPath);argsArray.push([OPS.fill,rectangle,[0,0,600,400]]);}
  const operators={fnArray,argsArray},page={pageNumber:1,commonObjs:{get:()=>font},getOperatorList:async()=>operators,getAnnotations:async()=>[]};
  const text='A'.repeat(glyphCount),element:ElementData={observation_id:'obs_budget',kind:'text',text,normalized_text:text,bbox:[0,0,1,1],reading_order:0,availability:'available',method:'pdf_text',source_ref:'page:1/text:0',provenance:'observed'};
  return {page,viewport,operators,element};
}

test('PDF overlap admission below the operator cap retains source text and withholds all visibility conclusions',async()=>{
  const {page,viewport,operators,element}=appearanceFixture(1000,5000),text=element.text;
  assert.ok(operators.fnArray.length<250000);
  const result=await inspectAppearance(page,viewport,[element],{},'sha256:budget');
  assert.equal(element.text,text);assert.equal(element.visibility,'unverified');assert.deepEqual(element.visibility_spans,[]);
  assert.ok(result.gaps.some(g=>g.reason==='appearance_budget_exceeded_visibility_unverified'));
  assert.deepEqual(result.regions,[]);
});

test('PDF repeated overlay evidence is deduplicated incrementally while retaining each glyph span',async()=>{
  const {page,viewport,element}=appearanceFixture(1000,1);
  await inspectAppearance(page,viewport,[element],{},'sha256:dedup');
  assert.equal(element.visibility,'occluded');assert.equal(element.visibility_spans!.length,1000);
  assert.equal(element.visibility_evidence!.filter(e=>e.method==='later_opaque_rectangle_per_glyph').length,1);
});
