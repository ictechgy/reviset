import {test} from 'node:test';
import assert from 'node:assert/strict';
import {diffRevisions} from '../../packages/diff/index.js';
import {selectHybridComparison} from '../../packages/ingest/comparison-selection.js';
import {Page,type PageData,type ElementData,type RevisionData,type MatchData} from '../../packages/schema/index.js';
function line(key:string,text:string,y=.3):ElementData{return {observation_id:key,kind:'text',text,normalized_text:text,bbox:[.1,y,.4,.05],reading_order:0,availability:'available',method:'vision_ocr',source_ref:key,provenance:'inferred',visibility:'visible',ocr:{confidence:1,confidence_scope:'line',strike_status:'not_detected',numeric_consensus:true,ambiguous:false,alternatives:[{text,confidence:1,truncated:false}]}};}
function page(key:string,text:string):PageData{
 const header=line(key+'-header','Contract review',.04);header.ocr!.confidence=.5;header.ocr!.reconsideration_observation={status:'unsupported_background',band_bbox:header.bbox,contexts:[]};
 const p:PageData={page_id:key,asset_id:key,page:1,width:960,height:540,coordinate_system:'normalized',source_transform:[],hidden:null,text:'',elements:[header,line(key+'-body',text)],notes:null,capabilities:{text:'available',notes:'unavailable',hidden_slides:'unavailable',animation:'unavailable',structure:'unavailable',preview:'available'},coverage_gaps:[],raster:{sha256:(key==='a'?'a':'b').repeat(64),width:1920,height:1080,renderer:'fixture',environment:'same'},ocr:{status:'available',engine:'fixture',environment:'same',width:1920,height:1080}};selectHybridComparison(p);Page.parse(p);return p;
}
const rev=(p:PageData,key:string):RevisionData=>({revision_id:key,revision_occurrence_id:key,label:key,assets:[{asset_id:p.asset_id,format:'pdf',bytes:0}],status:'success',pages:[p],coverage_gaps:p.coverage_gaps,errors:[],bundle_mapping:[]});
const edits=(a:PageData,b:PageData,change:Partial<MatchData>={})=>diffRevisions(rev(a,'r1'),rev(b,'r2'),[{from_page_id:a.page_id,to_page_id:b.page_id,score:1,status:'human_confirmed',reasons:['explicit page correspondence'],...change}],[],()=> 'entity').filter(c=>c.kind==='text_modified');
test('disjoint unresolved OCR retains anchored nonnumeric regional edits with exact inferred evidence',()=>{
 for(const status of ['human_confirmed','inferred'] as const){const a=page('a','Customer approved'),b=page('b','Customer declined'),result=edits(a,b,{status});assert.equal(result.length,1);const c=result[0];assert.equal(c.before,'Customer approved');assert.equal(c.after,'Customer declined');assert.equal(c.text_scope,'region');assert.equal(c.region_pairing_assessment,'inferred');assert.equal(c.text_assessment,'inferred');assert.deepEqual(c.evidence.map(e=>[e.quote,e.bbox]),[['Customer approved',a.elements[1].bbox],['Customer declined',b.elements[1].bbox]]);assert.equal(a.elements[0].comparison_role,'unresolved');assert.ok(c.coverage_gaps.some(g=>g.reason==='other_page_regions_unresolved'));}
 const a=page('a','Customer approved'),b=page('b','Customer declined');a.elements.push(line('a-second','Manager accepted',.6));b.elements.push(line('b-second','Manager rejected',.6));selectHybridComparison(a);selectHybridComparison(b);assert.equal(edits(a,b).length,2);
});
test('regional nonnumeric inference preserves page, producer, movement, reflow and numeric ambiguity guards',()=>{
 const reject=(mutate:(a:PageData,b:PageData)=>void,match:Partial<MatchData>={})=>{const a=page('a','Customer approved'),b=page('b','Customer declined');mutate(a,b);assert.equal(edits(a,b,match).length,0);};
 reject(()=>{}, {status:'needs_review'});
 reject((a,b)=>{b.raster!.sha256=a.raster!.sha256;});
 reject((_a,b)=>{b.ocr!.environment='different';b.raster!.environment='different';});
 reject((_a,b)=>{b.ocr!.width=100;});
 reject((_a,b)=>{b.raster=undefined;});
 reject((_a,b)=>{const extra=line('moved','Customer approved',.6);b.elements.push(extra);selectHybridComparison(b);});
 reject((a,_b)=>{a.elements.push(line('duplicate','Customer approved'));selectHybridComparison(a);});
 reject((a,_b)=>{const unknown=line('uncertain','unreadable');unknown.visibility='uncertain';a.elements.push(unknown);selectHybridComparison(a);});
 reject((_a,b)=>{b.elements.push({...line('annotation','Redact'),method:'pdf_page_annotation',provenance:'observed',source_ref:'page:1/annotation:0/Redact',visibility:'unverified',visibility_evidence:[{method:'pdf_annotation_region_requires_review',bbox:[.1,.3,.4,.05],coverage:1,assessment:'inferred'}]});selectHybridComparison(b);});
 reject((a,b)=>{a.elements[1].text='Customer';b.elements[1].text='Manager';});
 reject((_a,b)=>{b.elements[1].text='Different topic';});
 reject((_a,b)=>{b.elements[1].text='Customer decline d';});
 reject((a,b)=>{a.elements[1].text='Customer amount 100';b.elements[1].text='Customer amount 120 130';});
 reject((_a,b)=>{b.elements[1].bbox=[.1,.3,.4,.035];b.elements.push(line('wrap-tail','additional words',.335));selectHybridComparison(b);});
 reject((a,_b)=>{a.elements[1].bbox=[.1,.3,.4,.035];a.elements.push(line('merge-tail','additional words',.335));selectHybridComparison(a);});
 reject((a,b)=>{a.elements.push(line('a-next','Customer declined',.6));b.elements.push(line('b-next','Customer approved',.6));selectHybridComparison(a);selectHybridComparison(b);});
 // The primary body remains a separate inferred observation when source text
 // with unverified geometry disagrees; it must not silently settle that source.
 reject((a,_b)=>{a.elements.push({...line('source','Different source'),method:'pdf_text',provenance:'observed',visibility:'unverified',visibility_evidence:[{method:'pdf_text_geometry_estimated_or_unavailable',bbox:[0,0,1,1],assessment:'inferred',coverage:1}]});selectHybridComparison(a);});
});
test('pre-hybrid numeric regional evidence retains the existing single-slot contract',()=>{
 const a=page('a','Revenue 100'),b=page('b','Revenue 120');for(const p of [a,b]){p.comparison_basis='raster_ocr';p.ocr_text=p.elements[1].text;p.ocr_unresolved_text='Unresolved header';for(const e of p.elements){delete e.comparison_role;delete e.comparison_reason;}}
 assert.equal(edits(a,b).length,1);
});
