import { mkdtemp,mkdir,writeFile,readFile,rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { resolve,join } from 'node:path';
import { spawn } from 'node:child_process';
import assert from 'node:assert/strict';
const scale=process.argv.includes('--scale'),scanScale=process.argv.includes('--scan-scale'),folder=resolve(scanScale?'output/native-scan-scale':scale?'output/native-scale':'output/native-smoke');await mkdir(folder,{recursive:true});
for(const name of ['result.json','failure.json','process.json'])await rm(join(folder,name),{force:true});
const userData=await mkdtemp(join(tmpdir(),'docver-native-')),request=join(folder,'request.json');
await writeFile(request,JSON.stringify({output:folder,layout_checks:true,files:scanScale?['v1.pdf','v2.pdf'].map(f=>resolve('artifacts/scan-scale-fixture',f)):scale?['v1.pptx','v2.pdf','v3.pptx'].map(f=>resolve('artifacts/scale-fixture',f)):[]}));
const child=spawn(resolve('release/Docver.app/Contents/MacOS/Docver'),[],{cwd:'/',env:{...process.env,DOCVER_TEST_USER_DATA:userData,DOCVER_SMOKE_REQUEST:request,DOCVER_SMOKE_OUTPUT:join(folder,'failure.json')},stdio:['ignore','pipe','pipe']});
let stdout='',stderr='';child.stdout.on('data',d=>stdout+=d);child.stderr.on('data',d=>stderr+=d);
const code=await new Promise((res,rej)=>{const timer=setTimeout(()=>{child.kill('SIGKILL');rej(new Error('Native app smoke timeout'));},scanScale?1200000:300000);child.on('error',rej);child.on('exit',c=>{clearTimeout(timer);res(c);});});
await writeFile(join(folder,'process.json'),JSON.stringify({code,userData,stdout,stderr},null,2));assert.equal(code,0,stderr);
const result=JSON.parse(await readFile(join(folder,'result.json'),'utf8'));assert.equal(result.error,'');assert.equal(result.native_ui,'SwiftUI/AppKit/PDFKit');assert.equal(result.numeric_changes.length,scanScale?1:2);
if(scale)assert.deepEqual(result.pages,[300,300,300]);
if(scanScale){assert.deepEqual(result.pages,[300,300]);assert.equal(result.numeric_changes[0].text_assessment,'inferred');assert.ok(result.numeric_changes[0].before.includes('100억'));assert.ok(result.numeric_changes[0].after.includes('120억'));}
console.log(JSON.stringify({folder,userData,pages:result.pages,numeric_changes:result.numeric_changes.length,seconds:result.analysis_and_ui_seconds,report_id:result.report_id,stderr},null,2));
