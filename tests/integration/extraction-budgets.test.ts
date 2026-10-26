import {test} from 'node:test';
import assert from 'node:assert/strict';
import {strToU8,zipSync} from 'fflate';
import {OPS} from 'pdfjs-dist/legacy/build/pdf.mjs';
import {inspectAppearance} from '../../packages/ingest/pdf-appearance.js';
import {PDF_APPEARANCE_LIMITS,PdfAppearanceDocumentBudget,PdfAppearanceBudgetExceeded,paintedGlyphs} from '../../packages/ingest/pdf-glyphs.js';
import {PPTX_EXTRACTION_LIMITS,PptxExtractionBudget,extractPptx} from '../../packages/ingest/pptx.js';
import {PDF_ANNOTATION_LIMIT} from '../../packages/ingest/pdf-annotations.js';
import {annotationBlocksRegion,PDF_ANNOTATION_CARRIER} from '../../packages/ingest/pdf-annotation-regions.js';
import {PDF_GEOMETRY_UNVERIFIED} from '../../packages/ingest/pdf-text-geometry.js';
import {supplementPdfOcr,type NativePageResult} from '../../packages/ingest/ocr.js';
import {selectHybridComparison} from '../../packages/ingest/comparison-selection.js';
import {diffRevisions} from '../../packages/diff/index.js';
import {Page,type ElementData,type PageData,type RevisionData} from '../../packages/schema/index.js';

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

