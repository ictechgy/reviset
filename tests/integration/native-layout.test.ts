import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {execFileSync} from 'node:child_process';
import {buildLocalizationResources} from '../../scripts/localization.js';

test('actual native customizable layouts preserve PDF/grid hosts and user state; preferences are bounded and isolated',{skip:process.platform!=='darwin',timeout:65_000},async()=>{
  const root=await mkdtemp(join(tmpdir(),'reviset-native-layout-'));
  try {
    await buildLocalizationResources(root);
    const binary=join(root,'probe');
    execFileSync('swiftc',['-swift-version','5','-warnings-as-errors','-parse-as-library','-target','arm64-apple-macos14.0','apps/macos/Localization.swift','apps/macos/WorkspaceLayout.swift','tests/native/WorkspaceLayoutChecks.swift','-o',binary,'-framework','SwiftUI','-framework','AppKit','-framework','PDFKit'],{timeout:45_000,stdio:'pipe'});
    const output=execFileSync(binary,[],{timeout:18_000,encoding:'utf8',env:{...process.env,DOCVER_TEST_USER_DATA:root}});
    assert.match(output,/PASS native customizable layouts: 15 transitions/);
  }finally{await rm(root,{recursive:true,force:true});}
});
