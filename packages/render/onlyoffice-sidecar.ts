import {z} from 'zod';
import {readFile,writeFile,mkdir,realpath,lstat,rename,rm,link,readdir} from 'node:fs/promises';
import {join} from 'node:path';
import {getDocument} from 'pdfjs-dist/legacy/build/pdf.mjs';
import {byteHash,MAX_INPUT_BYTES,DocverError,type PageData,type ReportData} from '../schema/index.js';
import {runTool,visionInfo} from '../runtime/tools.js';
import {extractPptx} from '../ingest/pptx.js';
import {pdfOptions} from '../ingest/pdf.js';
import {validateRenderPackage} from './index.js';
import {namedSourceFonts} from './pptx-preview.js';
import {unzipSync} from 'fflate';
import {parseOnlyOfficeFonts,onlyOfficeFontRoots} from './onlyoffice-fonts.js';
import {setImmediate as yieldTurn} from 'node:timers/promises';

const sha=z.string().regex(/^[a-f0-9]{64}$/u),key=z.string().regex(/^[a-zA-Z0-9_-]{1,160}$/u);
export const SidecarScope=z.object({project_id:key,report_id:key,revision_occurrence_id:key,page_id:key,session_id:z.string().regex(/^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/u)}).strict();
export type SidecarScopeData=z.infer<typeof SidecarScope>;
const FileIdentity=z.object({sha256:sha,bytes:z.number().int().positive().max(1024*1024)}).strict();
const Provider=z.object({version:z.literal(1),app_path:z.string().min(1).max(4096),bundle_version:z.string().min(1).max(80),release_version:z.string().min(1).max(80),team_id:z.literal('2WH24U26GJ'),converter_sha256:sha,code_resources_sha256:sha,font_inventory_sha256:sha,files:z.object({'AllFonts.js':FileIdentity,'font_selection.bin':FileIdentity}).strict()}).strict();
const Lease=SidecarScope.extend({created_at:z.string().datetime()}).strict();
const requirement='=anchor apple generic and certificate leaf[subject.OU] = "2WH24U26GJ"';
function fail(code:string,message:string):never{throw new DocverError(code,message);}
const compact=(text:string)=>text.normalize('NFC').replace(/\s/gu,'');
const xml=(value:string)=>value.replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;').replaceAll("'",'&apos;');

async function privateDirectory(path:string,create:boolean):Promise<string|undefined>{
  try{if(create)await mkdir(path,{recursive:true,mode:0o700});const st=await lstat(path);
    if(!st.isDirectory()||st.isSymbolicLink()||st.uid!==process.getuid?.()||(st.mode&0o077)!==0)fail('SIDECAR_DIRECTORY','참고 미리보기의 전용 폴더를 확인할 수 없습니다.');
    return await realpath(path);
  }catch(e){if(!create&&(e as NodeJS.ErrnoException).code==='ENOENT')return;throw e;}
}
async function directories(library:string,create:boolean){
  const root=await privateDirectory(join(library,'sidecars-v1'),create);if(!root)return;
  const jobs=await privateDirectory(join(root,'jobs'),create),leases=await privateDirectory(join(root,'leases'),create);
  return jobs&&leases?{jobs,leases}:undefined;
}
async function smallFile(path:string,maximum:number){const st=await lstat(path);if(!st.isFile()||st.isSymbolicLink()||st.size>maximum)fail('SIDECAR_RESOURCE','참고 렌더러 리소스를 확인할 수 없습니다.');const bytes=await readFile(path);if(bytes.length>maximum)fail('SIDECAR_RESOURCE','참고 렌더러 리소스 한도를 넘었습니다.');return bytes;}

export async function onlyOfficeSidecarConfigured(resources:string):Promise<boolean>{
  try{const config=Provider.parse(JSON.parse((await smallFile(join(resources,'provider.json'),65536)).toString('utf8')));await realpath(config.app_path);return true;}catch{return false;}
}

