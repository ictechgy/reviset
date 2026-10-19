import {mkdtemp,mkdir,writeFile,readFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {resolve,join} from 'node:path';
import {spawn} from 'node:child_process';
import assert from 'node:assert/strict';
import {makePptx} from './generate-fixtures.js';

// Synthetic ground truth is authored here, independent of matching output.
// Exercises real packaged app/model/native sheet, not OS mouse/keyboard input.
const output=resolve('output/native-relations'),userData=await mkdtemp(join(tmpdir(),'docver-native-relations-')),fixtures=join(userData,'fixtures');
await mkdir(output,{recursive:true});await mkdir(fixtures);
for(const f of ['result.json','failure.json','process.json'])await rm(join(output,f),{force:true});
const slide=(key:string,body:string)=>({key,title:key,body}),versions=[[slide('통합 전략','설계 구현 검토'),slide('매출 전망','예상 매출 100억')],[slide('설계 전략','설계 검토'),slide('구현 전략','구현 검토'),slide('매출 전망','예상 매출 100억')],[slide('통합 전략','설계 구현 검토'),slide('매출 전망','예상 매출 120억')]];
const files=[];
for(const [i,slides] of versions.entries()){const file=join(fixtures,`v${i+1}.pptx`);await writeFile(file,await makePptx(slides));files.push(file);}
const request=join(output,'request.json');await writeFile(request,JSON.stringify({output,files,manual_relations:true}));
const child=spawn(resolve('release/Docver.app/Contents/MacOS/Docver'),[],{cwd:'/',env:{...process.env,DOCVER_TEST_USER_DATA:userData,DOCVER_SMOKE_REQUEST:request,DOCVER_SMOKE_OUTPUT:join(output,'failure.json')},stdio:['ignore','pipe','pipe']});
let stdout='',stderr='';child.stdout.on('data',d=>stdout+=d);child.stderr.on('data',d=>stderr+=d);
const code=await new Promise<number|null>((res,rej)=>{const timer=setTimeout(()=>{child.kill('SIGKILL');rej(Error('Native relations app timeout'));},300000);child.on('error',rej);child.on('exit',c=>{clearTimeout(timer);res(c);});});
await writeFile(join(output,'process.json'),JSON.stringify({code,userData,stdout,stderr},null,2));assert.equal(code,0,stderr);
let failure:string|undefined;try{failure=JSON.parse(await readFile(join(output,'failure.json'),'utf8')).error;}catch(e){if((e as NodeJS.ErrnoException).code!=='ENOENT')throw e;}assert.equal(failure,undefined,failure ?? "Native relations validation failed");
const result=JSON.parse(await readFile(join(output,'result.json'),'utf8'));assert.equal(result.error,'');assert.deepEqual(result.pages,[2,3,2]);assert.equal(result.numeric_changes.length,1);assert.equal(result.manual_relation_checks.length,5);
console.log(JSON.stringify({output,userData,pages:result.pages,checks:result.manual_relation_checks,seconds:result.analysis_and_ui_seconds,report_id:result.report_id},null,2));
