import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {diffRevisions} from '../../packages/diff/index.js';
import {diffRevisions as archived54Diff} from '../../packages/diff/legacy-bundle-54.js';
import {equivalentPdfSourceLayout} from '../../packages/diff/pdf-source-layout.js';
import {QueryService} from '../../packages/query/index.js';
import {Store} from '../../packages/storage/index.js';
import {rangeLineage} from '../../packages/matching/lineage.js';
import {matchPages} from '../../packages/matching/index.js';
import {ENGINE_VERSION,SCHEMA_VERSION,SCHEMA_HASH,Page,Report,byteHash,id,normalize,type Box,type PageData,type ElementData,type RevisionData,type MatchData,type ReportData} from '../../packages/schema/index.js';

type Line={text:string;cuts?:number[];y?:number};
function page(key:string,lines:Line[],reverseRuns=false):PageData{
  const elements:ElementData[]=[];
  for(const [lineIndex,line] of lines.entries()){
    const y=line.y??.1+lineIndex*.12,h=.04,advance=.012,space=.008,characters:{text:string;bbox:Box;offset:number}[]=[];
    let x=.1;
    for(let offset=0;offset<line.text.length;offset++){
      const text=line.text[offset];if(/\s/u.test(text)){x+=space;continue;}
      characters.push({text,bbox:[x,y,advance,h],offset});x+=advance;
    }
    const boundaries=[0,...line.cuts??[],line.text.length];
    for(let i=0;i<boundaries.length-1;i++){
      const start=boundaries[i],end=boundaries[i+1],text=line.text.slice(start,end).trim(),glyphs=characters.filter(c=>c.offset>=start&&c.offset<end);
      if(!text)continue;
      const left=glyphs[0].bbox[0],right=glyphs.at(-1)!.bbox[0]+advance;
      elements.push({observation_id:key+'_run_'+elements.length,kind:'text',text,normalized_text:normalize(text),bbox:[left,y,right-left,h],reading_order:elements.length,availability:'available',method:'pdf_text',source_ref:key+'/run/'+elements.length,provenance:'observed',visibility:'visible',visibility_spans:glyphs.map(g=>({text:g.text,bbox:g.bbox,state:'visible',paint_index:elements.length,assessment:'inferred'}))});
    }
  }
  if(reverseRuns)elements.reverse();
  elements.forEach((e,i)=>e.reading_order=i);
  const text=elements.map(e=>e.text).join('\n');
  return Page.parse({page_id:key,asset_id:'asset_'+key,page:1,width:600,height:400,coordinate_system:'normalized_top_left',source_transform:[1,0,0,-1,0,400],hidden:null,text,visible_text:text,elements,notes:null,capabilities:{text:'available',notes:'unavailable',hidden_slides:'unavailable',animation:'unavailable',structure:'unavailable',preview:'available'},coverage_gaps:[]});
}
const revision=(p:PageData,key:string):RevisionData=>({revision_id:'rev_'+key,revision_occurrence_id:'occ_'+key,label:key,assets:[{asset_id:p.asset_id,format:'pdf',bytes:0}],status:'success',pages:[p],coverage_gaps:[],errors:[],bundle_mapping:[]});
const match=(a:PageData,b:PageData):MatchData=>({from_page_id:a.page_id,to_page_id:b.page_id,score:1,status:'human_confirmed',reasons:['locally authored exporter qualification']});
const changes=(a:PageData,b:PageData)=>diffRevisions(revision(a,'a'),revision(b,'b'),[match(a,b)],[],()=> 'family');
const equivalentGap=(rows:ReturnType<typeof changes>)=>rows.some(c=>c.kind==='coverage_gap'&&c.coverage_gaps.some(g=>g.reason==='pdf_source_run_layout_equivalent'));

