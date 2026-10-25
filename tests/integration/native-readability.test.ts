import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,rm,readFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {execFileSync} from 'node:child_process';
import {buildLocalizationResources} from '../../scripts/localization.js';

test('native interface text size recovers and persists independently; nested live hosts update without losing source or editor state',{skip:process.platform!=='darwin',timeout:65_000},async()=>{
  const root=await mkdtemp(join(tmpdir(),'reviset-native-readability-'));
  try {
    await buildLocalizationResources(root);
    const executable=join(root,'probe');
    execFileSync('swiftc',['-warnings-as-errors','-swift-version','5','-parse-as-library','-target','arm64-apple-macos14.0','apps/macos/Localization.swift','apps/macos/WorkspaceLayout.swift','tests/native/ReadabilityChecks.swift','-o',executable,'-framework','SwiftUI','-framework','AppKit','-framework','PDFKit'],{timeout:45_000,stdio:'pipe'});
    const persistentEnv={...process.env};delete persistentEnv.DOCVER_TEST_USER_DATA;
    assert.match(execFileSync(executable,['preferences'],{encoding:'utf8',timeout:5000,env:persistentEnv}),/PASS readability preference recovery, persistence and bounds/u);
    assert.match(execFileSync(executable,[],{encoding:'utf8',timeout:15_000,env:{...process.env,DOCVER_TEST_USER_DATA:root}}),/PASS live readability:/u);
    const result=JSON.parse(await readFile(join(root,'readability-observations.json'),'utf8')) as {observations:Array<{size:string;body_height:number;caption_height:number}>;native_hosts_retained:boolean;page_zoom_grid_viewport_draft_and_focus_retained:boolean};
    assert.deepEqual(result.observations.map(value=>value.size),['standard','large','extraLarge','standard']);
    assert.ok(result.observations[2]!.body_height>result.observations[0]!.body_height && result.observations[2]!.caption_height>result.observations[0]!.caption_height);
    assert.equal(result.native_hosts_retained,true);assert.equal(result.page_zoom_grid_viewport_draft_and_focus_retained,true);
  }finally{await rm(root,{recursive:true,force:true});}
});
