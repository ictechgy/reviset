import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,mkdir,writeFile,readFile,readdir,link,rm,rename} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {randomUUID} from 'node:crypto';
import PptxGenJS from 'pptxgenjs';
import {extractPptx} from '../../packages/ingest/pptx.js';
import {byteHash,hash,DocverError,type ReportData} from '../../packages/schema/index.js';
import {parseOnlyOfficeFonts} from '../../packages/render/onlyoffice-fonts.js';
import {rethrowSidecarConversionError,SidecarScope,sidecarSource,verifySidecarMapping,verifySidecarMappingCancellable,createOnlyOfficeSidecar,closeOnlyOfficeSidecar,recoverOnlyOfficeSidecars} from '../../packages/render/onlyoffice-sidecar.js';
import {setImmediate as yieldTurn} from 'node:timers/promises';
import {optionalSidecarBuild} from '../../scripts/onlyoffice-build-policy.js';

const deck=new (PptxGenJS as unknown as typeof PptxGenJS.default)();
for(const text of ['Alpha roadmap ownership','Beta review schedule'])deck.addSlide().addText(text,{x:1,y:1,w:6,h:1});
const bytes=await deck.write({outputType:'nodebuffer'}) as Buffer,asset_id='sha256:'+byteHash(bytes),pages=extractPptx(bytes,asset_id);
// The selector consumes only these fields; real PageData comes from extraction.
const report={project_id:'prj_sidecar',report_id:'rpt_sidecar',revisions:[{revision_occurrence_id:'occ_a',assets:[{asset_id,format:'pptx',bytes:bytes.length}],pages}]} as ReportData;
const scope=()=>SidecarScope.parse({project_id:report.project_id,report_id:report.report_id,revision_occurrence_id:'occ_a',page_id:pages[0].page_id,session_id:randomUUID()});
const rendered=()=>pages.map(p=>({width:p.width,height:p.height,text:p.text}));
const metadata=(file='/System/Library/Fonts/Helvetica.ttc')=>Buffer.from(Object.entries({__all_fonts_js_version__:2,__fonts_files:[file],__fonts_infos:[['Helvetica',0,0,-1,-1,-1,-1,-1,-1]],__fonts_ranges:[0,127,0],g_fonts_selection_bin:'AA=='}).map(([k,v])=>`window["${k}"] = ${JSON.stringify(v)};`).join('\n'));

test('host metadata requires explicit selection and the private app name',()=>{
  for(const name of ['Docver.app','Docver-MCP.app','Docver-Render.app'])assert.equal(optionalSidecarBuild(name,undefined),false);
  assert.equal(optionalSidecarBuild('Docver-Render.app','host-bound'),true);
  for(const [name,flag]of [['Docver.app','host-bound'],['Docver-MCP.app','host-bound'],['Docver-Render.app',''],['Docver-Render.app','true']])assert.throws(()=>optionalSidecarBuild(name,flag));
});

test('sidecar source uses immutable report and occurrence membership without changing the report',()=>{
  const before=hash(report),d=scope();assert.equal(sidecarSource(report,d).asset.asset_id,asset_id);
  const repeated=structuredClone(report);repeated.revisions.push({...repeated.revisions[0],revision_occurrence_id:'occ_b'});
  assert.equal(sidecarSource(repeated,{...d,revision_occurrence_id:'occ_b'}).page.page_id,d.page_id);
  assert.equal(hash(report),before);
  for(const changed of [{project_id:'prj_other'},{report_id:'latest'},{revision_occurrence_id:'occ_missing'},{page_id:pages[1].page_id+'missing'}])assert.throws(()=>sidecarSource(report,{...d,...changed}));
  const duplicate=structuredClone(report);duplicate.revisions[0].pages.push(duplicate.revisions[0].pages[0]);assert.throws(()=>sidecarSource(duplicate,d));
  const traversal=structuredClone(report);traversal.revisions[0].assets[0].asset_id='sha256:../../outside';traversal.revisions[0].pages[0].asset_id='sha256:../../outside';assert.throws(()=>sidecarSource(traversal,d),/원본 ID/u);
});