test('split parentheses, mixed-script words and reordered paint runs retain source evidence and actual visual differences',()=>{
  for(const [text,cuts] of [['Review (USD) 100',[6,7,10,12]],['인증(MFA) 확인',[2,3,6,7]],['Revenue100',[3,7]]] as [string,number[]][]){
    const a=page('a',[{text}]),b=page('b',[{text,cuts}]);
    const before=JSON.stringify([a,b]);assert.notEqual(normalize(a.text),normalize(b.text));assert.ok(equivalentPdfSourceLayout(a,b));
    const rows=changes(a,b),gap=rows.find(c=>c.coverage_gaps.some(g=>g.reason==='pdf_source_run_layout_equivalent'))!;
    assert.ok(gap);assert.ok(!rows.some(c=>c.kind==='text_modified'));assert.deepEqual([gap.before,gap.after],[a.text,b.text]);assert.deepEqual(gap.evidence.map(e=>e.page_id),['a','b']);assert.equal(JSON.stringify([a,b]),before);
    a.raster={sha256:'a'.repeat(64),width:3000,height:2000,renderer:'PDFKit.thumbnail.cropBox',environment:'same-native-helper',page_box:'cropBox',rotation:0,render_policy:'pdfkit-300dpi-max4096-source-color-profile-v1'};
    b.raster={...a.raster,sha256:'b'.repeat(64)};
    const withRaster=changes(a,b),visual=withRaster.find(c=>c.kind==='visual_region_changed')!;assert.ok(visual);assert.equal(visual.appearance_assessment,'observed');assert.deepEqual(visual.evidence.map(e=>e.render_sha256),['a'.repeat(64),'b'.repeat(64)]);assert.ok(equivalentGap(withRaster));assert.ok(!withRaster.some(c=>c.kind==='text_modified'));
  }
  const a=page('paint_a',[{text:'Alpha'},{text:'Beta'}]),b=page('paint_b',[{text:'Alpha'},{text:'Beta'}],true);
  assert.ok(equivalentGap(changes(a,b)));assert.ok(!changes(a,b).some(c=>c.kind==='text_modified'));
});

test('actual digits, decimal signs, bullets, units and internal token boundaries retain edits',()=>{
  for(const [before,after] of [['Revenue 100','Revenue 101'],['Rate 1.00','Rate 100'],['Balance -100','Balance 100'],['• Approved','Approved'],['Weight 100 kg','Weight 100 g'],['Revenue 1 00','Revenue 100'],['Customer accepted','Customer declined']]){
    const a=page('a',[{text:before}]),b=page('b',[{text:after,cuts:[Math.max(1,after.indexOf(' '))]}]),rows=changes(a,b);
    assert.equal(equivalentPdfSourceLayout(a,b),false,before+' -> '+after);assert.ok(!equivalentGap(rows));assert.ok(rows.some(c=>c.kind==='text_modified'),before+' -> '+after);
  }
});

test('spatial row value swaps and repeated-content count changes cannot become run equivalence',()=>{
  const pairs:[PageData,PageData][]=[
    [page('a',[{text:'North 100'},{text:'South 200'}]),page('b',[{text:'North 200',cuts:[5]},{text:'South 100',cuts:[5]}])],
    [page('a',[{text:'Total 100'},{text:'Total 100'}]),page('b',[{text:'Total 100',cuts:[5]}])],
    [page('a',[{text:'AA'}]),page('b',[{text:'AAA',cuts:[1,2]}])]
  ];
  for(const [a,b] of pairs){assert.equal(equivalentPdfSourceLayout(a,b),false);const rows=changes(a,b);assert.ok(!equivalentGap(rows));assert.ok(rows.some(c=>c.kind==='text_modified'));}
});