async function provider(resources:string,signal?:AbortSignal){
  signal?.throwIfAborted();
  let config:z.infer<typeof Provider>;
  try{config=Provider.parse(JSON.parse((await smallFile(join(resources,'provider.json'),65536)).toString('utf8')));}
  catch{fail('SIDECAR_UNAVAILABLE','이 Mac의 참고 렌더러가 준비되지 않았습니다. 기본 원문 화면은 계속 사용할 수 있습니다.');}
  let app:string,converter:string;
  try{app=await realpath(config.app_path);converter=await realpath(join(app,'Contents/Resources/converter/x2t'));}
  catch{fail('SIDECAR_PROVIDER_CHANGED','참고 렌더러의 실행 파일을 찾을 수 없습니다. 이 Mac에서 렌더러를 다시 준비하세요.');}
  if(!converter.startsWith(app+'/'))fail('SIDECAR_PROVIDER_CHANGED','참고 렌더러 실행 경로를 확인할 수 없습니다.');
  if(byteHash(await smallFile(converter,128*1024*1024))!==config.converter_sha256||byteHash(await smallFile(join(app,'Contents/_CodeSignature/CodeResources'),4*1024*1024))!==config.code_resources_sha256)fail('SIDECAR_PROVIDER_CHANGED','참고 렌더러가 변경되었습니다. 다시 준비한 빌드가 필요합니다.');
  await runTool('/usr/bin/codesign',['--verify','--deep','--strict','-R',requirement,app],{timeout:30_000,signal,maxBytes:65536,inheritEnv:false,env:{PATH:'/usr/bin:/bin'}});
  for(const [name,expected]of [['CFBundleVersion',config.bundle_version],['CFBundleShortVersionString',config.release_version]]){
    const actual=(await runTool('/usr/bin/plutil',['-extract',name,'raw',join(app,'Contents/Info.plist')],{timeout:5000,signal,maxBytes:1024,inheritEnv:false,env:{PATH:'/usr/bin:/bin'}})).trim();
    if(actual!==expected)fail('SIDECAR_PROVIDER_CHANGED','참고 렌더러의 버전이 변경되었습니다.');
  }
  const info=await visionInfo(signal);signal?.throwIfAborted();
  if(!info)fail('SIDECAR_UNAVAILABLE','이 Mac의 참고 렌더링 글꼴 정보를 확인할 수 없습니다.');
  if(info.font_inventory_sha256!==config.font_inventory_sha256)fail('SIDECAR_FONTS_CHANGED','이 Mac의 글꼴 구성이 바뀌어 참고 렌더러를 다시 준비해야 합니다.');
  const fonts:Record<string,Buffer>={};
  for(const name of ['AllFonts.js','font_selection.bin'] as const){const bytes=await smallFile(join(resources,'fonts',name),1024*1024);if(bytes.length!==config.files[name].bytes||byteHash(bytes)!==config.files[name].sha256)fail('SIDECAR_FONTS','참고 글꼴 정보의 검증에 실패했습니다.');fonts[name]=bytes;}
  parseOnlyOfficeFonts(fonts['AllFonts.js']);
  return {app,converter,config,fonts,info};
}

export function onlyOfficeSidecarPolicy(folder:string,app:string,converter:string){
  const reads=['/System','/usr/lib','/usr/share','/private/etc','/private/var/db',...onlyOfficeFontRoots(),app,folder,'/dev'];
  return `(version 1)(allow default)(deny network*)(deny mach-lookup)(deny mach-register)(deny user-preference-write)(deny lsopen)(deny signal)(deny ipc-posix*)(deny ipc-sysv*)(deny iokit*)(deny process-fork)(deny process-exec)(allow process-exec (literal ${JSON.stringify(converter)}))(deny file-read-data)(allow file-read-data (vnode-type DIRECTORY) ${reads.map(p=>`(subpath ${JSON.stringify(p)})`).join(' ')})(deny file-write*)(allow file-write* (subpath ${JSON.stringify(folder)}) (literal "/dev/null"))(deny file-write* (subpath ${JSON.stringify(app)}))`;
}

export function sidecarSource(report:ReportData,scope:SidecarScopeData){
  scope=SidecarScope.parse(scope);
  if(scope.report_id==='latest'||report.report_id!==scope.report_id||report.project_id!==scope.project_id)fail('SIDECAR_SCOPE','고정된 보고서의 원문을 선택하세요.');
  const revisions=report.revisions.filter(v=>v.revision_occurrence_id===scope.revision_occurrence_id);
  if(revisions.length!==1)fail('SIDECAR_SCOPE','원문 버전을 하나로 확인할 수 없습니다.');
  const revision=revisions[0],matches=revision.pages.filter(p=>p.page_id===scope.page_id);
  if(matches.length!==1)fail('SIDECAR_MAPPING','원문 페이지를 하나로 확인할 수 없습니다.');
  const page=matches[0],assets=revision.assets.filter(a=>a.asset_id===page.asset_id&&a.format==='pptx');
  if(assets.length!==1)fail('SIDECAR_SCOPE','PPTX 원문 페이지에서 참고 미리보기를 열 수 있습니다.');
  if(!/^sha256:[a-f0-9]{64}$/u.test(assets[0].asset_id))fail('ASSET_ID','참고 화면의 원본 ID를 확인할 수 없습니다.');
  return {page,asset:assets[0],pages:revision.pages.filter(p=>p.asset_id===page.asset_id)};
}

