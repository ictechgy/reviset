import {test} from 'node:test';
import assert from 'node:assert/strict';
import {Page,type PageData} from '../../packages/schema/index.js';
import {supplementPdfOcr,type NativePageResult} from '../../packages/ingest/ocr.js';

test('ambiguous glyph strokes retain available OCR and uncertain text through page validation',async()=>{
  const page:PageData={page_id:'page_strike_status',asset_id:'asset_strike_status',page:1,width:960,height:540,coordinate_system:'normalized',source_transform:[],hidden:null,text:'',elements:[],notes:null,capabilities:{text:'available',notes:'unavailable',hidden_slides:'unavailable',animation:'unavailable',structure:'unavailable',preview:'available'},coverage_gaps:[]};
  const result:NativePageResult={version:'docver-vision-27-strike-ink-separation',revision:3,languages:['en-US'],language_correction:false,ocr_performed:true,renderer:'fixture',verification:'fixture',viewport_width:960,viewport_height:540,rotation:0,width:960,height:540,render_sha256:'a'.repeat(64),lines:[{text:'6',confidence:1,bbox:[.1,.2,.05,.05],strike_candidate:false,strike_status:'ambiguous_glyph_stroke',strike_bbox:[0,0,0,0],numeric_consensus:true,numeric_readings:['6'],tokens:[],alternatives:[],reconsideration:undefined,reconsideration_error:undefined}]};
  await supplementPdfOcr(page,new Uint8Array(),{nativeResult:result});
  const saved=Page.parse(JSON.parse(JSON.stringify(page)));
  assert.equal(saved.ocr?.status,'available');assert.equal(saved.elements.length,1);
  assert.equal(saved.elements[0].text,'6');assert.equal(saved.elements[0].availability,'available');
  assert.equal(saved.elements[0].visibility,'uncertain');assert.equal(saved.elements[0].ocr?.strike_status,'ambiguous_glyph_stroke');
  assert.ok(saved.coverage_gaps.some(g=>g.feature==='strike_ocr'&&g.reason==='raster_strike_ambiguous_glyph_stroke'));
  assert.ok(!saved.coverage_gaps.some(g=>g.reason==='OCR_FAILED'));
});