test('unresolved, OCR, strike and unsupported glyph geometry cannot certify equality',()=>{
  const fresh=()=>[page('a',[{text:'Review(USD)'}]),page('b',[{text:'Review(USD)',cuts:[6,7,10]}])] as const;
  const mutators:((p:PageData)=>void)[]=[
    p=>{p.elements[0].visibility='uncertain';p.unresolved_text=p.elements[0].text;},
    p=>{p.elements[0].method='vision_ocr';p.elements[0].provenance='inferred';},
    p=>{p.comparison_basis='raster_ocr';},
    p=>{p.elements[0].visibility='struck_through';p.elements[0].visibility_spans!.forEach(s=>s.state='struck_through');},
    p=>{p.elements[0].visibility_spans=undefined;},
    p=>{p.elements[0].visibility_spans![0].text='X';},
    p=>{p.elements[0].visibility_spans![0].bbox[2]=0;},
    p=>{p.elements[0].visibility_spans![1].bbox[0]=.01;},
    p=>{p.elements[0].visibility_spans![1].bbox[1]=.7;},
    p=>{p.elements[0].visibility_spans![1].bbox[0]=p.elements[0].visibility_spans![0].bbox[0]+.001;},
    p=>{p.elements[0].visibility_evidence=[{method:'pdf_text_geometry_estimated_or_unavailable',bbox:p.elements[0].bbox,assessment:'inferred',coverage:0}];},
    p=>{p.capabilities.text='unavailable';},
    p=>{p.source_transform=[0,1,-1,0,400,0];},
    p=>{p.source_transform=[-1,0,0,-1,600,400];},
    p=>{p.source_transform=[];},
    p=>{p.width=400;},
    p=>{p.elements.push({observation_id:'annotation',kind:'shape',text:'',normalized_text:'',bbox:[.1,.1,.2,.05],reading_order:p.elements.length,availability:'available',method:'pdf_page_annotation',source_ref:'annot',provenance:'observed',visibility_evidence:[{method:'pdf_annotation_region_requires_review',bbox:[.1,.1,.2,.05],assessment:'inferred',coverage:1}]});},
    p=>{p.elements.forEach(e=>{e.bbox[0]+=.2;e.visibility_spans!.forEach(s=>s.bbox[0]+=.2);});}
  ];
  for(const mutate of mutators){const [a,b]=fresh();mutate(b);assert.equal(equivalentPdfSourceLayout(a,b),false,mutate.toString());assert.ok(!equivalentGap(changes(a,b)));}
  const [a,b]=fresh();b.unresolved_text='Unlocalized unreadable source';assert.ok(!equivalentGap(changes(a,b)),'page-level uncertainty prevents equivalence');
  const unresolved=diffRevisions(revision(a,'a'),revision(b,'b'),[{...match(a,b),status:'needs_review'}],[],()=> 'family');assert.ok(!equivalentGap(unresolved),'unresolved page association prevents equivalence');
  const bidiA=page('bidi_a',[{text:'Rev\u202eenue100'}]),bidiB=page('bidi_b',[{text:'Rev\u202eenue100',cuts:[4]}]);assert.equal(equivalentPdfSourceLayout(bidiA,bidiB),false,'Bidi control changes logical/visual ordering rules');assert.ok(!equivalentGap(changes(bidiA,bidiB)));
  for(const text of ['שלום','سلام']){
    const cuts=[1,2,3],rtlA=page('rtl_a',[{text,cuts}]),rtlB=page('rtl_b',[{text,cuts}],true);
    assert.notEqual(rtlA.text,rtlB.text);assert.equal(equivalentPdfSourceLayout(rtlA,rtlB),false,'RTL single-glyph paint runs need an independent logical-order proof');assert.ok(!equivalentGap(changes(rtlA,rtlB)));
  }
  const [bandA,bandB]=fresh();bandB.elements.slice(1).forEach(e=>{e.bbox[0]+=.002;e.visibility_spans!.forEach(s=>s.bbox[0]+=.002);});assert.equal(equivalentPdfSourceLayout(bandA,bandB),false,'Ambiguous inter-run gap cannot prove a join');assert.ok(!equivalentGap(changes(bandA,bandB)));
});

test('run and glyph work limits retain comparison instead of certifying an exhausted proof',()=>{
  function boundedPage(key:string,glyphCount:number,runCount:number):PageData{
    const p=page(key,[{text:'A'}]),width=.8/glyphCount,h=.04,elements:ElementData[]=[];
    for(let run=0;run<runCount;run++){
      const start=Math.floor(run*glyphCount/runCount),end=Math.floor((run+1)*glyphCount/runCount),text='A'.repeat(end-start);
      elements.push({...p.elements[0],observation_id:key+'_'+run,text,normalized_text:text,reading_order:run,bbox:[.1+start*width,.1,(end-start)*width,h],visibility_spans:Array.from({length:end-start},(_,offset)=>({text:'A',state:'visible',bbox:[.1+(start+offset)*width,.1,width,h] as Box,paint_index:run,assessment:'inferred'}))});
    }
    p.elements=elements;p.text=p.visible_text=elements.map(e=>e.text).join('\n');return Page.parse(p);
  }
  const atGlyphLimit=boundedPage('at_glyphs',32_768,1),atBothLimits=boundedPage('at_both',32_768,2_048);
  assert.ok(equivalentPdfSourceLayout(atGlyphLimit,atBothLimits),'Valid geometry at both published proof limits remains eligible');
  const overGlyphLimit=boundedPage('over_glyphs',32_769,1);assert.equal(equivalentPdfSourceLayout(overGlyphLimit,overGlyphLimit),false,'One extra glyph exhausts the proof budget');
  const overRunLimit=boundedPage('over_runs',2_049,2_049),sameGlyphs=boundedPage('same_glyphs',2_049,1);assert.equal(equivalentPdfSourceLayout(sameGlyphs,overRunLimit),false,'One extra independently valid run exhausts the proof budget');
  const rows=changes(sameGlyphs,overRunLimit);assert.ok(!equivalentGap(rows));assert.ok(rows.some(c=>c.kind==='text_modified'));
});