test('sidecar mapping rejects reordered, hidden, missing and ambiguous pages',()=>{
  verifySidecarMapping(pages,rendered());
  assert.throws(()=>verifySidecarMapping(pages,rendered().reverse()));
  assert.throws(()=>verifySidecarMapping(pages,rendered().slice(1)));
  assert.throws(()=>verifySidecarMapping([{...pages[0],hidden:true},pages[1]],rendered()));
  assert.throws(()=>verifySidecarMapping(pages,rendered().map(p=>({...p,text:'shared heading'}))));
  assert.throws(()=>verifySidecarMapping(pages,rendered().map(p=>({...p,text:pages.map(p=>p.text).join(' ')}))));
  assert.throws(()=>verifySidecarMapping([{...pages[0],width:0,height:0},pages[1]],rendered()));
  assert.throws(()=>verifySidecarMapping(pages,[{...rendered()[0],width:10,height:900},rendered()[1]]));
});

test('nested headings do not masquerade as another page when independent anchors exist',()=>{
  const texts=['Alpha roadmap ownership\nExclusive starter details','Alpha roadmap ownership extended\nDistinct review checklist'];
  const nested=pages.map((p,i)=>({...p,text:texts[i],elements:p.elements.map((e,j)=>({...e,text:j===0?texts[i]:''}))}));
  const rendered=nested.map(p=>({width:p.width,height:p.height,text:p.text}));
  verifySidecarMapping(nested,rendered);
  assert.throws(()=>verifySidecarMapping(nested,rendered.reverse()));
});

test('mapping uses later visible candidates instead of excluded or nonrendered first lines',()=>{
  const source=pages.map((p,i)=>({...p,elements:[{...p.elements[0],text:'Excluded annotation '+i,comparison_role:'excluded' as const},{...p.elements[0],text:'Occluded annotation '+i,visibility:'occluded' as const},{...p.elements[0],text:'Nonrendered first line '+i},{...p.elements[0],text:'Nonrendered second line '+i},...p.elements]}));
  verifySidecarMapping(source,rendered());assert.throws(()=>verifySidecarMapping(source,rendered().reverse()));
});

test('a thousand short uniquely anchored pages map and cancellation interrupts the yielded scan',async()=>{
  const source=Array.from({length:1000},(_,i)=>{const text='Independent reference source '+String(i).padStart(4,'0');return {...pages[0],page:i+1,text,elements:[{...pages[0].elements[0],text}]};});
  const rendered=source.map(p=>({width:p.width,height:p.height,text:p.text}));
  await verifySidecarMappingCancellable(source,rendered);
  const controller=new AbortController(),pending=verifySidecarMappingCancellable(source,rendered,controller.signal);await yieldTurn();controller.abort();await assert.rejects(pending,{name:'AbortError'});
  const swapped=[...rendered];[swapped[239],swapped[999]]=[swapped[999],swapped[239]];assert.throws(()=>verifySidecarMapping(source,swapped));
});

test('dense three-hundred-page source anchors are prepared once with an independent rendered budget',async()=>{
  const source=Array.from({length:300},(_,i)=>{const text=Array.from({length:8},(_,j)=>'Page '+String(i).padStart(4,'0')+' section '+j+' anchor '+('x'.repeat(160))).join('\n');return {...pages[0],page:i+1,text,elements:[{...pages[0].elements[0],text}]};});
  await verifySidecarMappingCancellable(source,source.map(p=>({width:p.width,height:p.height,text:p.text})));
});

