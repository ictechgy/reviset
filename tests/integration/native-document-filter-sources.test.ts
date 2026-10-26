import {nativeLocalizationTestSources,prepareLegacyNativeLocalization} from '../../scripts/native-swift-sources.js';
import {test} from 'node:test';import assert from 'node:assert/strict';import {mkdtemp,mkdir,writeFile,copyFile,symlink,rm} from 'node:fs/promises';import {tmpdir} from 'node:os';import {join,resolve} from 'node:path';import {execFileSync} from 'node:child_process';

test('native filters preserve verified intermediate sources and explicit same-question navigation retires detail',{skip:process.platform!=='darwin',timeout:45000},async()=>{
 const root=await mkdtemp(join(tmpdir(),'reviset-document-filter-sources-'));try{
  const contents=join(root,'Probe.app/Contents'),exe=join(contents,'MacOS/Probe');for(const folder of ['MacOS','Helpers','Resources/backend'])await mkdir(join(contents,folder),{recursive:true});
  await prepareLegacyNativeLocalization(join(contents,'Resources'));
  await writeFile(join(contents,'Info.plist'),'<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>Probe</string><key>CFBundleIdentifier</key><string>org.reviset.document-filter-sources</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>');
  await symlink(process.execPath,join(contents,'Helpers/node'));await copyFile(resolve('tests/native/workbook-read-fixture.mjs'),join(contents,'Resources/backend/bridge.mjs'));
  execFileSync('swiftc',['-warnings-as-errors','-swift-version','5','-parse-as-library','-target','arm64-apple-macos14.0',...nativeLocalizationTestSources,'apps/macos/Bridge.swift','apps/macos/Model.swift','tests/native/DocumentFilterSources.swift','-o',exe,'-framework','SwiftUI','-framework','AppKit'],{timeout:25000,stdio:'pipe'});
  const stdout=execFileSync(exe,[],{encoding:'utf8',timeout:20000,maxBuffer:1024*1024,env:{PATH:'/usr/bin:/bin',DOCVER_TEST_USER_DATA:join(root,'userdata')}});assert.match(stdout,/PASS native filtered document sources:/);
 }finally{await rm(root,{recursive:true,force:true});}
});