type RenderedPage={width:number;height:number;text:string};
type MappingPlan={geometry:{width:number;height:number}[];anchors:string[][]};
function mappingContains(){let comparisons=0,inspected=0;return (text:string,line:string)=>{if(++comparisons>8_000_000||(inspected+=text.length+line.length)>2_000_000_000)fail('SIDECAR_LIMIT','고유 문구의 대응 검사 한도를 넘었습니다.');return text.includes(line);};}
function* prepareSidecarMapping(source:PageData[]):Generator<void,MappingPlan>{
  if(!source.length||source.length>2000||source.some((p,i)=>p.page!==i+1||p.hidden!==false||![p.width,p.height].every(n=>Number.isFinite(n)&&n>0)))fail('SIDECAR_MAPPING','숨김·누락·모호한 페이지가 있는 원문은 별도 미리보기로 연결하지 않습니다.');
  if(source.reduce((n,p)=>n+p.elements.reduce((m,e)=>m+e.text.length,0),0)>20_000_000)fail('SIDECAR_LIMIT','참고 화면의 원문 검사 한도를 넘었습니다.');
  const lines=source.map(p=>[...new Set(p.elements.filter(e=>e.comparison_role!=='excluded'&&e.comparison_role!=='shadowed'&&!['occluded','hidden_render_mode'].includes(e.visibility??'')).flatMap(e=>e.text.split(/\r\n|\r|\n/u)).map(compact).filter(s=>s.length>=6&&s.length<=512&&/\p{L}/u.test(s)))].slice(0,64));
  const counts=new Map<string,number>();for(const page of lines)for(const line of page)counts.set(line,(counts.get(line)??0)+1);
  const sourceText=source.map(p=>compact(p.elements.map(e=>e.text).join(' ')));
  if(sourceText.reduce((n,s)=>n+s.length,0)>20_000_000)fail('SIDECAR_LIMIT','참고 화면의 원문 검사 한도를 넘었습니다.');
  const contains=mappingContains();
  // Exact line uniqueness is insufficient: a short heading can legitimately be
  // contained in another page's longer heading. Only source-global anchors vote.
  const anchors:string[][]=[];
  for(let i=0;i<lines.length;i++){const found:string[]=[];for(const line of lines[i]){
    if(counts.get(line)===1&&!sourceText.some((other,j)=>j!==i&&contains(other,line)))found.push(line);
    if(found.length===8)break;
  }if(!found.length)fail('SIDECAR_MAPPING',`${i+1}쪽에서 고유한 원문 문구를 확인할 수 없어 별도 미리보기로 연결하지 않습니다.`);anchors.push(found);yield;}
  return {geometry:source.map(({width,height})=>({width,height})),anchors};
}
function* verifyRenderedMapping(plan:MappingPlan,rendered:RenderedPage[]):Generator<void>{
  const {geometry,anchors}=plan,contains=mappingContains();
  if(rendered.length!==geometry.length)fail('SIDECAR_MAPPING','변환된 페이지 수가 원문과 다릅니다.');
  if(rendered.reduce((n,p)=>n+p.text.length,0)>20_000_000)fail('SIDECAR_LIMIT','참고 화면의 텍스트 검사 한도를 넘었습니다.');
  for(let i=0;i<geometry.length;i++){
    const a=geometry[i],b=rendered[i];
    if(![a.width,a.height,b.width,b.height].every(n=>Number.isFinite(n)&&n>0)||Math.abs((a.width/a.height)/(b.width/b.height)-1)>.001)fail('SIDECAR_MAPPING','변환된 페이지 크기가 원문과 다릅니다.');
    const text=compact(b.text);
    if(!anchors[i].length||!anchors[i].some(line=>contains(text,line)))fail('SIDECAR_MAPPING','페이지 대응을 확인할 고유한 원문을 찾지 못했습니다.');
    if(anchors.some((other,j)=>j!==i&&other.some(line=>contains(text,line))))fail('SIDECAR_MAPPING','다른 페이지의 고유 원문이 겹쳐 참고 화면을 연결하지 않습니다.');
    yield;
  }
}