test('anchorless source is rejected before a missing provider or a conversion job is opened',async()=>{
  const root=await mkdtemp(join(tmpdir(),'docver-sidecar-preflight-'));try{
    const short=new (PptxGenJS as unknown as typeof PptxGenJS.default)();short.addSlide().addText('Q&A',{x:1,y:1,w:6,h:1});
    const bytes=await short.write({outputType:'nodebuffer'}) as Buffer,asset_id='sha256:'+byteHash(bytes),source=extractPptx(bytes,asset_id),r={...report,revisions:[{...report.revisions[0],assets:[{asset_id,format:'pptx',bytes:bytes.length}],pages:source}]} as ReportData,d={...scope(),page_id:source[0].page_id};
    await mkdir(join(root,'assets'));await writeFile(join(root,'assets',asset_id.slice(7)),bytes);
    await assert.rejects(createOnlyOfficeSidecar({library:root,resources:join(root,'missing-provider'),guard:join(root,'must-not-run'),report:r,scope:d}),(error:unknown)=>!!error&&typeof error==='object'&&'code'in error&&error.code==='SIDECAR_MAPPING'&&String(error).includes('1쪽'));
    assert.deepEqual((await readdir(root)).sort(),['assets']);assert.equal(byteHash(await readFile(join(root,'assets',asset_id.slice(7)))),asset_id.slice(7));
  }finally{await rm(root,{recursive:true,force:true});}
});

test('font metadata accepts data assignments and rejects executable or outside-path payloads',()=>{
  assert.deepEqual(parseOnlyOfficeFonts(metadata()).files,['/System/Library/Fonts/Helvetica.ttc']);
  for(const bytes of [Buffer.concat([metadata(),Buffer.from('process.exit(0);')]),metadata('/private/secret.ttf'),metadata('/System/Library/Fonts/../../secret.ttf'),metadata('/System/Library/Fonts/foo\u0000.ttf'),Buffer.concat([metadata(),Buffer.from('window["constructor"]={};')])])assert.throws(()=>parseOnlyOfficeFonts(bytes));
  assert.throws(()=>parseOnlyOfficeFonts(Buffer.from(metadata().toString().replace('= 2;', '= (()=>2)();'))));
});

async function leaseFixture(){
  const root=await mkdtemp(join(tmpdir(),'docver-sidecar-lease-')),d=scope(),base=join(root,'sidecars-v1'),jobs=join(base,'jobs'),leases=join(base,'leases');
  for(const path of [base,jobs,leases])await mkdir(path,{mode:0o700});
  const folder=join(jobs,d.session_id),pending=join(leases,d.session_id+'.pending.json'),active=join(leases,d.session_id+'.active.json');
  await mkdir(folder,{mode:0o700});await writeFile(join(folder,'temporary.pdf'),'temporary');await writeFile(pending,JSON.stringify({...d,created_at:new Date().toISOString()}),{mode:0o600});
  const canary=join(root,'canonical-canary.json');await writeFile(canary,'canonical input unchanged');
  return {root,d,base,jobs,leases,folder,pending,active,canary};
}

test('cleanup checks session ownership and preserves canonical files',async()=>{
  const f=await leaseFixture();
  try{
    await assert.rejects(closeOnlyOfficeSidecar(f.root,{...f.d,report_id:'rpt_other'}));
    assert.equal(await readFile(join(f.folder,'temporary.pdf'),'utf8'),'temporary');
    await link(f.pending,f.active);await closeOnlyOfficeSidecar(f.root,f.d);
    assert.deepEqual(await readdir(f.jobs),[]);assert.deepEqual(await readdir(f.leases),[]);
    assert.equal(await readFile(f.canary,'utf8'),'canonical input unchanged');
    await assert.rejects(closeOnlyOfficeSidecar(f.root,{...f.d,session_id:'../../outside'}));
  }finally{await rm(f.root,{recursive:true,force:true});}
});

