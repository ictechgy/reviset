import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';

test('actual native evidence-button action resolves supplied PDF IDs to primary slides and preserves navigation pins',async()=>{
 const root=await mkdtemp(join(tmpdir(),'docver-evidence-action-'));try{
  const executable=join(root,'probe'),build=spawnSync('swiftc',['-warnings-as-errors','-swift-version','5','-parse-as-library','-target','arm64-apple-macos14.0','apps/macos/Bridge.swift','apps/macos/Model.swift','tests/native/EvidenceNavigation.swift','-o',executable,'-framework','SwiftUI','-framework','AppKit'],{encoding:'utf8',timeout:30000});assert.equal(build.status,0,build.stderr);assert.ifError(build.error);
  const run=spawnSync(executable,[],{cwd:'/',encoding:'utf8',timeout:15000,env:{PATH:'/usr/bin:/bin',DOCVER_TEST_USER_DATA:join(root,'userdata')}});assert.equal(run.status,0,run.stderr);assert.ifError(run.error);assert.match(run.stdout,/PASS actual AppModel evidence button mapping/);
 }finally{await rm(root,{recursive:true,force:true});}
});
