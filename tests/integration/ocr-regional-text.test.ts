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
test('shifted regional text pairs reject extra observations on either same-page footprint',()=>{
 for(const side of ['old','new'] as const){
  const a=page('a','Customer approved'),b=page('b','Customer declined');b.elements[1].bbox=[.18,.3,.4,.05];
  const extra=line('sliver','additional words');extra.bbox=side==='old'?[.1,.3,.05,.05]:[.53,.3,.05,.05];
  (side==='old'?a:b).elements.push(extra);selectHybridComparison(a);selectHybridComparison(b);
  assert.equal(edits(a,b).length,0,side+' own-footprint ambiguity');
 }
});
test('wrapped word fragments withhold partial replacements while retaining an independent edit',()=>{
 for(const reverse of [false,true])for(const mode of ['following','preceding','hyphen','multiple','budget','characters','horizontal'] as const){
  const a=page('a','Customer approved'),b=page('b',mode==='preceding'?'Customer proved':mode==='hyphen'?'Customer appro-':mode==='budget'?'Customer a':'Customer appro');b.elements[1].bbox=[.1,.3,.3,.05];
  const tails=mode==='preceding'?[line('head','earlier ap',.24)]:mode==='multiple'?[line('tail1','ve',.36),line('tail2','d immediately',.42)]:mode==='budget'?[line('tail1','p',.36),line('tail2','p',.42),line('tail3','r',.48)]:[line('tail',mode==='characters'?'ved '+ 'x'.repeat(128):'ved immediately',.36)];
  for(const tail of tails){tail.bbox[2]=.08;b.elements.push(tail);}
  if(mode==='horizontal'){a.elements[1].bbox=[.1,.3,.3,.05];b.elements[1].bbox=[.1,.3,.24,.05];tails[0].bbox=[.41,.3,.08,.05];}
  a.elements.push(line('a-manager','Manager accepted',.7));b.elements.push(line('b-manager','Manager rejected',.7));selectHybridComparison(a);selectHybridComparison(b);
  const result=reverse?edits(b,a):edits(a,b);assert.equal(result.length,1,mode+' reverse='+reverse);assert.match(String(result[0].before),/^Manager /u);assert.match(String(result[0].after),/^Manager /u);
  const gaps=diffRevisions(rev(reverse?b:a,'r1'),rev(reverse?a:b,'r2'),[{from_page_id:(reverse?b:a).page_id,to_page_id:(reverse?a:b).page_id,score:1,status:'human_confirmed',reasons:[]}],[],()=> 'entity').filter(c=>c.coverage_gaps.some(g=>g.reason==='ocr_fragment_reflow_region_withheld'));
  assert.equal(gaps.length,1);assert.equal(gaps[0].kind,'coverage_gap');assert.equal(gaps[0].evidence[0].quote,reverse?b.elements[1].text:a.elements[1].text);assert.deepEqual(gaps[0].evidence[0].bbox,(reverse?b:a).elements[1].bbox);
 }
});
test('a token shortening without a nearby matching continuation remains a regional edit',()=>{
 for(const mode of ['absent','unrelated','far'] as const){
  const a=page('a','Customer approved'),b=page('b','Customer approve');b.elements[1].bbox=[.1,.3,.3,.05];
  if(mode!=='absent')b.elements.push(line('tail',mode==='far'?'d immediately':'different words',mode==='far'?.8:.36));selectHybridComparison(b);
  assert.equal(edits(a,b).length,1,mode);
 }
});

test('continuation fragments preserve hyphens only in raw evidence and search repeated boundaries both ways',()=>{
 for(const reverse of [false,true])for(const hyphen of ['-','\u00ad','\u2010'])for(const preceding of [false,true]){
  const a=page('a','Customer approved'),b=page('b',preceding?'Customer proved':'Customer appro');b.elements[1].bbox=[.1,.3,.3,.05];
  if(preceding)b.elements.push(line('head','earlier ap'+hyphen,.24));
  else b.elements.push(line('tail1','v'+hyphen,.36),line('tail2','ed immediately',.42));
  for(const e of b.elements.slice(2))e.bbox[2]=.08;
  a.elements.push(line('a-manager','Manager accepted',.7));b.elements.push(line('b-manager','Manager rejected',.7));selectHybridComparison(a);selectHybridComparison(b);
  const result=reverse?edits(b,a):edits(a,b);assert.equal(result.length,1,JSON.stringify({hyphen,preceding,reverse}));assert.match(String(result[0].before),/^Manager /u);
  assert.ok(b.elements.some(e=>e.text.includes(hyphen)),'raw hyphen remains');
 }
 for(const reverse of [false,true])for(const [longer,shorter,prefix] of [['murmur detected','mur detected','mur'],['ababa detected','aba detected','ab']]){
  const a=page('a',longer),b=page('b',shorter);a.elements.push(line('a-before','Earlier',.24));b.elements.push(line('b-before','Earlier '+prefix,.24));
  a.elements.push(line('a-manager','Manager accepted',.7));b.elements.push(line('b-manager','Manager rejected',.7));selectHybridComparison(a);selectHybridComparison(b);
  const result=reverse?edits(b,a):edits(a,b);assert.equal(result.length,1,longer+' '+reverse);assert.match(String(result[0].before),/^Manager /u);
 }
});
