import {mkdtemp,mkdir,writeFile,readFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {spawn} from 'node:child_process';
import {randomUUID} from 'node:crypto';
import pptxgen from 'pptxgenjs';
import {unzipSync,zipSync,strToU8} from 'fflate';
import assert from 'node:assert/strict';
import {makePdf} from './generate-fixtures.js';
import {byteHash} from '../packages/schema/index.js';

const output=resolve(process.argv[2]??'output/native-aspect'),userData=await mkdtemp(join(tmpdir(),'docver-aspect-')),fixtures=join(userData,'fixtures');await mkdir(output,{recursive:true});await mkdir(fixtures);
async function source(name:string,width:number,height:number){
 const deck=new (pptxgen as unknown as typeof pptxgen.default)();deck.defineLayout({name:'CUSTOM',width:width/72,height:height/72});deck.layout='CUSTOM';const slide=deck.addSlide();slide.addText(name,{x:.05,y:.1,w:Math.min(1,width/72-.1),h:.2,fontSize:8,margin:0});const parts=unzipSync(await deck.write({outputType:'nodebuffer'}) as Buffer);
 // Harmless unused external relationship forces the documented no-conversion
 // path. Ingest preserves source structure; render safety rejects before I/O.
 parts['unused/_rels/remote.rels']=strToU8('<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="external" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" TargetMode="External" Target="https://example.invalid/not-fetched.png"/></Relationships>');const file=join(fixtures,name+'.pptx');await writeFile(file,zipSync(parts));return file;
}
const thin=await source('Thin source',100,2000),wide=await source('Wide source',2000,100),pdf=join(fixtures,'reference.pdf');await writeFile(pdf,await makePdf([{key:'thin',title:'Thin source',body:'Independent reference page'}]));const files=[thin,wide,pdf],before=await Promise.all(files.map(async p=>byteHash(await readFile(p))));
for(const name of ['failure.json','result.json','process.json'])await rm(join(output,name),{force:true});const nonce=randomUUID(),request=join(output,'request.json');await writeFile(request,JSON.stringify({output,smoke_invocation_id:nonce,bundle_revisions:[{label:'세로 원본',files:[thin,pdf]},{label:'가로 원본',files:[wide]}],aspect_ratio_checks:true}));
const child=spawn(resolve('release/Docver.app/Contents/MacOS/Docver'),[],{cwd:'/',env:{PATH:'/usr/bin:/bin',DOCVER_TEST_USER_DATA:userData,DOCVER_SMOKE_REQUEST:request,DOCVER_SMOKE_OUTPUT:join(output,'failure.json')},stdio:['ignore','pipe','pipe']});let stdout='',stderr='';child.stdout.on('data',d=>stdout+=d);child.stderr.on('data',d=>stderr+=d);const code=await new Promise<number|null>((res,rej)=>{const timer=setTimeout(()=>{child.kill('SIGKILL');rej(Error('Native aspect app timeout'));},90000);child.on('error',rej);child.on('exit',c=>{clearTimeout(timer);res(c);});});await writeFile(join(output,'process.json'),JSON.stringify({code,userData,stdout,stderr},null,2));assert.equal(code,0,stderr);let failure:unknown;try{failure=JSON.parse(await readFile(join(output,'failure.json'),'utf8'));}catch(e){if((e as NodeJS.ErrnoException).code!=='ENOENT')throw e;}assert.equal(failure,undefined,JSON.stringify(failure));const result=JSON.parse(await readFile(join(output,'result.json'),'utf8'));assert.equal(result.smoke_invocation_id,nonce);assert.equal(result.error,'');assert.equal(result.aspect_ratio_checks.length,3);assert.ok(result.aspect_ratio_checks.every((c:{page_ratio_preserved:boolean})=>c.page_ratio_preserved));assert.deepEqual(await Promise.all(files.map(async p=>byteHash(await readFile(p)))),before);console.log(JSON.stringify({output,userData,checks:result.aspect_ratio_checks,scope:'Actual production native canvas bounds/main+bundle sheets; own synthetic fallback sources; not OS input'},null,2));
