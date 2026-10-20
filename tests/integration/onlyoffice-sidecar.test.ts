import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,mkdir,writeFile,readFile,readdir,link,rm} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {randomUUID} from 'node:crypto';
import PptxGenJS from 'pptxgenjs';
import {extractPptx} from '../../packages/ingest/pptx.js';
import {byteHash,hash,type ReportData} from '../../packages/schema/index.js';
import {parseOnlyOfficeFonts} from '../../packages/render/onlyoffice-fonts.js';
import {SidecarScope,sidecarSource,verifySidecarMapping,closeOnlyOfficeSidecar,recoverOnlyOfficeSidecars} from '../../packages/render/onlyoffice-sidecar.js';

const deck=new (PptxGenJS as unknown as typeof PptxGenJS.default)();
for(const text of ['Alpha roadmap ownership','Beta review schedule'])deck.addSlide().addText(text,{x:1,y:1,w:6,h:1});
const bytes=await deck.write({outputType:'nodebuffer'}) as Buffer,asset_id='sha256:'+byteHash(bytes),pages=extractPptx(bytes,asset_id);
// The selector consumes only these fields; real PageData comes from extraction.
const report={project_id:'prj_sidecar',report_id:'rpt_sidecar',revisions:[{revision_occurrence_id:'occ_a',assets:[{asset_id,format:'pptx',bytes:bytes.length}],pages}]} as ReportData;
const scope=()=>SidecarScope.parse({project_id:report.project_id,report_id:report.report_id,revision_occurrence_id:'occ_a',page_id:pages[0].page_id,session_id:randomUUID()});
const rendered=()=>pages.map(p=>({width:p.width,height:p.height,text:p.text}));
const metadata=(file='/System/Library/Fonts/Helvetica.ttc')=>Buffer.from(Object.entries({__all_fonts_js_version__:2,__fonts_files:[file],__fonts_infos:[['Helvetica',0,0,-1,-1,-1,-1,-1,-1]],__fonts_ranges:[0,127,0],g_fonts_selection_bin:'AA=='}).map(([k,v])=>`window["${k}"] = ${JSON.stringify(v)};`).join('\n'));

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
