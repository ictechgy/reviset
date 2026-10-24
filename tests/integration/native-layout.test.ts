import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,rm,readFile,writeFile} from 'node:fs/promises';
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
    assert.match(output,/PASS native customizable layouts: 16 transitions/);
    const geometry=await readFile(join(root,'source-row-layout.json'),'utf8');
    const row=JSON.parse(geometry) as {width:number;height:number;minimum_text_width:number};
    assert.ok(row.width>=row.minimum_text_width && row.height<35);
    if (process.env.DOCVER_TEST_LAYOUT_EVIDENCE_OUT) await writeFile(process.env.DOCVER_TEST_LAYOUT_EVIDENCE_OUT,geometry);
  }finally{await rm(root,{recursive:true,force:true});}
});