test('cleanup and a racing publication leave no active file or temporary job',async()=>{
  for(let attempt=0;attempt<20;attempt++){
    const f=await leaseFixture();
    try{
      await Promise.allSettled([link(f.pending,f.active),closeOnlyOfficeSidecar(f.root,f.d)]);
      assert.deepEqual(await readdir(f.jobs),[]);assert.deepEqual(await readdir(f.leases),[]);
      await assert.rejects(link(f.pending,f.active),{code:'ENOENT'});
      assert.equal(await readFile(f.canary,'utf8'),'canonical input unchanged');
    }finally{await rm(f.root,{recursive:true,force:true});}
  }
});

test('startup recovery handles a damaged optional lease without deleting unrelated data',async()=>{
  const f=await leaseFixture(),bad=join(f.leases,randomUUID()+'.pending.json');
  try{
    await writeFile(bad,'partial json');await link(f.pending,f.active);
    const result=await recoverOnlyOfficeSidecars(f.root);assert.equal(result.recovered,1);assert.equal(result.skipped,1);
    assert.deepEqual(await readdir(f.jobs),[]);assert.equal(await readFile(bad,'utf8'),'partial json');
    assert.equal(await readFile(f.canary,'utf8'),'canonical input unchanged');
  }finally{await rm(f.root,{recursive:true,force:true});}
});

test('startup recovers a valid closing marker after an interrupted cleanup',async()=>{
  const f=await leaseFixture();try{await link(f.pending,f.active);await rename(f.pending,join(f.leases,f.d.session_id+'.closing.json'));assert.deepEqual(await recoverOnlyOfficeSidecars(f.root),{recovered:1,skipped:0});assert.deepEqual(await readdir(f.jobs),[]);assert.deepEqual(await readdir(f.leases),[]);assert.equal(await readFile(f.canary,'utf8'),'canonical input unchanged');}finally{await rm(f.root,{recursive:true,force:true});}
});

test('startup recovers an owned active-only marker without a pending link',async()=>{
  const f=await leaseFixture();try{await rename(f.pending,f.active);assert.deepEqual(await recoverOnlyOfficeSidecars(f.root),{recovered:1,skipped:0});assert.deepEqual(await readdir(f.jobs),[]);assert.deepEqual(await readdir(f.leases),[]);assert.equal(await readFile(f.canary,'utf8'),'canonical input unchanged');}finally{await rm(f.root,{recursive:true,force:true});}
});

test('startup removes only empty or validated pre-lease jobs and retains unknown nonempty data',async()=>{
  const f=await leaseFixture();try{
    const empty=randomUUID(),seeded=scope(),unknown=randomUUID();
    for(const name of [empty,seeded.session_id,unknown])await mkdir(join(f.jobs,name),{mode:0o700});
    await writeFile(join(f.jobs,seeded.session_id,'.lease-seed'),JSON.stringify({...seeded,created_at:new Date().toISOString()}));await writeFile(join(f.jobs,unknown,'unknown.txt'),'preserve for inspection');
    assert.deepEqual(await recoverOnlyOfficeSidecars(f.root),{recovered:3,skipped:1});assert.deepEqual(await readdir(f.jobs),[unknown]);assert.equal(await readFile(join(f.jobs,unknown,'unknown.txt'),'utf8'),'preserve for inspection');assert.equal(await readFile(f.canary,'utf8'),'canonical input unchanged');
  }finally{await rm(f.root,{recursive:true,force:true});}
});


test('sidecar limits retain the public error code across converter and monitor rejection',()=>{
  for(const code of ['TOOL_FAILED','TOOL_SUPERVISOR'])assert.throws(()=>rethrowSidecarConversionError(new DocverError(code,'DOCVER_RESOURCE_LIMIT: Output symlink refused')),error=>error instanceof DocverError&&error.code==='SIDECAR_LIMIT'&&error.message.includes('원문·변경 이력은 보존됩니다.'));
  for(const original of [new DocverError('CANCELLED','DOCVER_RESOURCE_LIMIT: ignored'),new DocverError('TOOL_SUPERVISOR','Monitor crashed'),new Error('unrelated')])assert.throws(()=>rethrowSidecarConversionError(original),error=>error===original);
});
