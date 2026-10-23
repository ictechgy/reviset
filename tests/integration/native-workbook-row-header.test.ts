import {nativeLocalizationTestSources,prepareLegacyNativeLocalization} from '../../scripts/native-swift-sources.js';
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';

test('native row-header action preserves current physical column and shares selection guards',{skip:process.platform!=='darwin'||process.arch!=='arm64',timeout:60_000},async()=>{
  const root=await mkdtemp(join(tmpdir(),'reviset-row-header-'));
  try {
  await prepareLegacyNativeLocalization(root);
    const executable=join(root,'probe');
    const build=spawnSync('swiftc',['-warnings-as-errors','-swift-version','5','-parse-as-library','-target','arm64-apple-macos14.0',...nativeLocalizationTestSources,'apps/macos/Bridge.swift','apps/macos/Model.swift','apps/macos/WorkbookView.swift','tests/native/WorkbookRowHeader.swift','-o',executable,'-framework','SwiftUI','-framework','AppKit'],{encoding:'utf8',timeout:45_000});
    assert.ifError(build.error);assert.equal(build.status,0,build.stderr);
    const run=spawnSync(executable,[],{encoding:'utf8',timeout:10_000,env:{PATH:'/usr/bin:/bin'}});
    assert.ifError(run.error);assert.equal(run.status,0,run.stderr+run.stdout);assert.match(run.stdout,/PASS actual WorkbookGrid.Coordinator clicked/);
  } finally { await rm(root,{recursive:true,force:true}); }
});