function appearanceFixture(glyphCount:number,fillCount:number,annotations:any[]=[]){
  const viewport={width:600,height:400,transform:[1,0,0,-1,0,400],scale:1},font={ascent:.8,descent:-.2};
  const glyph={unicode:'A',width:100},fnArray=[OPS.setFont,OPS.setTextMatrix,OPS.showText],argsArray:any[]=[['font',1],[1,0,0,1,20,100],[Array.from({length:glyphCount},()=>glyph)]];
  const rectangle=[[0,0,0,1,600,0,1,600,400,1,0,400,4]];
  for(let i=0;i<fillCount;i++){fnArray.push(OPS.constructPath);argsArray.push([OPS.fill,rectangle,[0,0,600,400]]);}
  const operators={fnArray,argsArray},page={pageNumber:1,commonObjs:{get:()=>font},getOperatorList:async()=>operators,getAnnotations:async()=>annotations};
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

const square={subtype:'Square',annotationFlags:0,rect:[48,244,293,284]};
function observedPage(elements:ElementData[],gaps:PageData['coverage_gaps']):PageData{
  const text=elements.filter(e=>e.method==='pdf_text').map(e=>e.text).join('\n');
  return {page_id:'page_budget',asset_id:'sha256:budget',page:1,width:600,height:400,coordinate_system:'pdf_user_space_bottom_left',source_transform:[1,0,0,-1,0,400],hidden:null,text,visible_text:'',unresolved_text:text,suppressed_text:'',elements,notes:null,capabilities:{text:'available',notes:'unavailable',hidden_slides:'unavailable',animation:'unavailable',structure:'unavailable',preview:'available'},coverage_gaps:gaps};
}
function regionalChanges(before:PageData,after:PageData){
  const revision=(p:PageData,key:string):RevisionData=>({revision_id:key,revision_occurrence_id:key,label:key,assets:[{asset_id:p.asset_id,format:'pdf',bytes:0}],status:'success',pages:[p],coverage_gaps:p.coverage_gaps,errors:[],bundle_mapping:[]});
  return diffRevisions(revision(before,'before'),revision(after,'after'),[{from_page_id:before.page_id,to_page_id:after.page_id,score:.9,status:'inferred',reasons:['controlled_budget_correspondence']}],[],()=> 'entity');
}

test('PDF annotation safety carrier survives every early admission exit and vetoes OCR selection and stored diff',async()=>{
  for(const reason of ['operators','annotations','evidence'] as const){
    // Accessing per-annotation geometry here would demonstrate an unbounded
    // count-limit path. The oversized source list must never be traversed.
    const annotations=reason==='annotations'?Array.from({length:PDF_ANNOTATION_LIMIT+1},()=>({get quadPoints(){throw new Error('count admission must precede annotation traversal');}})):[square];
    const {page,viewport,operators,element}=appearanceFixture(1,0,annotations),budget=new PdfAppearanceDocumentBudget();
    element.text=element.normalized_text='Revenue 120 won';element.visibility_evidence=[{method:PDF_GEOMETRY_UNVERIFIED,bbox:element.bbox,assessment:'inferred',coverage:0}];
    if(reason==='operators')operators.fnArray.length=250001;
    if(reason==='evidence')for(let remaining=PDF_APPEARANCE_LIMITS.document.evidence;remaining>0;remaining-=PDF_APPEARANCE_LIMITS.page.evidence)budget.page()('evidence',Math.min(remaining,PDF_APPEARANCE_LIMITS.page.evidence));
    const elements=[element],result=await inspectAppearance(page,viewport,elements,{},'sha256:budget',budget),carriers=elements.filter(e=>e.method===PDF_ANNOTATION_CARRIER);
    assert.equal(element.text,'Revenue 120 won');assert.equal(element.visibility,'unverified');assert.deepEqual(element.visibility_spans,[]);
    assert.equal(carriers.length,1,reason);assert.ok(carriers[0].source_ref.endsWith('/BudgetExceeded'));assert.equal(carriers[0].comparison_role,'excluded');assert.equal(carriers[0].text,'');
    assert.ok(annotationBlocksRegion(elements,[.8,.8,.1,.1]),'Uninspected annotations retain a full-page veto');
    const after=observedPage(elements,result.gaps),bbox:[number,number,number,number]=[.1,.3,.3,.1];
    const native:NativePageResult={version:'synthetic-budget-observation',revision:3,languages:['en-US'],language_correction:false,ocr_performed:true,renderer:'fixture',verification:'fixture',viewport_width:600,viewport_height:400,rotation:0,width:1200,height:800,render_sha256:'b'.repeat(64),lines:[{text:'Revenue 120 won',confidence:1,bbox,strike_candidate:false,strike_status:'not_detected',strike_bbox:[0,0,0,0],numeric_consensus:true,numeric_readings:[],tokens:[],alternatives:[],reconsideration:undefined,reconsideration_error:undefined}]};
    await supplementPdfOcr(after,new Uint8Array(),{nativeResult:native});
    const ocr=after.elements.find(e=>e.method==='vision_ocr')!;assert.ok(ocr);assert.equal(ocr.visibility,'uncertain');assert.equal(ocr.comparison_role,'unresolved');assert.equal(ocr.comparison_reason,'page_annotation_blocks_independent_raster');Page.parse(after);
    const before=structuredClone(after);before.page_id='page_before';before.raster={sha256:'a'.repeat(64),width:1200,height:800,renderer:'fixture',environment:'fixture'};before.elements=before.elements.filter(e=>e.method!==PDF_ANNOTATION_CARRIER);before.text=before.unresolved_text='Revenue 100 won';
    for(const e of before.elements){e.observation_id+='-before';e.text=e.normalized_text='Revenue 100 won';if(e.method==='vision_ocr')e.visibility='visible';}
    selectHybridComparison(before);
    // Stored reports may contain preselected OCR; diff must independently
    // apply the annotation carrier rather than trusting that stored role.
    ocr.visibility='visible';ocr.comparison_role='selected';after.raster={sha256:'b'.repeat(64),width:1200,height:800,renderer:'fixture',environment:'fixture'};
    const blocked=regionalChanges(before,after);assert.ok(!blocked.some(c=>c.kind==='text_modified'));assert.ok(blocked.some(c=>c.coverage_gaps.some(g=>g.reason==='page_annotation_prevents_inferred_raster_edit')));
    const control=structuredClone(after);control.elements=control.elements.filter(e=>e.method!==PDF_ANNOTATION_CARRIER);selectHybridComparison(control);assert.equal(regionalChanges(before,control).filter(c=>c.kind==='text_modified').length,1,'The retained carrier must be the active diff veto');
  }
});

test('PDF late appearance exhaustion retains already prepared bounded annotation regions',async()=>{
  const {page,viewport,element}=appearanceFixture(1000,5000,[square]),elements=[element];
  const result=await inspectAppearance(page,viewport,elements,{},'sha256:budget');
  assert.equal(element.visibility,'unverified');assert.ok(result.gaps.some(g=>g.reason==='appearance_budget_exceeded_visibility_unverified'));
  assert.equal(elements.filter(e=>e.method===PDF_ANNOTATION_CARRIER).length,1);assert.ok(annotationBlocksRegion(elements,[.1,.3,.3,.1]));
});
