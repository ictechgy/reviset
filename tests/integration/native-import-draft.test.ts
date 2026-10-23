import {nativeLocalizationTestSources,prepareLegacyNativeLocalization} from '../../scripts/native-swift-sources.js';
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,rm,writeFile,readFile,stat,utimes,readdir} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {spawnSync} from 'node:child_process';
import {DesktopService} from '../../packages/desktop/service.js';
import {byteHash,DocverError} from '../../packages/schema/index.js';

test('actual native import group/ungroup preserves IDs, labels, order, fingerprints and legacy create shape',{skip:process.platform!=='darwin'},async()=>{
 const root=await mkdtemp(join(tmpdir(),'docver-import-draft-'));try{
  await prepareLegacyNativeLocalization(root);
  const binary=join(root,'probe'),build=spawnSync('swiftc',['-warnings-as-errors','-swift-version','5','-parse-as-library','-target','arm64-apple-macos14.0',...nativeLocalizationTestSources,'apps/macos/Bridge.swift','apps/macos/Model.swift','tests/native/ImportDraft.swift','-o',binary,'-framework','SwiftUI','-framework','AppKit'],{encoding:'utf8',timeout:30000});assert.equal(build.status,0,build.stderr);assert.ifError(build.error);
  const run=spawnSync(binary,[join(root,'inputs')],{cwd:'/',encoding:'utf8',timeout:15000,env:{PATH:'/usr/bin:/bin',DOCVER_TEST_USER_DATA:join(root,'userdata')}});assert.equal(run.status,0,run.stderr);assert.ifError(run.error);assert.match(run.stdout,/PASS actual import draft identities/);
 }finally{await rm(root,{recursive:true,force:true});}
});

test('desktop create verifies picked bytes even after same-size same-mtime mutation and leaves projects unchanged',async()=>{
 const root=await mkdtemp(join(tmpdir(),'docver-import-identity-')),service=new DesktopService(join(root,'library'));try{
  const source=join(root,'selected.pdf'),bytes=Buffer.from('abc'),expected=byteHash(bytes);await writeFile(source,bytes);const selected=await stat(source);
  const good=await service.create('Selected bytes',[{label:'First',files:[source],expected_sha256:[expected]}]);assert.deepEqual(await readFile(join(service.root,'imports',good.revisions[0].files[0].blob)),bytes);assert.equal(service.manifest(good.project_id).revisions[0].files.length,1);assert.ok(!('expected_sha256' in good.revisions[0]));
  await writeFile(source,'abd');await utimes(source,selected.atime,selected.mtime);assert.equal((await stat(source)).size,bytes.length);
  await assert.rejects(service.create('Changed input',[{label:'Bad',files:[source],expected_sha256:[expected]}]),(e:unknown)=>e instanceof DocverError&&e.code==='SOURCE_CHANGED');assert.equal(service.projects().length,1);assert.equal((await readdir(join(service.root,'imports'))).length,1);
  await assert.rejects(service.create('Malformed identity',[{label:'Bad',files:[source],expected_sha256:[]}]),(e:unknown)=>e instanceof DocverError&&e.code==='INPUT_IDENTITY');assert.equal(service.projects().length,1);
  const legacy=await service.create('Legacy input',[{label:'Current bytes',files:[source]}]);assert.deepEqual(await readFile(join(service.root,'imports',legacy.revisions[0].files[0].blob)),Buffer.from('abd'));
 }finally{service.close();await rm(root,{recursive:true,force:true});}
});

test('actual native bridge create rejects mismatched selected identity and malformed counts',async()=>{
 const root=await mkdtemp(join(tmpdir(),'docver-bridge-import-')),source=join(root,'selected.pdf');try{
  await writeFile(source,'abd');
  const invoke=(expected_sha256:(string|null)[],files=[source])=>{const r=spawnSync(process.execPath,['--import','tsx',resolve('apps/bridge/main.ts'),'--root',join(root,'library')],{input:JSON.stringify({action:'create',args:{title:'Identity guard',revisions:[{label:'v1',files,expected_sha256}]}}),encoding:'utf8',timeout:20000});assert.ifError(r.error);assert.equal(r.status,1,r.stderr);return JSON.parse(r.stdout);};
  assert.equal(invoke([byteHash(Buffer.from('abc'))]).error.code,'SOURCE_CHANGED');assert.equal(invoke([]).ok,false);const legacy=join(root,'legacy.pptx');await writeFile(legacy,'legacy');assert.equal(invoke([byteHash(Buffer.from('abc')),null],[source,legacy]).error.code,'SOURCE_CHANGED');
  const service=new DesktopService(join(root,'library'));try{assert.deepEqual(service.projects(),[])}finally{service.close()}
 }finally{await rm(root,{recursive:true,force:true});}
});