function finishMappingChecks<T>(checks:Generator<void,T>):T{for(;;){const step=checks.next();if(step.done)return step.value;}}
export function verifySidecarMapping(source:PageData[],rendered:RenderedPage[]):void{finishMappingChecks(verifyRenderedMapping(finishMappingChecks(prepareSidecarMapping(source)),rendered));}
async function runMappingChecks<T>(checks:Generator<void,T>,signal?:AbortSignal):Promise<T>{
  signal?.throwIfAborted();
  for(;;){signal?.throwIfAborted();const step=checks.next();if(step.done)return step.value;await yieldTurn();signal?.throwIfAborted();}
}
export async function verifySidecarMappingCancellable(source:PageData[],rendered:RenderedPage[],signal?:AbortSignal):Promise<void>{const plan=await runMappingChecks(prepareSidecarMapping(source),signal);await runMappingChecks(verifyRenderedMapping(plan,rendered),signal);}

export async function closeOnlyOfficeSidecar(library:string,scope:SidecarScopeData):Promise<void>{
  scope=SidecarScope.parse(scope);
  const paths=await directories(library,false);if(!paths)return;
  const pending=join(paths.leases,scope.session_id+'.pending.json'),tombstone=join(paths.leases,scope.session_id+'.closing.json');
  let owner:z.infer<typeof Lease>;
  try{owner=Lease.parse(JSON.parse((await smallFile(pending,8192)).toString('utf8')));}catch(e){if((e as NodeJS.ErrnoException).code==='ENOENT')return;throw e;}
  if(Object.entries(scope).some(([key,value])=>owner[key as keyof SidecarScopeData]!==value))fail('SIDECAR_SCOPE','이 미리보기 작업의 정리 권한을 확인할 수 없습니다.');
  try{await rename(pending,tombstone);}catch(e){if((e as NodeJS.ErrnoException).code==='ENOENT')return;throw e;}
  // Publication links the pending marker. Once renamed, an in-flight create
  // cannot publish a new active marker after this cleanup has completed.
  await rm(join(paths.leases,scope.session_id+'.active.json'),{force:true});
  await rm(join(paths.jobs,scope.session_id),{recursive:true,force:true});
  await rm(tombstone,{force:true});
}

export async function recoverOnlyOfficeSidecars(library:string):Promise<{recovered:number;skipped:number}>{
  const paths=await directories(library,false);let recovered=0,skipped=0;if(!paths)return {recovered,skipped};
  for(const name of await readdir(paths.leases)){
    if(!/^[a-f0-9-]{36}\.(?:pending|closing|active)\.json$/u.test(name))continue;
    try{
      const owner=Lease.parse(JSON.parse((await smallFile(join(paths.leases,name),8192)).toString('utf8')));
      if(!['pending','closing','active'].some(state=>name===owner.session_id+'.'+state+'.json')){skipped++;continue;}
      if(name.endsWith('.active.json')){
        let linked=false;for(const state of ['pending','closing'])try{await lstat(join(paths.leases,owner.session_id+'.'+state+'.json'));linked=true;}catch(error){if((error as NodeJS.ErrnoException).code!=='ENOENT')throw error;}
        if(linked)continue;
      }
      if(name.endsWith('.pending.json')){const {created_at,...scope}=owner;void created_at;await closeOnlyOfficeSidecar(library,SidecarScope.parse(scope));}
      else {await rm(join(paths.leases,owner.session_id+'.active.json'),{force:true});await rm(join(paths.jobs,owner.session_id),{recursive:true,force:true});await rm(join(paths.leases,name),{force:true});}
      recovered++;
    }catch(error){if((error as NodeJS.ErrnoException).code!=='ENOENT')skipped++;} // A damaged optional lease must not prevent opening reports.
  }
  // Startup holds the native library's exclusive app lock. Recover only empty
  // pre-lease directories or the validated seed written before any input copy.
  // Unknown nonempty jobs and malformed leases remain available for inspection.
  for(const name of await readdir(paths.jobs)){
    if(!/^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/u.test(name))continue;
    try{
      let leased=false;
      for(const state of ['pending','active','closing'])try{await lstat(join(paths.leases,name+'.'+state+'.json'));leased=true;}catch(error){if((error as NodeJS.ErrnoException).code!=='ENOENT')throw error;}
      if(leased)continue;
      const folder=(await privateDirectory(join(paths.jobs,name),false))!;const entries=await readdir(folder);
      if(entries.length){
        if(entries.length!==1||entries[0]!=='.lease-seed'){skipped++;continue;}
        const owner=Lease.parse(JSON.parse((await smallFile(join(folder,'.lease-seed'),8192)).toString('utf8')));
        if(owner.session_id!==name){skipped++;continue;}
      }
      await rm(folder,{recursive:true});recovered++;
    }catch{skipped++;}
  }
  return {recovered,skipped};
}