test('archived engine54 preserves exact source bytes, full range events, canonical selector IDs and evidence',async()=>{
  assert.equal(byteHash(await readFile(new URL('../../packages/diff/legacy-bundle-54.ts',import.meta.url))),'f9cf2288187c45a9fe21a8fe2186f28dfa4a20b1e0c2a1a4bf5d86304724e1d3');
  const a=page('a',[{text:'Review(USD)'}]),b=page('b',[{text:'Review(USD)',cuts:[6,7,10]}]),revisions=[revision(a,'a'),revision(b,'b')];
  const report:ReportData={schema_version:SCHEMA_VERSION,engine_version:'0.4.0-native.bundle.54',schema_hash:SCHEMA_HASH,project_id:'project',report_id:'report54',timeline_revision_id:'timeline',mapping_revision_id:'mapping',observation_environment:{},revisions,matches:[match(a,b)],candidates:[],mapping_decisions:[],mapping_relations:[],bundle_decisions:[],lineages:[{entity_id:'family',page_ids:['a','b'],status:'human_confirmed'}],changes:[],coverage_gaps:[]};
  const directed=rangeLineage(report,revisions[0],revisions[1]),expected=archived54Diff(revisions[0],revisions[1],directed.matches,matchPages([a],[b]).candidates,()=> 'family',directed.structural).map((c,i)=>({...c,report_id:report.report_id,change_id:id('net',[report.report_id,'occ_a','occ_b',i,c]),evidence_uri:'docver://projects/project/reports/report54/manifest'}));
  const currentExpected=diffRevisions(revisions[0],revisions[1],directed.matches,matchPages([a],[b]).candidates,()=> 'family',directed.structural).map((c,i)=>({...c,report_id:report.report_id,change_id:id('net',[report.report_id,'occ_a','occ_b',i,c]),evidence_uri:'docver://projects/project/reports/report54/manifest'}));
  assert.ok(expected.some(c=>c.kind==='text_modified'),'engine54 actually reproduces the original representation edit');report.changes=expected;Report.parse(report);const frozen=JSON.stringify(report);
  const query=new QueryService({} as Store,new Set(['project']),()=>report),base={project_id:'project',report_id:'report54',max_output_tokens:8000};
  for(const [from,to] of [['rev_a','rev_b'],['occ_a','occ_b']]){
    const args={...base,from,to};assert.deepEqual(query.changeSet({...args,mode:'range_net'}),expected);assert.deepEqual(query.changeSet({...args,mode:'history'}),expected);
    for(const event of expected){const evidence=query.query('get_evidence',{...args,change_id:event.change_id});assert.deepEqual(evidence.items,event.evidence.map(e=>({...e,text_offset:0,next_text_offset:null})));}
    const current={...report,engine_version:ENGINE_VERSION},latest=new QueryService({} as Store,new Set(['project']),()=>current),net=latest.changeSet({...args,mode:'range_net'});
    assert.deepEqual(net,currentExpected);assert.ok(equivalentGap(net));assert.ok(!net.some(c=>c.kind==='text_modified'));assert.deepEqual(latest.changeSet({...args,mode:'history'}),expected);
    for(const event of net){const evidence=latest.query('get_evidence',{...args,change_id:event.change_id});assert.deepEqual(evidence.items,event.evidence.map(e=>({...e,text_offset:0,next_text_offset:null})));}
  }
  assert.equal(JSON.stringify(report),frozen);assert.equal(byteHash(await readFile(new URL('../../packages/diff/legacy-bundle-54.ts',import.meta.url))),'f9cf2288187c45a9fe21a8fe2186f28dfa4a20b1e0c2a1a4bf5d86304724e1d3');
});
