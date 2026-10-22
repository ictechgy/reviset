import {test} from 'node:test';
import assert from 'node:assert/strict';
import PDFDocument from 'pdfkit';
import {rectanglePath,PDF_RECTANGLE_PATH_POLICY} from '../../packages/ingest/pdf-geometry.js';
import {extractPdf} from '../../packages/ingest/pdf.js';
import {byteHash,Page,id,canonical,type PageData,type RevisionData} from '../../packages/schema/index.js';
import {diffRevisions} from '../../packages/diff/index.js';
import {analyze} from '../../packages/engine/index.js';
import {Store} from '../../packages/storage/index.js';
import {mkdtemp,writeFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';

// Actual LibreOffice 26.8.1.1 Impress white rectangle: start on an edge,
// explicitly return to that midpoint, then close. Coordinates are PDF.js's
// Float32 operator values, independently captured from the exported PDF.
const libreOfficeCover=[0,273.5719909667969,244.85699462890625,1,50.400001525878906,244.85699462890625,1,50.400001525878906,309.6000061035156,1,496.7430114746094,309.6000061035156,1,496.7430114746094,244.85699462890625,1,273.5719909667969,244.85699462890625,4];
function path(points:number[][],close=true){return points.flatMap((p,i)=>[i?1:0,...p]).concat(close?[4]:[]);}

test('LibreOffice edge-midpoint and redundant-closing rectangles remain rectangles',()=>{
  assert.equal(rectanglePath([new Float32Array(libreOfficeCover)]),true);
  for(const points of [
    [[0,0],[10,0],[10,10],[0,10]],
    [[0,0],[0,10],[10,10],[10,0]],
    [[0,0],[10,0],[10,10],[0,10],[0,0]],
    [[5,0],[0,0],[0,5],[0,10],[10,10],[10,0],[5,0]],
    [[5,0],[5,0],[0,0],[0,0],[0,10],[10,10],[10,0],[5,0],[5,0]],
  ])assert.equal(rectanglePath([path(points)]),true,JSON.stringify(points));
  assert.equal(rectanglePath([[0,0,0,1,10,0],[1,10,10,1,0,10,4]]),true,'Buffers may split one subpath');
});

test('rectangle recognition rejects nonrectangular, backtracking, multiple and unbounded paths',()=>{
  for(const points of [
    [[0,0],[10,0],[10,5],[5,5],[5,10],[0,10]], // concave
    [[0,0],[10,0],[5,0],[10,0],[10,10],[0,10]], // backtracking
    [[0,0],[10,10],[10,0],[0,10]], // crossing diagonals
    [[0,0],[10,0],[10.001,10],[0,10]], // nearly rectangular is not proof
    [[0,0],[10,0],[10,0],[0,0]], // zero area
    [[0,0],[10,0],[10,10],[0,10],[0,0],[10,0],[10,10],[0,10]], // twice wound
  ])assert.equal(rectanglePath([path(points)]),false,JSON.stringify(points));
  const rectangle=path([[0,0],[10,0],[10,10],[0,10]]);
  for(const invalid of [
    [path([[0,0],[10,0],[10,10],[0,10]],false)],
    [rectangle,rectangle],
    [[...rectangle.slice(0,-1),...path([[2,2],[8,2],[8,8],[2,8]])]],
    [[0,0,0,2,0,10,10,10,10,0,4]],
    [[0,0,0,3,10,0,10,10,4]],
    [[...rectangle,4]],[[...rectangle,1,0,0]],
    [rectangle.map((v,i)=>i===1?NaN:v)],
    [rectangle.map((v,i)=>i===1?Infinity:v)],
    [path([[-Number.MAX_VALUE,0],[Number.MAX_VALUE,0],[Number.MAX_VALUE,10],[-Number.MAX_VALUE,10]])],
    [new Float64Array(10000)],null,{},[{}],[new DataView(new ArrayBuffer(16))],
  ])assert.equal(rectanglePath(invalid),false);
});

async function pdf(kind:'none'|'opaque'|'transparent'|'concave'|'backtrack',clip?:'rectangle'|'concave'){
  const d=new PDFDocument({size:[300,200],margin:0,compress:false}),chunks:Buffer[]=[];d.on('data',b=>chunks.push(b));const done=new Promise<Buffer>(r=>d.on('end',()=>r(Buffer.concat(chunks))));
  if(clip){d.save().moveTo(150,60).lineTo(30,60).lineTo(30,120).lineTo(270,120);if(clip==='concave')d.lineTo(270,100).lineTo(180,100).lineTo(180,60);else d.lineTo(270,60);d.lineTo(150,60).closePath().clip('even-odd');}
  d.font(resolve('node_modules/pdfjs-dist/standard_fonts/LiberationSans-Regular.ttf')).fontSize(20).fillColor('black').text('COVERED SECRET 42',40,80,{lineBreak:false});
  if(clip)d.restore();
  if(kind!=='none'){
    d.save().fillColor('white');if(kind==='transparent')d.fillOpacity(.5);
    // PDFKit emits a real M/L/Z path, including the start-edge subdivision.
    d.moveTo(150,70).lineTo(30,70);
    if(kind==='backtrack')d.lineTo(80,70).lineTo(30,70);
    d.lineTo(30,120).lineTo(270,120);
    if(kind==='concave')d.lineTo(270,100).lineTo(180,100).lineTo(180,70);
    else d.lineTo(270,70);
    d.lineTo(150,70).closePath().fill('white','even-odd').restore();
  }
  d.end();return done;
}
function changes(a:PageData,b:PageData){const rev=(p:PageData,key:string):RevisionData=>({revision_id:key,revision_occurrence_id:key,label:key,assets:[{asset_id:p.asset_id,format:'pdf',bytes:0}],status:'success',pages:[p],coverage_gaps:p.coverage_gaps,errors:[],bundle_mapping:[]});return diffRevisions(rev(a,'before'),rev(b,'after'),[{from_page_id:a.page_id,to_page_id:b.page_id,score:1,status:'human_confirmed',reasons:['controlled_single_page']}],[],()=> 'entity');}

test('real PDF redundant rectangle produces inferred occlusion without accepting unsafe controls',async()=>{
  const loaded:Record<string,PageData>={};
  for(const kind of ['none','opaque','transparent','concave','backtrack'] as const){const bytes=await pdf(kind);loaded[kind]=(await extractPdf(bytes,'sha256:'+byteHash(bytes),{ocr:'off'}))[0];Page.parse(loaded[kind]);}
  const element=(kind:string)=>loaded[kind].elements.find(e=>e.text==='COVERED SECRET 42')!;
  assert.equal(element('none').visibility,'visible');
  assert.equal(element('opaque').visibility,'occluded');
  assert.ok(element('opaque').visibility_evidence?.some(e=>e.method==='later_opaque_rectangle_per_glyph'&&e.assessment==='inferred'));
  assert.ok(!loaded.opaque.visible_text?.includes('COVERED SECRET'));
  const event=changes(loaded.none,loaded.opaque).find(c=>c.kind==='text_occluded');assert.ok(event);assert.equal(event.appearance_assessment,'inferred');
  for(const kind of ['transparent','concave','backtrack']){
    assert.equal(element(kind).visibility,'uncertain',kind);
    assert.ok(!changes(loaded.none,loaded[kind]).some(c=>c.kind==='text_occluded'),kind);
    assert.ok(loaded[kind].coverage_gaps.some(g=>g.reason==='visibility_requires_review:uncertain'),kind);
  }
});

test('redundant rectangular clipping preserves text while concave clipping stays unverified',async()=>{
  for(const clip of ['rectangle','concave'] as const){const bytes=await pdf('none',clip),[page]=await extractPdf(bytes,'sha256:'+byteHash(bytes),{ocr:'off'}),element=page.elements.find(e=>e.text==='COVERED SECRET 42')!;
    if(clip==='rectangle'){assert.equal(element.visibility,'visible');assert.ok(!page.coverage_gaps.some(g=>g.reason==='clipping_or_soft_mask_visibility_not_fully_verified'));}
    else{assert.notEqual(element.visibility,'visible');assert.ok(page.coverage_gaps.some(g=>g.reason==='clipping_or_soft_mask_visibility_not_fully_verified'));}
    Page.parse(page);
  }
});

test('rectangle policy distinguishes unchanged observation identities and fixed reports replay exactly',async()=>{
  const folder=await mkdtemp(join(tmpdir(),'reviset-rectangle-policy-')),store=new Store(join(folder,'store'));
  try{await writeFile(join(folder,'input.pdf'),await pdf('none'));const input={project_id:'prj_rectangle_identity',title:'Rectangle policy',revisions:[{label:'unchanged',files:['input.pdf']}],mapping_decisions:[]};
    const {report}=await analyze(input,folder,store,undefined,undefined,{ocr:'off',pptxPreview:false});assert.equal(report.observation_environment.pdf_rectangle_path_policy,PDF_RECTANGLE_PATH_POLICY);assert.equal(report.changes.length,0);
    const {report_id,...base}=report;assert.equal(report_id,id('rpt',base));const {pdf_rectangle_path_policy,...oldEnvironment}=base.observation_environment;
    assert.notEqual(report_id,id('rpt',{...base,observation_environment:oldEnvironment}),'Policy changes identity even when pages need no rectangle recognition');
    const before=canonical(store.report(report.project_id,report_id)),again=(await analyze(input,folder,store,undefined,undefined,{ocr:'off',pptxPreview:false})).report;
    assert.equal(again.report_id,report_id);assert.equal(canonical(store.report(report.project_id,report_id)),before);
  }finally{store.close();await rm(folder,{recursive:true,force:true});}
});
