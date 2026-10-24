import {nativeLocalizationTestSources, prepareLegacyNativeLocalization} from '../../scripts/native-swift-sources.js';
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {execFileSync} from 'node:child_process';

test('native Git-inspired workspace preserves query/event scope, source semantics, bounded diffs and existing layouts', {skip:process.platform !== 'darwin', timeout:60_000}, async () => {
  const root=await mkdtemp(join(tmpdir(), 'reviset-git-workspace-'));
  try {
    await prepareLegacyNativeLocalization(root);
    const executable=join(root,'probe');
    execFileSync('swiftc', ['-warnings-as-errors','-swift-version','5','-parse-as-library','-target','arm64-apple-macos14.0',...nativeLocalizationTestSources,'apps/macos/Bridge.swift','apps/macos/Model.swift','apps/macos/WorkbookView.swift','tests/native/GitDiffWorkspace.swift','-o',executable,'-framework','SwiftUI','-framework','AppKit'], {timeout:45_000,stdio:'pipe'});
    const stdout=execFileSync(executable,[],{encoding:'utf8',timeout:10_000,env:{PATH:'/usr/bin:/bin',DOCVER_TEST_USER_DATA:join(root,'userdata')}});
    assert.match(stdout,/PASS native Git diff workspace:/u);
  } finally {await rm(root,{recursive:true,force:true});}
});
