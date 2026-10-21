import {test} from 'node:test';import assert from 'node:assert/strict';import {mkdtemp,mkdir,writeFile,copyFile,symlink,rm}from'node:fs/promises';import{tmpdir}from'node:os';import{join,resolve}from'node:path';import{execFileSync}from'node:child_process';
test('native workflow rejects cross-project/ABA MCP configuration, stale selection and destructive reorder before explicit confirmation',{skip:process.platform!=='darwin',timeout:45000},async()=>{
 const root=await mkdtemp(join(tmpdir(),'docver-review-workflow-'));try{
  const contents=join(root,'Probe.app/Contents'),exe=join(contents,'MacOS/Probe');for(const folder of ['MacOS','Helpers','Resources/backend'])await mkdir(join(contents,folder),{recursive:true});
  await writeFile(join(contents,'Info.plist'),'<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>Probe</string><key>CFBundleIdentifier</key><string>org.docver.review-workflow</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>');await symlink(process.execPath,join(contents,'Helpers/node'));await copyFile(resolve('tests/native/review-workflow-fixture.mjs'),join(contents,'Resources/backend/bridge.mjs'));
  execFileSync('swiftc',['-warnings-as-errors','-swift-version','5','-parse-as-library','-target','arm64-apple-macos14.0','apps/macos/Bridge.swift','apps/macos/Model.swift','tests/native/ReviewWorkflow.swift','-o',exe,'-framework','SwiftUI','-framework','AppKit'],{timeout:20000,stdio:'pipe'});
  const stdout=execFileSync(exe,[],{encoding:'utf8',timeout:12000,env:{PATH:'/usr/bin:/bin',DOCVER_TEST_USER_DATA:join(root,'userdata')}});assert.match(stdout,/PASS actual native workflow:/);
 }finally{await rm(root,{recursive:true,force:true});}
});
