import {nativeLocalizationTestSources,prepareLegacyNativeLocalization} from '../../scripts/native-swift-sources.js';
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,mkdir,writeFile,copyFile,symlink,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {execFileSync} from 'node:child_process';

test('native intervals, interrupted imports, document commit reconciliation and reused accessibility metadata stay truthful',{skip:process.platform!=='darwin'||process.arch!=='arm64',timeout:60_000},async()=>{
  const root=await mkdtemp(join(tmpdir(),'docver-native-reliability-'));
  try {
  await prepareLegacyNativeLocalization(join(root,'Probe.app/Contents/Resources'));
    const contents=join(root,'Probe.app/Contents'),exe=join(contents,'MacOS/Probe'),userData=join(root,'userdata');
    for(const folder of ['MacOS','Helpers','Resources/backend'])await mkdir(join(contents,folder),{recursive:true});
    await mkdir(userData);
    await writeFile(join(contents,'Info.plist'),'<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>Probe</string><key>CFBundleIdentifier</key><string>org.docver.reliability</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>');
    await symlink(process.execPath,join(contents,'Helpers/node'));
    await copyFile(resolve('tests/native/reliability-fixture.mjs'),join(contents,'Resources/backend/bridge.mjs'));
    execFileSync('swiftc',['-warnings-as-errors','-swift-version','5','-parse-as-library','-target','arm64-apple-macos14.0',...nativeLocalizationTestSources,'apps/macos/Bridge.swift','apps/macos/Model.swift','apps/macos/WorkbookView.swift','tests/native/Reliability.swift','-o',exe,'-framework','SwiftUI','-framework','AppKit'],{timeout:45_000,stdio:'pipe'});
    const stdout=execFileSync(exe,[],{encoding:'utf8',timeout:20_000,env:{PATH:'/usr/bin:/bin',DOCVER_TEST_USER_DATA:userData}});
    assert.match(stdout,/PASS native reliability:/);
  } finally { await rm(root,{recursive:true,force:true}); }
});