export async function createOnlyOfficeSidecar(options:{library:string;resources:string;guard:string;report:ReportData;scope:SidecarScopeData;signal?:AbortSignal}){
  const {library,resources,guard,report,signal}=options,scope=SidecarScope.parse(options.scope),selected=sidecarSource(report,scope);
  signal?.throwIfAborted();let source:Buffer;
  try{source=await smallFile(join(library,'assets',selected.asset.asset_id.slice(7)),MAX_INPUT_BYTES);}
  catch{fail('ASSET_CORRUPT','참고 화면에 사용할 저장 원본이 없거나 읽을 수 없습니다. 원본을 다시 가져와 확인하세요.');}
  if(byteHash(source)!==selected.asset.asset_id.slice(7))fail('ASSET_CORRUPT','참고 화면에 사용할 원본의 hash가 다릅니다.');
  validateRenderPackage(source);const pages=extractPptx(source,selected.asset.asset_id);
  if(pages.reduce((n,p)=>n+p.elements.reduce((m,e)=>m+e.text.length,0),0)>20_000_000)fail('SIDECAR_LIMIT','참고 화면의 원문 검사 한도를 넘었습니다.');
  if(!pages.length||pages.length>2000||pages.length!==selected.pages.length||selected.pages.some((p,i)=>p.page!==pages[i]?.page||p.hidden!==pages[i]?.hidden||p.width!==pages[i]?.width||p.height!==pages[i]?.height)||pages.some(p=>p.hidden!==false))fail('SIDECAR_MAPPING','현재 원문과 저장된 페이지 대응을 확인할 수 없습니다.');
  // Reject source-only ambiguity before signature checks, metadata preparation,
  // copying or converting a whole deck. The rendered correspondence is still
  // checked independently after conversion, with the same bounded policy.
  const mapping=await runMappingChecks(prepareSidecarMapping(pages),signal);
  const prepared=await provider(resources,signal);
  signal?.throwIfAborted();const paths=(await directories(library,true))!,folder=join(paths.jobs,scope.session_id),pending=join(paths.leases,scope.session_id+'.pending.json');
  let ownsFolder=false,ownsLease=false,published=false;
  try{
    await mkdir(folder,{mode:0o700});ownsFolder=true;
    const seed=join(folder,'.lease-seed');
    await writeFile(seed,JSON.stringify({...scope,created_at:new Date().toISOString()}),{flag:'wx',mode:0o600});
    await link(seed,pending);ownsLease=true;await rm(seed);
    const copied=join(folder,'input.pptx'),output=join(folder,'converted.pdf'),fonts=join(folder,'fonts');await mkdir(fonts,{mode:0o700});await writeFile(copied,source,{flag:'wx',mode:0o600});
    for(const [name,bytes]of Object.entries(prepared.fonts))await writeFile(join(fonts,name),bytes,{flag:'wx',mode:0o600});
    const params={m_sFileFrom:copied,m_sFileTo:output,m_nFormatTo:'513',m_sFontDir:fonts,m_sAllFontsPath:join(fonts,'AllFonts.js'),m_sThemeDir:join(prepared.app,'Contents/Resources/editors/sdkjs/slide/themes'),m_bIsNoBase64:'true',m_sTempDir:folder};
    const parameterFile=join(folder,'params.xml');await writeFile(parameterFile,'<?xml version="1.0" encoding="utf-8"?><TaskQueueDataConvert>'+Object.entries(params).map(([k,v])=>`<${k}>${xml(v)}</${k}>`).join('')+'</TaskQueueDataConvert>',{mode:0o600,flag:'wx'});
    signal?.throwIfAborted();
    try{await runTool(guard,[folder,'/usr/bin/sandbox-exec','-p',onlyOfficeSidecarPolicy(folder,prepared.app,prepared.converter),prepared.converter,parameterFile],{timeout:120_000,signal,maxBytes:1024*1024,inheritEnv:false,env:{PATH:'/usr/bin:/bin',HOME:folder,TMPDIR:folder,XDG_CACHE_HOME:join(folder,'cache'),LANG:'en_US.UTF-8',TZ:'UTC'}});}
    catch(error){if(error instanceof DocverError&&error.code==='TOOL_FAILED'&&error.message.includes('DOCVER_RESOURCE_LIMIT:'))fail('SIDECAR_LIMIT','참고 변환 작업의 파일·폴더 용량 또는 구조 제한을 넘었습니다. 원문·변경 이력은 보존됩니다.');throw error;}
    signal?.throwIfAborted();const st=await lstat(output);if(st.nlink!==1)fail('SIDECAR_OUTPUT','참고 PDF가 독립된 파일이 아닙니다.');const pdf=await smallFile(output,128*1024*1024);
    const task=getDocument({...pdfOptions,data:new Uint8Array(pdf)}),rendered:RenderedPage[]=[];let documentCharacters=0,documentItems=0;
    let abortedDestroy:Promise<void>|undefined;
    const abortPdf=()=>{abortedDestroy=task.destroy().catch(()=>{});};signal?.addEventListener('abort',abortPdf,{once:true});if(signal?.aborted)abortPdf();
    try{const doc=await task.promise;if(doc.numPages!==pages.length)fail('SIDECAR_MAPPING','변환된 페이지 수가 원문과 다릅니다.');
      for(let page=1;page<=doc.numPages;page++){
        signal?.throwIfAborted();const p=await doc.getPage(page),v=p.getViewport({scale:1}),reader=p.streamTextContent({disableNormalization:true}).getReader(),fragments:string[]=[];let characters=0,items=0;
        try{for(;;){signal?.throwIfAborted();const {done,value}=await reader.read();if(done)break;
          for(const item of value.items){if(!('str'in item))continue;characters+=item.str.length;documentCharacters+=item.str.length;items++;documentItems++;if(characters>1_000_000||items>100000||documentCharacters>20_000_000||documentItems>1_000_000)fail('SIDECAR_LIMIT','참고 페이지의 텍스트 검사 한도를 넘었습니다.');fragments.push(item.str);}
        }}finally{await reader.cancel().catch(()=>{});reader.releaseLock();}
        rendered.push({width:v.width,height:v.height,text:fragments.join(' ')});p.cleanup();
      }
    }finally{signal?.removeEventListener('abort',abortPdf);await(abortedDestroy??task.destroy());}
    await runMappingChecks(verifyRenderedMapping(mapping,rendered),signal);signal?.throwIfAborted();
    const parts=unzipSync(source,{filter:e=>/^ppt\/(slides|slideLayouts|slideMasters|theme)\/[^/]+\.xml$/u.test(e.name)}),known=new Set(prepared.info.font_families.map((s:string)=>s.toLowerCase())),missing=namedSourceFonts(Object.values(parts)).filter(f=>!known.has(f.toLowerCase()));
    await link(pending,join(paths.leases,scope.session_id+'.active.json'));published=true;
    return {...scope,path:output,page:selected.page.page,pages:pages.length,renderer:'ONLYOFFICE Desktop Editors',version:prepared.config.release_version,assessment:'inferred' as const,mapping:'unique_source_text_anchors_v1',source_sha256:byteHash(source),pdf_sha256:byteHash(pdf),converter_sha256:prepared.config.converter_sha256,font_inventory_sha256:prepared.config.font_inventory_sha256,omitted_font_warnings:Math.max(0,missing.length-20),warnings:['참고용 변환 화면입니다. 변경 이력과 AI 조회 결과에는 반영하지 않습니다.','PowerPoint와 픽셀 일치를 보장하지 않습니다. 그림자·글꼴·복합 개체를 원본과 대조하세요.',...missing.slice(0,20).map(f=>'대체될 수 있는 글꼴: '+(f.length>200?f.slice(0,200)+'…':f))]};
  }finally{
    if(!published){if(ownsFolder)await rm(folder,{recursive:true,force:true});if(ownsLease)await closeOnlyOfficeSidecar(library,scope);}
  }
}
