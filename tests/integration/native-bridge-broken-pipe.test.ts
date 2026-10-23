import {nativeLocalizationTestSources,prepareLegacyNativeLocalization} from '../../scripts/native-swift-sources.js';
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,mkdir,writeFile,symlink,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';

test('native host survives writing a large request to a helper that exits before reading',{skip:process.platform!=='darwin',timeout:45_000},async()=>{
  const root=await mkdtemp(join(tmpdir(),'docver-broken-pipe-'));
  try {
  await prepareLegacyNativeLocalization(join(root,'Probe.app/Contents/Resources'));
    const contents=join(root,'Probe.app/Contents'),exe=join(contents,'MacOS/Probe'),userData=join(root,'userdata');
    for(const folder of ['MacOS','Helpers','Resources/backend'])await mkdir(join(contents,folder),{recursive:true});
    await mkdir(userData);
    await writeFile(join(contents,'Info.plist'),'<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>Probe</string><key>CFBundleIdentifier</key><string>org.docver.broken-pipe</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>');
    await symlink(process.execPath,join(contents,'Helpers/node'));
    await writeFile(join(contents,'Resources/backend/bridge.mjs'),'process.exit(1);');
    const build=spawnSync('swiftc',['-warnings-as-errors','-swift-version','5','-parse-as-library',...nativeLocalizationTestSources,'apps/macos/Bridge.swift','tests/native/BridgeBrokenPipe.swift','-o',exe],{encoding:'utf8',timeout:30_000});
    assert.ifError(build.error);assert.equal(build.status,0,build.stderr);
    const run=spawnSync(exe,[],{encoding:'utf8',timeout:10_000,env:{PATH:'/usr/bin:/bin',DOCVER_TEST_USER_DATA:userData}});
    assert.ifError(run.error);assert.equal(run.signal,null,`Native host died from ${run.signal}`);assert.equal(run.status,0,run.stderr);
    assert.match(run.stdout,/PASS native broken pipe:/);
  } finally { await rm(root,{recursive:true,force:true}); }
});
