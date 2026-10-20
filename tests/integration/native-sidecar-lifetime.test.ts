import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,mkdir,writeFile,copyFile,symlink,rm} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {execFileSync} from 'node:child_process';

test('native model owns sidecar replacement and dismissal without a view disappearance callback',{skip:process.platform!=='darwin',timeout:30000},async()=>{
  const root=await mkdtemp(join(tmpdir(),'docver-model-sidecar-'));try{
    const contents=join(root,'Probe.app/Contents'),resources=join(contents,'Resources'),executable=join(contents,'MacOS/Probe');
    for(const folder of [join(contents,'MacOS'),join(contents,'Helpers'),join(resources,'backend')])await mkdir(folder,{recursive:true});
    await writeFile(join(contents,'Info.plist'),'<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>Probe</string><key>CFBundleIdentifier</key><string>org.docver.sidecar-lifetime-fixture</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>');
    await symlink(process.execPath,join(contents,'Helpers/node'));await copyFile(resolve('tests/native/sidecar-lifecycle-fixture.mjs'),join(resources,'backend/bridge.mjs'));
    execFileSync('swiftc',['-warnings-as-errors','-swift-version','5','-parse-as-library','-target','arm64-apple-macos14.0','apps/macos/Bridge.swift','apps/macos/Model.swift','tests/native/SidecarLifetime.swift','-o',executable,'-framework','SwiftUI','-framework','AppKit'],{timeout:20000,stdio:'pipe'});
    const stdout=execFileSync(executable,[root],{timeout:7000,encoding:'utf8',env:{PATH:'/usr/bin:/bin',DOCVER_TEST_USER_DATA:join(root,'userdata')}});assert.match(stdout,/PASS model-owned immutable replacement\/dismissal/u);
  }finally{await rm(root,{recursive:true,force:true});}
});
