import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,mkdir,writeFile,readFile,rm,chmod} from 'node:fs/promises';
import {DatabaseSync} from 'node:sqlite';
import {join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {spawnSync} from 'node:child_process';

test('native reopen validator rejects a fresh zero-exit failure and stale results on reused output',{timeout:20_000},async()=>{
  const root=await mkdtemp(join(tmpdir(),'docver-reopen-validator-')),source=join(root,'source'),original=join(root,'original'),output=join(root,'output'),libraries:string[]=[];
  try {
    await mkdir(source);await mkdir(join(original,'library'),{recursive:true});await mkdir(output);
    const db=new DatabaseSync(join(original,'library','docver.sqlite'));db.exec('CREATE TABLE reports(id TEXT PRIMARY KEY,body TEXT NOT NULL)');db.prepare('INSERT INTO reports VALUES (?,?)').run('rpt_control','{}');db.close();
    const fixture={project_id:'proj_control',report_id:'rpt_control',pages:[300,300],numeric_changes:[{}]};
    await writeFile(join(source,'result.json'),JSON.stringify(fixture));await writeFile(join(source,'process.json'),JSON.stringify({userData:original}));
    const app=join(root,'release/Reviset.app/Contents/MacOS/Reviset');await mkdir(join(root,'release/Reviset.app/Contents/MacOS'),{recursive:true});
    await writeFile(app,`#!${process.execPath}
const fs=require('node:fs'),path=require('node:path');const req=JSON.parse(fs.readFileSync(process.env.DOCVER_SMOKE_REQUEST,'utf8'));
if(process.env.DOCVER_VALIDATOR_MOCK==='failure'){fs.writeFileSync(process.env.DOCVER_SMOKE_OUTPUT,JSON.stringify({error:'CONTROLLED_NEW_RENDER_FAILURE'}));process.exit(0)}
fs.writeFileSync(path.join(req.output,'result.json'),JSON.stringify({error:'',report_id:req.existing_report_id,pages:[300,300],numeric_changes:[{}],layout_checks:{native_divider_and_height_reopen:true},smoke_invocation_id:process.env.DOCVER_VALIDATOR_MOCK==='stale_nonce'?'old_nonce':req.smoke_invocation_id}));
`);await chmod(app,0o700);
    const run=async(mode:string)=>{
      const result=spawnSync(process.execPath,[resolve('scripts/native-view-reopen.mjs'),source,output],{cwd:root,env:{...process.env,DOCVER_VALIDATOR_MOCK:mode},encoding:'utf8',timeout:10_000});
      try{libraries.push(JSON.parse(await readFile(join(output,'process.json'),'utf8')).userData);}catch{/* failed before child launch */}
      return result;
    };
    await writeFile(join(output,'failure.json'),JSON.stringify({error:'OLD_FAILURE_MUST_BE_CLEARED'}));
    const success=await run('success');assert.equal(success.status,0,success.stderr);assert.match(success.stdout,/report_bodies_unchanged/);
    const failed=await run('failure');assert.notEqual(failed.status,0);assert.match(failed.stderr,/CONTROLLED_NEW_RENDER_FAILURE/);assert.doesNotMatch(failed.stdout,/report_bodies_unchanged/);
    await assert.rejects(readFile(join(output,'result.json')),{code:'ENOENT'});await assert.rejects(readFile(join(output,'immutable-reopen.json')),{code:'ENOENT'});
    const stale=await run('stale_nonce');assert.notEqual(stale.status,0);assert.match(stale.stderr,/different native invocation/);
    const recovered=await run('success');assert.equal(recovered.status,0,recovered.stderr);
  }finally{for(const library of new Set(libraries))await rm(library,{recursive:true,force:true});await rm(root,{recursive:true,force:true});}
});
